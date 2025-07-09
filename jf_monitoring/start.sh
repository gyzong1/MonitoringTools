#!/bin/bash
# jf_monitoring environment installation

Jf_monitoring_Home=`pwd`

docker_installation(){
echo -e "Home path: ${Jf_monitoring_Home}"
echo -e "Install docker..."

# online
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install docker-ce -y
systemctl enable docker && systemctl start docker

# offline
# cd ${Jf_monitoring_Home}/init && chmod +x install-docker-ce.sh && ./install-docker-ce.sh docker-23.0.0.tgz && rm -rf docker

}

docker_compose_installation(){
echo -e "Home path: ${Jf_monitoring_Home}"
echo -e "Install docker-compose..."

# online
curl -L "https://github.com/docker/compose/releases/download/v2.38.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# offline
# 

}

jf_monitoring(){
cd ${Jf_monitoring_Home}

read -p "Please input the local ip of this server, for example: 192.168.56.13 : " answer
localIp=$answer

read -p "Please input Artifactory node ip, for example: 192.168.56.14 :" answer
ip=($answer)
# ip=($answer)
# num=${#ip[*]}
# for j in $(seq 0 $num);
# do
#   eval ip"$j"=${ip[${j}]}
# done

read -p "Please written Artifactory Credentials(Identity Token), 'Admin'--'Edit Profile'--'Generate an Identity Token' :" answer
Credentials=$answer

echo -e  "Install jf_monitoring..."

## offline
# docker load -i init/images/prometheus-v2.53.4.tar
# docker load -i /root/blackbox-exporter-v0.26.0.tar 
# docker load -i init/images/grafana-11.6.0.tar

touch ./prometheus/config/prometheus.yml
cat > ./prometheus/config/prometheus.yml << EOF
global:
  scrape_interval:     15s # By default, scrape targets every 15 seconds.
  external_labels:
    monitor: 'line-monitor'

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: 'node-monitor'
    scrape_interval: 5s
    static_configs:
      - targets: ['$ip:9100']

  - job_name: 'jvm-monitor'
    scrape_interval: 5s
    static_configs:
      - targets: ['$ip:30013']

  - job_name: 'artifactory-monitor'
    scrape_interval: 5s
    authorization: 
      credentials: $Credentials
    metrics_path: '/artifactory/api/v1/metrics'
    static_configs:
      - targets: ['$ip:8082']

  - job_name: "blackbox_telnet_port"
    scrape_interval: 5s
    metrics_path: /probe
    params:
      module: [tcp_connect]
    static_configs:
      - targets: [ '$ip:8082' ]
        labels:
          group: 'artifactory'
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: $ip:9115

  - job_name: 'http-blackbox'
    metrics_path: /probe
    params:
      module: [http_2xx]  # Look for a HTTP 200 response.
    static_configs:
      - targets:
        - http://$ip:8082/artifactory/api/system/ping
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: $ip:9115  # The blackbox exporter's real hostname:port.

  - job_name: 'tcp_8081_exporter'
    static_configs:
      - targets: ['$ip::8000']
EOF


chmod -R 777 ${Jf_monitoring_Home}/prometheus/data ${Jf_monitoring_Home}/grafana/data
docker-compose up -d

curl -X POST -H "Content-Type: application/json" "http://admin:admin@${localIp}:3000/api/datasources" -d '{"name":"Prometheus","type":"prometheus","typeLogoUrl":"","access":"proxy","url":"http://'${localIp}':9090","user":"","database":"","basicAuth":false,"basicAuthUser":"","withCredentials":false,"isDefault":true,"jsonData":{"httpMethod":"POST"},"secureJsonFields":{},"version":2,"readOnly":false}' > /dev/null 2>&1

sleep 1
echo -e "\n"
echo -e "\033[32;1mPrometheus and Grafana start and configed Successflly!\033[0m"
echo -e "\n"
echo -e "\033[33;1mPrometheus's url: \033[32;1mhttp://${localIp}:9090\033[0m"
echo -e "\n"
echo -e "\033[33;1mGrafana's url: \033[32;1mhttp://${localIp}:3000\033[0m"
echo -e "\033[33;1mGrafana's account/password: \033[32;1madmin/admin\033[0m"
}

# read -p "Do you need to install docker? (yes/no)" answer
# case $answer in
# yes|y|Y)
#       docker_installation
#       sleep 2
# ;;
# *)
#       echo "Input wrong."
#       exit 1
# ;;
# esac

# read -p "Do you need to install docker-compose? (yes/no)? " answer
# case $answer in
# yes|y|Y)
#       docker_compose_installation
#       jf_monitoring
#       sleep 2
# ;;
# No|n|N)
#       jf_monitoring
# ;;
# *)
#       echo "Input wrong."
#       exit 1
# ;;
# esac

read -p "Do you need to install Docker? (yes/no): " docker_answer
case $docker_answer in
    yes|y|Y)
        docker_installation
        ;;
    no|n|N)
        ;;
    *)
        echo "Invalid input for Docker installation. Exiting."
        exit 1
        ;;
esac

read -p "Do you need to install Docker Compose? (yes/no): " compose_answer
case $compose_answer in
    yes|y|Y)
        docker_compose_installation
        jf_monitoring
        ;;
    no|n|N)
        jf_monitoring
        ;;
    *)
        echo "Invalid input for Docker Compose installation. Exiting."
        exit 1
        ;;
esac
