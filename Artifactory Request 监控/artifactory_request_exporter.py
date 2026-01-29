#!/usr/bin/env python3
"""
JFrog Artifactory Request Log Monitor

nohup python3 artifactory_request_exporter.py &

Change log:
2026.1.28 - Optimized that after log rotation, changes in the inode of artifactory-request.log prevent the script from continuing to retrieve metrics.
"""

import time
import threading
from collections import defaultdict, deque
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import os

# ========== Configuration ==========
LOG_FILE = '/var/opt/jfrog/artifactory/log/artifactory-request.log'
METRICS_PORT = 8002
WINDOW_SIZE = 15  # 统计窗口大小（秒）

COMMON_STATUS_CODES = [
    '200', '201', '204', '206', 
    '301', '302', '304', 
    '400', '401', '403', '404', '405', '409', '412',
    '500', '502', '503', '504'
]
# ===================================

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class LogEntry:
    __slots__ = ['method', 'status_code', 'upload_bytes', 'download_bytes', 'duration_ms']
    
    def __init__(self, line: str):
        parts = line.strip().split('|')
        if len(parts) < 10:
            raise ValueError("Invalid log format")
        
        self.method = parts[4]      
        self.status_code = parts[6]  
        
        up = parts[7]
        self.upload_bytes = int(up) if up.isdigit() or (up.startswith('-') and up == '-1') else 0
        if self.upload_bytes < 0: self.upload_bytes = 0
        
        dw = parts[8]
        self.download_bytes = int(dw) if dw.isdigit() or (dw.startswith('-') and dw == '-1') else 0
        if self.download_bytes < 0: self.download_bytes = 0
        
        self.duration_ms = int(parts[9]) if parts[9].replace('-','').isdigit() else 0

class ArtifactoryMetrics:
    def __init__(self):
        self.window_size = WINDOW_SIZE
        self.lock = threading.Lock()
        
        # 累计连接数值 (Counter)
        self.total_requests_counter = 0
        
        self.status_history = defaultdict(lambda: deque([0]*10, maxlen=10))
        
        self.latency_history = {
            'lt_5s': deque([0]*10, maxlen=10),
            '5s_10s': deque([0]*10, maxlen=10),
            '10s_20s': deque([0]*10, maxlen=10),
            'ge_20s': deque([0]*10, maxlen=10)
        }
        
        self.traffic_history = {
            'upload': deque([0]*10, maxlen=10),
            'download': deque([0]*10, maxlen=10)
        }
        
        self.current_window_id = int(time.time() / self.window_size)

    def _sync_window(self):
        now_id = int(time.time() / self.window_size)
        gap = now_id - self.current_window_id
        
        if gap > 0:
            steps = min(gap, 10)
            for _ in range(steps):
                for q in self.status_history.values(): q.append(0)
                for q in self.latency_history.values(): q.append(0)
                for q in self.traffic_history.values(): q.append(0)
            self.current_window_id = now_id

    def process_log_entry(self, entry: LogEntry):
        with self.lock:
            self._sync_window()
            # 1. 增加窗口内的状态码统计
            self.status_history[entry.status_code][-1] += 1
            
            # 2. 增加全局累计请求数 (Counter)
            self.total_requests_counter += 1
            
            # 耗时分段
            d = entry.duration_ms
            if d < 5000:
                self.latency_history['lt_5s'][-1] += 1
            elif 5000 <= d < 10000:
                self.latency_history['5s_10s'][-1] += 1
            elif 10000 <= d < 20000:
                self.latency_history['10s_20s'][-1] += 1
            else:
                self.latency_history['ge_20s'][-1] += 1
            
            self.traffic_history['upload'][-1] += entry.upload_bytes
            self.traffic_history['download'][-1] += entry.download_bytes

    def generate_metrics(self) -> str:
        with self.lock:
            self._sync_window()
            m = []
            
            # 1. 状态码 (Gauge)
            m.append(f"# HELP artifactory_status_codes_total Requests in last {self.window_size}s window")
            m.append("# TYPE artifactory_status_codes_total gauge")
            all_known_codes = sorted(list(set(COMMON_STATUS_CODES) | set(self.status_history.keys())))
            for code in all_known_codes:
                val = self.status_history[code][-1] if code in self.status_history else 0
                m.append(f'artifactory_status_codes_total{{code="{code}"}} {val}')
            
            # 2. 耗时分布 (Gauge)
            m.append(f"\n# HELP artifactory_request_duration_seconds Request count by duration tier in last {self.window_size}s")
            m.append("# TYPE artifactory_request_duration_seconds gauge")
            for tier, history in self.latency_history.items():
                m.append(f'artifactory_request_duration_seconds{{tier="{tier}"}} {history[-1]}')
            
            # 3. 流量 (Gauge)
            m.append(f"\n# HELP artifactory_traffic_bytes Traffic in last {self.window_size}s window")
            m.append("# TYPE artifactory_traffic_bytes gauge")
            m.append(f'artifactory_traffic_bytes{{direction="upload"}} {self.traffic_history["upload"][-1]}')
            m.append(f'artifactory_traffic_bytes{{direction="download"}} {self.traffic_history["download"][-1]}')
            
            # 4. 请求数汇总
            # 4a. 实时窗口请求数 (Gauge)
            total_req_window = sum(h[-1] for h in self.status_history.values())
            m.append(f"\n# HELP artifactory_requests_in_window Total requests in current {self.window_size}s window")
            m.append("# TYPE artifactory_requests_in_window gauge")
            m.append(f'artifactory_requests_in_window {total_req_window}')
            
            # 4b. 历史累积请求总数 (Counter)
            m.append("\n# HELP artifactory_requests_total Cumulative total requests since exporter start")
            m.append("# TYPE artifactory_requests_total counter")
            m.append(f'artifactory_requests_total {self.total_requests_counter}')

            m.append(f'\nartifactory_metrics_timestamp {time.time()}')
            
            return "\n".join(m)

class LogTailer:
    def __init__(self, log_file: str, metrics: ArtifactoryMetrics):
        self.log_file = log_file
        self.metrics = metrics
        self.running = False

    def get_inode(self):
        """获取当前日志文件的 inode，如果文件不存在返回 None"""
        try:
            return os.stat(self.log_file).st_ino
        except FileNotFoundError:
            return None

    def start(self):
        self.running = True
        logger.info(f"Monitoring {self.log_file}")
        
        while self.running:
            last_inode = self.get_inode()
            try:
                with open(self.log_file, 'r', errors='ignore') as f:
                    # 首次启动跳到末尾；如果是轮转后重新打开，则从头开始读
                    # 注意：这里通过判断上一次 inode 是否存在来决定
                    f.seek(0, 2) 
                    
                    while self.running:
                        line = f.readline()
                        if not line:
                            # 读到末尾，检查文件是否被轮转
                            current_inode = self.get_inode()
                            if current_inode != last_inode:
                                logger.info("Log rotation detected, reopening file...")
                                break  # 跳出内层循环，重新触发 with open
                            
                            time.sleep(0.1)
                            continue
                            
                        try:
                            self.metrics.process_log_entry(LogEntry(line))
                        except Exception:
                            continue
                            
            except FileNotFoundError:
                logger.warning(f"Log file {self.log_file} not found, retrying...")
                time.sleep(5)
            except Exception as e:
                logger.error(f"Tailer error: {e}")
                time.sleep(1)

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4')
            self.end_headers()
            self.wfile.write(metrics_collector.generate_metrics().encode('utf-8'))
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
    def log_message(self, format, *args): return

def main():
    global metrics_collector
    metrics_collector = ArtifactoryMetrics()
    tailer = LogTailer(LOG_FILE, metrics_collector)
    threading.Thread(target=tailer.start, daemon=True).start()
    server = HTTPServer(('0.0.0.0', METRICS_PORT), MetricsHandler)
    logger.info(f"Server started on port {METRICS_PORT} (15s Window)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()

if __name__ == "__main__":
    main()