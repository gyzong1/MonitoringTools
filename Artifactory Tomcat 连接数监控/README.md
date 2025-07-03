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
