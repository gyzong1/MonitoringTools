## tomcat_threads_exporter 安装（在所有Artifactory节点上）
安装 python3 (如已安装请跳过):
```bash
yum install -y python3 python3-pip
```
安装 tomcat_threads_exporter 需要的模块:
```bash
pip3 install prometheus_client
```
根据实际情况修改 tomcat_threads_exporter.py 以下部分:
```python
CONFIG = {
    "use_docker": True,                  # 是否使用 Docker 环境
    "container_name": "artifactory-7.111.10",  # Docker 容器名称
...
}
```
运行:
```bash
nohup python3 tomcat_threads_exporter.py &
```
查看是否展示数据:
```bash
curl http://127.0.0.1:8000/metrics
```
### Prometheus 配置添加:
编辑 prometheus.yml:
```bash
vim MonitoringTools/jf_monitoring/prometheus/config/prometheus.yml
```
添加以下配置:
```bash
scrape_configs:
  - job_name: 'tcp_8081_exporter'
    static_configs:
      - targets: ['198.19.249.230:8000']
```
重启 Prometheus:
```bash
docker restart prometheus
```

### 上传 dashboard:
**Dashboards** | **New dashboard**, 上传 "Artifactory Dashboard-latest.json":
<img width="1751" alt="image" src="https://github.com/gyzong1/MonitoringTools/blob/46d0406db252c16e87bebc5db3524ac9d4dae616/JVM%20%E7%9B%91%E6%8E%A7/images/jvm_dashboard.png">

