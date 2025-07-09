### 部署 jmx_exporter
下载 jmx_exporter:
```bash
cd /opt/jf_monitoring_node/
wget https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.17.2/jmx_prometheus_javaagent-0.17.2.jar
```
创建 jmx_exporter 配置:
```bash
vim /opt/jf_monitoring_node/jmx_config.yaml
添加以下内容:
---
lowercaseOutputLabelNames: true
lowercaseOutputName: true

rules:
- pattern: ".*"
```

### Artifactory 配置添加 jmx（路径根据实际目录填写）
编辑 artifactory.default:
```bash
vim $ARTIFACTORY_HOME/var/etc/system.yaml
```
添加客户端配置:
```bash
shared:
    extraJavaOpts: "-Xms512m -Xmx4g -javaagent:/opt/jf_monitoring_node/jmx_prometheus_javaagent-0.17.2.jar=30013:/opt/jf_monitoring_node/jmx_config.yaml"
```
重启 Artifactory:
```bash
systemctl restart artifactory
```
测试:
```bash
curl http://198.19.249.230:30013/metrics
```
