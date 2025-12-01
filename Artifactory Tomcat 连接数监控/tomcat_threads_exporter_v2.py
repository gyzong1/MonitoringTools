#!/usr/bin/env python3

'''
由监控一个端口增加到了可以多个端口, 使用:
pip3 install prometheus_client
python3 tomcat_threads_monitoring_v2.py
'''

from prometheus_client import start_http_server, Gauge
import subprocess
import time
import os

# 配置区域 ==============================================================
CONFIG = {
    "use_docker": True,                  # 是否使用Docker环境
    "container_name": "artifactory-7.104.14",  # Docker容器名称
    "monitor_ports": ["8081", "8082"],    # 【改造点1】要监控的端口列表
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
# 【改造点2】指标定义不变，但标签 'port' 的值会是列表中的每一个端口
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

def build_netstat_cmd(port, filter_type): # 【改造点3】函数增加 port 参数
    """构建netstat命令，接收端口和过滤类型作为参数"""
    base = CONFIG["commands"]["base_netstat"]
    filter_str = CONFIG["commands"][f"{filter_type}_filter"]
    
    if CONFIG["use_docker"]:
        # 注意：这里使用传入的 port 变量
        return f'docker exec -i {CONFIG["container_name"]} bash -c "{base} | grep \':{port}\' | grep {filter_str} | wc -l"'
    else:
        # 注意：这里使用传入的 port 变量
        return f'{base} | grep :{port} | grep {filter_str} | wc -l'

def get_connection_counts_for_port(port): # 【改造点4】为新函数命名，接收端口参数
    """为指定端口获取连接数"""
    established_cmd = build_netstat_cmd(port, "established")
    timewait_cmd = build_netstat_cmd(port, "timewait")
    
    return (
        execute_command(established_cmd),
        execute_command(timewait_cmd)
    )

def update_metrics():
    """定期更新所有端口的指标"""
    while True:
        all_ports = CONFIG["monitor_ports"]
        print(f"Updating metrics for ports: {', '.join(all_ports)}...") # 打印正在更新的端口
        
        for port in all_ports: # 【改造点5】遍历端口列表
            established, timewait = get_connection_counts_for_port(port)
            port_label = {'port': port} # 为每个端口创建标签
            
            # 更新 Prometheus 指标，标签为当前端口
            metrics['established'].labels(**port_label).set(established)
            metrics['timewait'].labels(**port_label).set(timewait)
            # 可选：在控制台打印实时值
            print(f"Port {port}: ESTABLISHED={established}, TIME_WAIT={timewait}")

        time.sleep(CONFIG["refresh_interval"])

if __name__ == '__main__':    
    # 启动Prometheus指标服务
    start_http_server(CONFIG["exporter_port"])
    print(f"Exporter started on port {CONFIG['exporter_port']}")
    
    # 根据监控模式打印不同的信息
    if CONFIG['use_docker']:
        container_info = f"Docker container '{CONFIG['container_name']}'"
    else:
        container_info = "host machine"
    # 【改造点6】打印所有监控的端口
    monitored_ports_str = ", ".join(CONFIG['monitor_ports'])
    print(f"Monitoring ports [{monitored_ports_str}] on {container_info}")
    
    # 更新指标
    update_metrics()
