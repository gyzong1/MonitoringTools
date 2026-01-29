## JFrog Artifactory Request Log Monitor

下载脚本至 Artifactory 节点服务器, 根据实际日志路径修改如下配置:
```
# ========== Configuration ==========
LOG_FILE = '/var/opt/jfrog/artifactory/log/artifactory-request.log'
```
启动:
```bash
nohup python3 artifactory_request_exporter.py &
```