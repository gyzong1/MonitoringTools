#!/bin/bash
# jf_monitoring environment installation

Jf_monitoring_Home=`pwd`

docker_installation(){
echo -e "Home path: ${Jf_monitoring_Home}"
echo -e "Install docker..."

cd ${Jf_monitoring_Home}/init && chmod +x install-docker-ce.sh && ./install-docker-ce.sh docker-23.0.0.tgz && rm -rf docker
}

jf_monitoring(){
cd ${Jf_monitoring_Home}

read -p "Please written the local ip of this server, for example: 192.168.56.13 : " answer
localIp=$answer

read -p "Please written Artifactory node ip, for example: 192.168.56.14 192.168.56.13 :" answer
ip=($answer)
num=${#ip[*]}
for j in $(seq 0 $num);
do
  eval ip"$j"=${ip[${j}]}
done

read -p "Please written Artifactory Credentials(Identity Token), 'admin'--'Edit Profile'--'Generate an Identity Token' :" answer
Credentials=$answer

echo -e  "Install jf_monitoring..."
docker load -i init/images/prometheus-v2.53.4.tar
docker load -i init/images/grafana-11.6.0.tar

cat > prometheus/config/prometheus.yml << EOF
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
      - targets: ['$ip0:9100', '$ip1:9100', '$ip2:9100', '$ip3:9100', '$ip4:9100', '$ip5:9100', '$ip6:9100']

  - job_name: 'jvm-monitor'
    scrape_interval: 5s
    static_configs:
      - targets: ['$ip0:30013', '$ip1:30013', '$ip2:30013', '$ip3:30013', '$ip4:30013', '$ip5:30013','$ip6:30013']

  - job_name: 'artifactory-monitor'
    scrape_interval: 5s
    authorization: 
      credentials: $Credentials
    metrics_path: '/artifactory/api/v1/metrics'
    static_configs:
      - targets: ['$ip0:8082']

  - job_name: "blackbox_telnet_port"
    scrape_interval: 5s
    metrics_path: /probe
    params:
      module: [tcp_connect]
    static_configs:
      - targets: [ '$ip0:8082' ]
        labels:
          group: 'artifactory'
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: $ip0:9115

  - job_name: 'http-blackbox'
    metrics_path: /probe
    params:
      module: [http_2xx]  # Look for a HTTP 200 response.
    static_configs:
      - targets:
        - https://$ip0:8082/artifactory/api/system/ping
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: $ip0:9115  # The blackbox exporter's real hostname:port.

  - job_name: 'tcp_8081_exporter'
    static_configs:
      - targets: ['192.168.56.13:8000']
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

read -p "Do you need to install docker and docker-compose? default(y/yes), change(n/no)? " answer
case $answer in
yes|y|Y)
      docker_installation
      jf_monitoring
      sleep 2
;;
No|n|N)
      jf_monitoring
;;
*)
      echo "Input wrong."
      exit 1
;;
esac
