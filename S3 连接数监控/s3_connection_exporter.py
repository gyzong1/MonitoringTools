#!/usr/bin/env python3

"""
S3 Connection Pool Monitor:
chmod +x s3_connection_exporter.py
nohup python3 s3_connection_exporter.py &
"""

import os
import time
import re
import threading
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler

# ============ 变量配置 ============
LOG_FILE_PATH = '/var/opt/jfrog/artifactory/log/artifactory-connectionpool.log'
HTTP_PORT = 8001
WINDOW_SIZE = 15
# =================================

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class S3ConnectionMetrics:
    def __init__(self):
        self.lock = threading.Lock()
        self.current_connections = 0
        self.max_connections = 50
        # 记录最近一次看到的值，防止日志静默时指标直接跳 0（针对连接池状态）
        self.last_update_time = time.time()
        
    def parse_log_line(self, line):
        """解析日志行，提取连接数信息"""
        # 匹配逻辑：Connection request ... total allocated: 12 of 50
        if 'total allocated:' in line:
            pattern = r'total allocated: (\d+) of (\d+)'
            match = re.search(pattern, line)
            if match:
                try:
                    return int(match.group(1)), int(match.group(2))
                except ValueError:
                    pass
        return None, None

    def update(self, current, max_conn):
        with self.lock:
            self.current_connections = current
            self.max_connections = max_conn
            self.last_update_time = time.time()

    def generate_metrics(self):
        with self.lock:
            # 如果超过 60s 没收到新日志，连接池可能已空或静默
            # 这里可以根据业务决定是否要清零。连接池通常在没日志时代表没变化，所以保留旧值
            curr = self.current_connections
            mx = self.max_connections
        
        usage_pct = (curr / mx * 100) if mx > 0 else 0
        
        metrics = [
            f'# HELP s3_connection_current Current S3 connections in use',
            f'# TYPE s3_connection_current gauge',
            f's3_connection_current{{source="artifactory",target="localhost:8046"}} {curr}',
            f'',
            f'# HELP s3_connection_max Maximum S3 connections allowed',
            f'# TYPE s3_connection_max gauge',
            f's3_connection_max{{source="artifactory",target="localhost:8046"}} {mx}',
            f'',
            f'# HELP s3_connection_usage_percentage Percentage of S3 connections in use',
            f'# TYPE s3_connection_usage_percentage gauge',
            f's3_connection_usage_percentage{{source="artifactory",target="localhost:8046"}} {usage_pct:.2f}',
            f'',
            f'# HELP s3_connection_available Available S3 connections',
            f'# TYPE s3_connection_available gauge',
            f's3_connection_available{{source="artifactory",target="localhost:8046"}} {mx - curr}',
            f'',
            f'artifactory_s3_metrics_timestamp {time.time()}'
        ]
        return "\n".join(metrics)

class LogTailer:
    def __init__(self, log_file, metrics):
        self.log_file = log_file
        self.metrics = metrics

    def get_inode(self):
        try:
            return os.stat(self.log_file).st_ino
        except FileNotFoundError:
            return None

    def start(self):
        logger.info(f"Starting LogTailer for {self.log_file}")
        while True:
            last_inode = self.get_inode()
            try:
                with open(self.log_file, 'r', errors='ignore') as f:
                    # 第一次打开跳到末尾
                    f.seek(0, 2)
                    while True:
                        line = f.readline()
                        if not line:
                            # 检查 inode 是否变化（轮转检查）
                            if self.get_inode() != last_inode:
                                logger.info("Log rotation detected in connectionpool.log")
                                break
                            time.sleep(1)
                            continue
                        
                        curr, mx = self.metrics.parse_log_line(line)
                        if curr is not None:
                            self.metrics.update(curr, mx)
            except FileNotFoundError:
                time.sleep(5)
            except Exception as e:
                logger.error(f"Tailer Error: {e}")
                time.sleep(2)

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4')
            self.end_headers()
            self.wfile.write(metrics_collector.generate_metrics().encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args): return

def main():
    global metrics_collector
    metrics_collector = S3ConnectionMetrics()
    
    # 启动日志监听线程
    tailer = LogTailer(LOG_FILE_PATH, metrics_collector)
    threading.Thread(target=tailer.start, daemon=True).start()
    
    # 启动服务器
    server = HTTPServer(('0.0.0.0', HTTP_PORT), MetricsHandler)
    logger.info(f"S3 Metrics Exporter running on port {HTTP_PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()

if __name__ == "__main__":
    main()