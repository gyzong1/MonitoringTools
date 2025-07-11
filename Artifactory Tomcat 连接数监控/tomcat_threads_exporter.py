#!/usr/bin/env python3
from prometheus_client import start_http_server, Gauge
import subprocess
import time
import os

# 配置区域 ==============================================================
CONFIG = {
    "use_docker": True,                  # 是否使用Docker环境
    "container_name": "artifactory-7.104.14",  # Docker容器名称
    "monitor_port": "8081",              # 要监控的端口
    "exporter_port": 8000,               # Exporter服务端口
    "refresh_interval": 5,               # 数据刷新间隔(秒)
    
    # 命令配置
    "commands": {
        "base_netstat": "netstat -anpt",  # 基础netstat命令
        "established_filter": "ESTABLISHED",
        "timewait_filter": "TIME_WAIT"
    }
}
# ======================================================================

# 创建Prometheus指标
metrics = {
    'established': Gauge('tcp_port_established', 'Number of ESTABLISHED connections', ['port']),
    'timewait': Gauge('tcp_port_timewait', 'Number of TIME_WAIT connections', ['port'])
}

def execute_command(cmd):
    """执行命令并返回整数结果"""
    try:
        result = subprocess.getoutput(cmd)
        return int(result.strip() or 0)
    except Exception as e:
        print(f"Command execution error: {e}\nCommand: {cmd}")
        return 0

def build_netstat_cmd(filter_type):
    """构建netstat命令"""
    base = CONFIG["commands"]["base_netstat"]
    port = CONFIG["monitor_port"]
    filter_str = CONFIG["commands"][f"{filter_type}_filter"]
    
    if CONFIG["use_docker"]:
        return f'docker exec -i {CONFIG["container_name"]} bash -c "{base} | grep \':{port}\' | grep {filter_str} | wc -l"'
    else:
        return f'{base} | grep :{port} | grep {filter_str} | wc -l'

def get_connection_counts():
    """获取连接数"""
    established_cmd = build_netstat_cmd("established")
    timewait_cmd = build_netstat_cmd("timewait")
    
    return (
        execute_command(established_cmd),
        execute_command(timewait_cmd)
    )

def update_metrics():
    """定期更新指标"""
    while True:
        established, timewait = get_connection_counts()
        port_label = {'port': CONFIG["monitor_port"]}
        
        metrics['established'].labels(**port_label).set(established)
        metrics['timewait'].labels(**port_label).set(timewait)
        
        time.sleep(CONFIG["refresh_interval"])

if __name__ == '__main__':    
    # 启动Prometheus指标服务
    start_http_server(CONFIG["exporter_port"])
    print(f"Exporter started on port {CONFIG['exporter_port']}")
    print(f"Monitoring {'Docker container' if CONFIG['use_docker'] else 'host'} port {CONFIG['monitor_port']}")
    
    # 更新指标
    update_metrics()
