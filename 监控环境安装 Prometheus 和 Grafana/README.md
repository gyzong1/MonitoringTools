# JFrog Artifactory 监控
## 客户端配置（在所有Artifactory节点上）
解压并启动 node_exporter:
```bash
$ tar zxf jf_monitoring_node.tgz && cd jf_monitoring_node && tar zxf node_exporter-1.9.1.linux-amd64.tar.gz && cd node_exporter-1.9.1.linux-amd64
$ nohup ./node_exporter &
```
配置Artifactory（路径根据实际目录填写）
编辑 artifactory.default:
```bash
vim $ARTIFACTORY_HOME/app/bin/artifactory.default
```
添加客户端配置:
```sh
export JAVA_OPTS="-javaagent:/root/jf_monitoring_node/jmx_prometheus_javaagent-0.17.2.jar=30013:/root/jf_monitoring_node/jmx_config.yaml"
```
启动 Artifactory:
```bash
systemctl restart artifactory
```
## 服务端配置（任意一台空闲服务器）
解压 jf_monitoring.tgz:
```bash
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

监控截图:
Artifactory:
![image](https://github.com/user-attachments/assets/db5f71d8-5e22-4ddd-b23a-280d7bf2af55)

JVM:
![image](https://github.com/user-attachments/assets/c1ce1c7f-2c04-46a9-b922-71f5d5ad87af)

Node:
![image](https://github.com/user-attachments/assets/6a377737-a106-46cc-badb-b38be23f3b60)




