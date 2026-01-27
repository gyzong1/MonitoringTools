#!/usr/bin/env python3

'''
使用:
pip3 install prometheus-client
chmod +x s3_connection_exporter.py
nohup python3 s3_connection_exporter.py &
'''

import subprocess
import time
import re
import sys
from datetime import datetime
import threading

# ============ 配置变量 ============
LOG_FILE_PATH = '/var/opt/jfrog/artifactory/log/artifactory-connectionpool.log'
HTTP_PORT = 8001
# =================================

class S3ConnectionMetrics:
    def __init__(self, log_file_path=LOG_FILE_PATH):
        self.current_connections = 0
        self.max_connections = 50
        self.lock = threading.Lock()
        self.running = True
        self.log_file_path = log_file_path
        
    def parse_log_line(self, line):
        """解析日志行，提取连接数信息"""
        pattern = r'total allocated: (\d+) of (\d+)'
        match = re.search(pattern, line)
        if match:
            try:
                current = int(match.group(1))
                max_conn = int(match.group(2))
                return current, max_conn
            except ValueError:
                pass
        return None, None
    
    def get_latest_log(self):
        """获取最新的日志行"""
        try:
            # 执行命令获取最新日志
            cmd = [
                'tail', '-n', '100', self.log_file_path
            ]
            
            # 如果文件不存在，返回None
            try:
                result = subprocess.run(
                    cmd, 
                    capture_output=True, 
                    text=True, 
                    timeout=5
                )
            except FileNotFoundError:
                print(f"# ERROR: Log file not found: {self.log_file_path}")
                return None
                
            if result.returncode != 0:
                print(f"# ERROR: Command failed: {result.stderr}")
                return None
                
            # 过滤包含连接请求的行
            lines = result.stdout.strip().split('\n')
            connection_lines = []
            
            for line in lines:
                if ('Connection request' in line and 
                    'http-nio-8081-exec' in line and
                    'total allocated:' in line):
                    connection_lines.append(line)
            
            # 返回最新的行
            if connection_lines:
                return connection_lines[-1]
                
        except subprocess.TimeoutExpired:
            print("# ERROR: Command timeout")
        except Exception as e:
            print(f"# ERROR: {str(e)}")
            
        return None
    
    def update_metrics(self):
        """更新metrics"""
        latest_log = self.get_latest_log()
        if latest_log:
            current, max_conn = self.parse_log_line(latest_log)
            if current is not None:
                with self.lock:
                    self.current_connections = current
                    if max_conn:
                        self.max_connections = max_conn
                return True
        return False
    
    def generate_metrics(self):
        """生成Prometheus格式的metrics"""
        with self.lock:
            current = self.current_connections
            max_conn = self.max_connections
        
        timestamp = int(time.time() * 1000)
        
        metrics = f"""# HELP s3_connection_current Current S3 connections in use
# TYPE s3_connection_current gauge
s3_connection_current{{source="artifactory",target="localhost:8046"}} {current}

# HELP s3_connection_max Maximum S3 connections allowed
# TYPE s3_connection_max gauge
s3_connection_max{{source="artifactory",target="localhost:8046"}} {max_conn}

# HELP s3_connection_usage_percentage Percentage of S3 connections in use
# TYPE s3_connection_usage_percentage gauge
s3_connection_usage_percentage{{source="artifactory",target="localhost:8046"}} {(current/max_conn*100) if max_conn > 0 else 0}

# HELP s3_connection_available Available S3 connections
# TYPE s3_connection_available gauge
s3_connection_available{{source="artifactory",target="localhost:8046"}} {max_conn - current}
"""
        return metrics
    
    def run(self):
        """主循环"""
        print(f"# Starting S3 Connection Metrics Exporter")
        print(f"# Monitoring log file: {self.log_file_path}")
        print(f"# Metrics available at http://localhost:{HTTP_PORT}/metrics")
        
        while self.running:
            try:
                success = self.update_metrics()
                if not success:
                    print("# WARNING: Failed to update metrics")
                
                time.sleep(5)
            except KeyboardInterrupt:
                print("\n# Shutting down...")
                self.running = False
            except Exception as e:
                print(f"# ERROR in main loop: {str(e)}")
                time.sleep(5)

def run_http_server(metrics_collector, port=HTTP_PORT):
    """运行简单的HTTP服务器提供metrics"""
    from http.server import HTTPServer, BaseHTTPRequestHandler
    
    class MetricsHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/metrics':
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain; version=0.0.4')
                self.end_headers()
                metrics = metrics_collector.generate_metrics()
                self.wfile.write(metrics.encode())
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b'Not Found')
    
        def log_message(self, format, *args):
            # 禁用默认的日志输出
            pass
    
    server = HTTPServer(('', port), MetricsHandler)
    print(f"# HTTP server started on port {port}")
    server.serve_forever()

def main():
    """主函数"""
    # 检查必要的命令是否存在
    try:
        subprocess.run(['tail', '--version'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("ERROR: 'tail' command not found or not working")
        sys.exit(1)
    
    # 创建metrics收集器
    metrics_collector = S3ConnectionMetrics()
    
    # 启动HTTP服务器线程
    server_thread = threading.Thread(
        target=run_http_server, 
        args=(metrics_collector,),
        daemon=True
    )
    server_thread.start()
    
    # 运行主循环
    metrics_collector.run()

if __name__ == "__main__":
    main()