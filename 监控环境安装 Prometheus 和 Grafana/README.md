# JFrog Artifactory 监控
## 客户端配置（在所有Artifactory节点上）
### 部署 node_exporter
创建安装目录:
```bash
mkdir /opt/jf_monitoring_node/ && cd /opt/jf_monitoring_node/
```
下载 node_exporter:
```bash
# amd64
wget https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-amd64.tar.gz
# arm64
wget https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-arm64.tar.gz
```
解压并启动 node_exporter(amd64为例):
```bash
$ tar zxf node_exporter-1.9.1.linux-amd64.tar.gz && cd node_exporter-1.9.1.linux-amd64
$ nohup ./node_exporter &
```
测试:
```bash
curl http://localhost:9100/metrics
```
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
编辑 system.yaml:
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
curl http://localhost:30013/metrics
```

### Artifactory 配置开启 metrics
编辑 system.yaml:
```bash
vim $ARTIFACTORY_HOME/var/etc/system.yaml
```
添加配置:
```bash
artifactory:
    metrics:
        enabled: true
access:
    metrics:
        enabled: true
event:
    metrics:
        enabled: true

integration:
    metrics:
        enabled: true

observability:
    metrics:
        enabled: true
```
重启 Artifactory:
```bash
systemctl restart artifactory
```
测试:
```bash
curl -uadmin:password http://localhost:8082/artifactory/api/v1/metrics
```


## 服务端配置（任意一台空闲服务器）
创建安装目录:
```bash
mkdir /opt/jf_monitoring/ && cd /opt/jf_monitoring/
```
下载 jf_monitoring.tgz:
```bash
git clone https://github.com/gyzong1/MonitoringTools.git
```
解压 jf_monitoring.tgz:
```bash
cd /opt/jf_monitoring/MonitoringTools/packages/
tar zxf jf_monitoring.tgz && cd jf_monitoring && chmod +x start.sh
```
安装 jf_monitoring:
```bash
./start.sh
```
按提示输入“是否安装docker环境”、“本机 IP”、“Artifactory节点 IP”、“Artifactory Identity Token”，示例如:
```txt
[root@nexus jf_monitoring]# ./start.sh
Do you need to install Docker and Docker Compose? default(y/yes), change(n/no)? y
Please write the local IP of this server, [for example, 192.168.56.13]: 192.168.56.13
Please write the Artifactory node IP, [for example 192.168.56.14]: 192.168.56.14
Please written Artifactory Credentials(Identity Token), 'admin'--'Edit Profile'--'Generate an Identity Token' : <token>
```
![image](https://github.com/user-attachments/assets/10e2e560-770e-4240-9584-6e7f4dcb493f)

### 访问 Grafana（admim/admin）, 添加 Prometheus 源:  
**Connections** | **Data sources** | **Add new data source** | 选择 **Prometheus** | 填入 **Prometheus server URL**, 如: http://198.19.249.230:9090

### 添加 Grafana dashboard:
**Dashboard** | **New** | **New dashboard** | **Import a dashboard**，添加 "Artifactory Dashboard-latest.json", "JVM Dashboard-latest.json", "Node Exporter Full-latest.json"(已添加请忽略).

监控截图:  
Artifactory:
![image](https://github.com/gyzong1/MonitoringTools/blob/5e588cc5ae44b1d192a4f049a92a17a9d500af46/%E7%9B%91%E6%8E%A7%E7%8E%AF%E5%A2%83%E5%AE%89%E8%A3%85%20Prometheus%20%E5%92%8C%20Grafana/images/Artifactory%20dashboard.png)

JVM:
![image](https://github.com/gyzong1/MonitoringTools/blob/286f1389a1a9f5456cd8fdb0798b4e38ecde2646/JVM%20%E7%9B%91%E6%8E%A7/images/jvm_dashboard.png)

Node:
![image](https://github.com/gyzong1/MonitoringTools/blob/8ca8313d326815f2b39c7236f963221427994e01/%E7%9B%91%E6%8E%A7%E7%8E%AF%E5%A2%83%E5%AE%89%E8%A3%85%20Prometheus%20%E5%92%8C%20Grafana/images/Node_dashboard.png)





