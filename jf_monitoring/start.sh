#!/bin/bash
# JF Monitoring Environment Installation

set -euo pipefail  # 严格的错误处理

readonly JF_MONITORING_HOME="$(pwd)"
readonly LOG_FILE="${JF_MONITORING_HOME}/installation.log"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================
# Docker 镜像版本配置
# ============================================
readonly PROMETHEUS_IMAGE="prom/prometheus:v2.53.4"
readonly BLACKBOX_EXPORTER_IMAGE="prom/blackbox-exporter:v0.26.0"
readonly GRAFANA_IMAGE="grafana/grafana:11.6.0"

# Docker Compose 版本
readonly DOCKER_COMPOSE_VERSION="v2.38.1"

# ============================================
# 网络配置
# ============================================
readonly DOCKER_NETWORK_NAME="jf-monitoring-network"
readonly DOCKER_NETWORK_DRIVER="bridge"

# ============================================
# 端口配置
# ============================================
readonly PROMETHEUS_PORT="9090"
readonly GRAFANA_PORT="3000"
readonly BLACKBOX_EXPORTER_PORT="9115"

# ============================================
# 默认凭证配置（可在脚本中修改或通过环境变量覆盖）
# ============================================
readonly GRAFANA_ADMIN_USER="admin"
readonly GRAFANA_ADMIN_PASSWORD="admin"

# ============================================
# Prometheus 配置
# ============================================
readonly PROMETHEUS_RETENTION_TIME="90d"
readonly PROMETHEUS_SCRAPE_INTERVAL="15s"
readonly PROMETHEUS_EVALUATION_INTERVAL="15s"

# ============================================
# 日志函数
# ============================================
log() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo -e "${BLUE}${timestamp}${NC} ${message}" | tee -a "$LOG_FILE"
}

success() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo -e "${GREEN}✅ ${message}${NC}" | tee -a "$LOG_FILE"
}

error() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo -e "${RED}❌ ${message}${NC}" | tee -a "$LOG_FILE"
}

warning() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo -e "${YELLOW}⚠️  ${message}${NC}" | tee -a "$LOG_FILE"
}

# 纯文本日志输出（不带颜色和图标）
log_plain() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "${timestamp} ${message}" >> "$LOG_FILE"
}

# 显示当前配置信息
display_configuration() {
    log "当前监控系统配置信息："
    log "========================================="
    log "Prometheus 镜像:      ${PROMETHEUS_IMAGE}"
    log "Grafana 镜像:         ${GRAFANA_IMAGE}"
    log "Blackbox Exporter 镜像: ${BLACKBOX_EXPORTER_IMAGE}"
    log "Docker Compose 版本:  ${DOCKER_COMPOSE_VERSION}"
    log "网络名称:            ${DOCKER_NETWORK_NAME}"
    log "Prometheus 端口:      ${PROMETHEUS_PORT}"
    log "Grafana 端口:         ${GRAFANA_PORT}"
    log "Blackbox Exporter 端口: ${BLACKBOX_EXPORTER_PORT}"
    log "数据保留时间:        ${PROMETHEUS_RETENTION_TIME}"
    log "========================================="
}

# 安装摘要输出到日志
log_summary() {
    local title="$1"
    local content="$2"
    echo "" >> "$LOG_FILE"
    echo "================================================" >> "$LOG_FILE"
    echo "${title}" >> "$LOG_FILE"
    echo "================================================" >> "$LOG_FILE"
    echo "${content}" >> "$LOG_FILE"
    echo "================================================" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

# 安装Docker
docker_installation() {
    log "Starting Docker installation..."
    
    if check_command docker; then
        warning "Docker is already installed"
        docker --version
        return 0
    fi
    
    log "Home path: ${JF_MONITORING_HOME}"
    
    # 安装依赖
    yum install -y yum-utils device-mapper-persistent-data lvm2
    
    # 添加Docker仓库
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # 安装Docker
    yum install -y docker-ce docker-ce-cli containerd.io
    
    # 启动Docker服务
    systemctl enable docker && systemctl start docker
    
    # 验证安装
    if systemctl is-active --quiet docker; then
        success "Docker installed and started successfully"
        docker --version
    else
        error "Docker service failed to start"
        return 1
    fi
}

# 安装Docker Compose
docker_compose_installation() {
    log "Starting Docker Compose installation..."
    
    if check_command docker-compose; then
        warning "Docker Compose is already installed"
        docker-compose --version
        return 0
    fi
    
    local compose_url="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)"
    local install_path="/usr/local/bin/docker-compose"
    
    log "Downloading Docker Compose ${DOCKER_COMPOSE_VERSION}..."
    
    if curl -L "$compose_url" -o "$install_path"; then
        chmod +x "$install_path"
        
        # 创建符号链接到/usr/bin以便更容易访问
        ln -sf "$install_path" /usr/bin/docker-compose
        
        success "Docker Compose installed successfully"
        docker-compose --version
    else
        error "Failed to download Docker Compose"
        return 1
    fi
}

# 验证IP地址格式
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -lt 0 || $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# 获取用户输入
get_user_input() {
    local prompt=$1
    local validation_func=${2:-}
    local max_attempts=3
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        read -p "$prompt" answer
        
        if [[ -z "$answer" ]]; then
            warning "Input cannot be empty"
        elif [[ -n "$validation_func" ]] && ! $validation_func "$answer"; then
            warning "Invalid input format"
        else
            echo "$answer"
            return 0
        fi
        
        attempt=$((attempt + 1))
    done
    
    error "Maximum attempts reached. Exiting."
    exit 1
}

# 生成Prometheus配置文件
generate_prometheus_config() {
    local local_ip=$1
    local artifactory_ip=$2
    local credentials=$3
    
    local config_dir="${JF_MONITORING_HOME}/prometheus/config"
    local config_file="${config_dir}/prometheus.yml"
    
    log "Generating Prometheus configuration..."
    
    # 确保目录存在
    mkdir -p "$config_dir"
    mkdir -p "${JF_MONITORING_HOME}/prometheus/rules"
    
    cat > "$config_file" << EOF
global:
  scrape_interval: ${PROMETHEUS_SCRAPE_INTERVAL}
  evaluation_interval: ${PROMETHEUS_EVALUATION_INTERVAL}
  external_labels:
    monitor: 'jf-monitor'

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    scrape_interval: 5s
    static_configs:
      - targets: ['${artifactory_ip}:9100']

  - job_name: 'jvm-exporter'
    scrape_interval: 5s
    static_configs:
      - targets: ['${artifactory_ip}:30013']

  - job_name: 'artifactory-metrics'
    scrape_interval: 5s
    authorization:
      credentials: '${credentials}'
    metrics_path: '/artifactory/api/v1/metrics'
    static_configs:
      - targets: ['${artifactory_ip}:8082']

  - job_name: 'blackbox-tcp'
    scrape_interval: 5s
    metrics_path: /probe
    params:
      module: [tcp_connect]
    static_configs:
      - targets: ['${artifactory_ip}:8082']
        labels:
          service: 'artifactory'
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: ${local_ip}:9115

  - job_name: 'blackbox-http'
    scrape_interval: 5s
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - http://${artifactory_ip}:8082/artifactory/api/system/ping
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: ${local_ip}:9115

  - job_name: 'artifactory_s3_connections'
    static_configs:
      - targets: ['${artifactory_ip}:8001']
    scrape_interval: 5s

  - job_name: 'tcp_8081_exporter'
    static_configs:
      - targets: ['${artifactory_ip}:8000']
    scrape_interval: 5s

  - job_name: 'artifactory_request_exporter'
    static_configs:
      - targets: ['${artifactory_ip}:8002']
    scrape_interval: 5s
EOF
    
    success "Prometheus configuration generated at $config_file"
}

# 生成Grafana配置文件（可选）
generate_grafana_config() {
    local grafana_config_dir="${JF_MONITORING_HOME}/grafana/config"
    local grafana_config_file="${grafana_config_dir}/grafana.ini"
    
    log "Checking Grafana configuration..."
    
    # 确保目录存在
    mkdir -p "$grafana_config_dir"
    
    # 如果配置文件不存在，创建一个默认的
    if [[ ! -f "$grafana_config_file" ]]; then
        log "Creating default Grafana configuration..."
        cat > "$grafana_config_file" << EOF
[server]
domain = localhost
root_url = %(protocol)s://%(domain)s:%(http_port)s/
serve_from_sub_path = false

[auth]
disable_login_form = false
disable_signout_menu = false

[auth.anonymous]
enabled = false

[auth.basic]
enabled = true

[auth.ldap]
enabled = false
config_file = /etc/grafana/ldap.toml

[security]
admin_user = ${GRAFANA_ADMIN_USER}
admin_password = ${GRAFANA_ADMIN_PASSWORD}
secret_key = SW2YcwTIb9zpOOhoPsMm

[database]
type = sqlite3
path = /var/lib/grafana/grafana.db

[session]
provider = file

[analytics]
reporting_enabled = false
check_for_updates = false

[log]
mode = console file
level = info

[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning
EOF
        success "Default Grafana configuration created at $grafana_config_file"
    else
        success "Grafana configuration already exists at $grafana_config_file"
    fi
}

# 创建Blackbox exporter配置
create_blackbox_config() {
    local blackbox_config_dir="${JF_MONITORING_HOME}/blackbox-config"
    local blackbox_config_file="${blackbox_config_dir}/config.yml"
    
    log "Creating Blackbox exporter configuration..."
    
    # 确保目录存在
    mkdir -p "$blackbox_config_dir"
    
    # 创建配置
    cat > "$blackbox_config_file" << EOF
modules:
  http_2xx:
    prober: http
    http:
      method: GET
      headers:
        User-Agent: "Blackbox Exporter"
      valid_status_codes: [200]
      valid_http_versions: ["HTTP/1.1", "HTTP/2"]
      ip_protocol_fallback: false
      follow_redirects: true
      preferred_ip_protocol: "ip4"
      
  tcp_connect:
    prober: tcp
    tcp:
      ip_protocol_fallback: false
      preferred_ip_protocol: "ip4"
      
  icmp:
    prober: icmp
    icmp:
      ip_protocol_fallback: false
      preferred_ip_protocol: "ip4"
EOF
    
    success "Blackbox exporter configuration created at $blackbox_config_file"
}

# 设置正确的目录权限（解决Grafana权限问题）
setup_directory_permissions() {
    log "Setting up directory permissions for Grafana..."
    
    # 创建必要的目录
    local grafana_dirs=(
        "${JF_MONITORING_HOME}/grafana/data"
        "${JF_MONITORING_HOME}/grafana/config"
    )
    
    for dir in "${grafana_dirs[@]}"; do
        mkdir -p "$dir"
        # 设置正确的权限
        chmod 755 "$dir"
        log "Created directory: $dir"
    done
    
    # 设置Grafana数据目录的所有权和权限
    local grafana_data_dir="${JF_MONITORING_HOME}/grafana/data"
    
    # 尝试设置所有权，如果失败则只设置权限
    if chown 472:472 "$grafana_data_dir" 2>/dev/null; then
        success "Set ownership of Grafana data directory to 472:472"
    else
        # 如果无法设置所有权，则确保权限正确
        chmod 777 "$grafana_data_dir"
        warning "Could not set ownership, using 777 permissions for Grafana data directory"
    fi
    
    # 设置所有必要的目录
    local all_dirs=(
        "${JF_MONITORING_HOME}/prometheus/data"
        "${JF_MONITORING_HOME}/prometheus/config"
        "${JF_MONITORING_HOME}/prometheus/rules"
        "${JF_MONITORING_HOME}/blackbox-config"
    )
    
    for dir in "${all_dirs[@]}"; do
        mkdir -p "$dir"
        chmod 755 "$dir"
    done
    
    # Prometheus数据目录需要写权限
    chmod 777 "${JF_MONITORING_HOME}/prometheus/data"
    
    success "Directory permissions set successfully"
}

# 生成docker-compose.yml文件（使用变量配置）
generate_docker_compose() {
    local compose_file="${JF_MONITORING_HOME}/docker-compose.yml"
    
    log "Generating docker-compose.yml with configuration variables..."
    
    cat > "$compose_file" << EOF
services:
  prometheus:
    image: ${PROMETHEUS_IMAGE}
    container_name: prometheus
    hostname: prometheus
    restart: unless-stopped
    ports:
      - '${PROMETHEUS_PORT}:9090'
    volumes:
      - './prometheus/config/prometheus.yml:/etc/prometheus/prometheus.yml'
      - './prometheus/data:/prometheus'
      - './prometheus/rules:/etc/prometheus/rules'
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--web.enable-lifecycle'
      - '--storage.tsdb.retention.time=${PROMETHEUS_RETENTION_TIME}'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    user: "root"
    networks:
      - monitoring-network

  blackbox-exporter:
    image: ${BLACKBOX_EXPORTER_IMAGE}
    container_name: blackbox-exporter
    hostname: blackbox-exporter
    restart: unless-stopped
    ports:
      - "${BLACKBOX_EXPORTER_PORT}:9115"
    volumes:
      - ./blackbox-config/config.yml:/etc/blackbox_exporter/config.yml
    command:
      - '--config.file=/etc/blackbox_exporter/config.yml'
    networks:
      - monitoring-network

  grafana:
    image: ${GRAFANA_IMAGE}
    container_name: grafana
    hostname: grafana
    restart: unless-stopped
    ports:
      - '${GRAFANA_PORT}:3000'
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
      - GF_SECURITY_ALLOW_EMBEDDING=true
      - GF_PATHS_DATA=/var/lib/grafana
      - GF_PATHS_LOGS=/var/log/grafana
      - GF_PATHS_PLUGINS=/var/lib/grafana/plugins
      - GF_PATHS_PROVISIONING=/etc/grafana/provisioning
    volumes:
      - ./grafana/data:/var/lib/grafana
      - ./grafana/config/grafana.ini:/etc/grafana/grafana.ini:ro
    user: "root"  # 使用root用户避免权限问题
    networks:
      - monitoring-network
    depends_on:
      - prometheus
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  monitoring-network:
    driver: ${DOCKER_NETWORK_DRIVER}
    name: ${DOCKER_NETWORK_NAME}
EOF
    
    success "docker-compose.yml generated at $compose_file"
    
    # 记录生成的docker-compose配置到日志
    log_plain "Generated docker-compose.yml with following image versions:"
    log_plain "  Prometheus: ${PROMETHEUS_IMAGE}"
    log_plain "  Grafana: ${GRAFANA_IMAGE}"
    log_plain "  Blackbox Exporter: ${BLACKBOX_EXPORTER_IMAGE}"
}

# 检查Docker Compose版本并创建兼容的配置文件
check_compose_version_and_generate() {
    log "Checking Docker Compose version..."
    
    local compose_version_output
    if compose_version_output=$(docker-compose version --short 2>/dev/null); then
        log "Docker Compose version: $compose_version_output"
        
        # 检查是否为v2.x版本
        if [[ "$compose_version_output" == v2.* ]]; then
            success "Using Docker Compose v2.x, generating compatible configuration"
        else
            warning "Using Docker Compose v1.x or other version"
        fi
    else
        warning "Unable to determine Docker Compose version"
    fi
    
    # 生成docker-compose.yml
    generate_docker_compose
}

# 启动监控服务
start_monitoring_services() {
    log "Starting monitoring services..."
    
    if ! check_command docker-compose; then
        error "Docker Compose is not installed"
        return 1
    fi
    
    # 检查docker-compose.yml文件是否存在
    if [[ ! -f "${JF_MONITORING_HOME}/docker-compose.yml" ]]; then
        error "docker-compose.yml not found in ${JF_MONITORING_HOME}"
        return 1
    fi
    
    cd "${JF_MONITORING_HOME}"
    
    # 显示docker-compose配置摘要
    log "Using docker-compose configuration:"
    echo "========================================="
    echo "Images to be used:"
    echo "  Prometheus:      ${PROMETHEUS_IMAGE}"
    echo "  Grafana:         ${GRAFANA_IMAGE}"
    echo "  Blackbox Exporter: ${BLACKBOX_EXPORTER_IMAGE}"
    echo "Port mappings:"
    echo "  Prometheus:      ${PROMETHEUS_PORT}:9090"
    echo "  Grafana:         ${GRAFANA_PORT}:3000"
    echo "  Blackbox Exporter: ${BLACKBOX_EXPORTER_PORT}:9115"
    echo "========================================="
    
    # log "Pulling Docker images..."
    # if ! docker-compose pull --quiet; then
    #     warning "Failed to pull some images, attempting to start anyway..."
    # fi
    
    log "Starting containers..."
    if docker-compose up -d; then
        success "Monitoring services started successfully"
        
        # 等待容器启动
        log "Waiting for containers to start..."
        sleep 15
        
        # 显示容器状态
        log "Container status:"
        docker-compose ps
        
        # 检查容器运行状态
        local failed_containers=0
        for container in prometheus blackbox-exporter grafana; do
            if docker-compose ps | grep -q "$container.*Up"; then
                success "Container $container is running"
                
                # 如果是Grafana，额外检查健康状态
                if [[ "$container" == "grafana" ]]; then
                    log "Checking Grafana health..."
                    sleep 5
                    if docker-compose exec grafana curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
                        success "Grafana is healthy and accessible"
                    else
                        warning "Grafana started but health check failed. It may need more time to initialize."
                    fi
                fi
            else
                error "Container $container is not running"
                show_container_logs "$container"
                failed_containers=$((failed_containers + 1))
            fi
        done
        
        if [[ $failed_containers -gt 0 ]]; then
            warning "$failed_containers container(s) failed to start."
            log "Check logs with: docker-compose logs"
        fi
    else
        error "Failed to start monitoring services"
        return 1
    fi
}

# 显示容器日志
show_container_logs() {
    local container=$1
    log "Showing recent logs for $container:"
    echo "========================================="
    docker-compose logs --tail=30 "$container" 2>/dev/null || docker logs --tail=30 "$container" 2>/dev/null
    echo "========================================="
}

# 检查并修复Grafana权限问题
check_and_fix_grafana_permissions() {
    log "Checking and fixing Grafana permissions..."
    
    local grafana_data_dir="${JF_MONITORING_HOME}/grafana/data"
    
    # 检查目录是否存在
    if [[ ! -d "$grafana_data_dir" ]]; then
        error "Grafana data directory not found: $grafana_data_dir"
        return 1
    fi
    
    # 检查目录权限
    local current_perms
    current_perms=$(stat -c "%a" "$grafana_data_dir" 2>/dev/null || echo "unknown")
    log "Current Grafana data directory permissions: $current_perms"
    
    # 确保目录有正确的权限
    if [[ "$current_perms" != "777" ]] && [[ "$current_perms" != "755" ]] && [[ "$current_perms" != "775" ]]; then
        log "Setting Grafana data directory permissions to 777..."
        chmod -R 777 "$grafana_data_dir"
        success "Grafana data directory permissions updated to 777"
    else
        success "Grafana data directory permissions are already appropriate ($current_perms)"
    fi
    
    # 检查子目录
    for subdir in "plugins" "dashboards" "csv"; do
        local subdir_path="${grafana_data_dir}/${subdir}"
        if [[ ! -d "$subdir_path" ]]; then
            mkdir -p "$subdir_path"
            chmod 777 "$subdir_path"
            log "Created missing Grafana subdirectory: $subdir_path"
        fi
    done
    
    return 0
}

# 显示安装摘要并记录到日志
display_installation_summary() {
    local local_ip=$1
    local artifactory_ip=$2
    
    # 创建安装摘要内容
    local summary_content="
Configuration Information:
Prometheus Image:     ${PROMETHEUS_IMAGE}
Grafana Image:        ${GRAFANA_IMAGE}
Blackbox Exporter Image: ${BLACKBOX_EXPORTER_IMAGE}
Docker Compose Version: ${DOCKER_COMPOSE_VERSION}

Access Information:
Prometheus URL:       http://${local_ip}:${PROMETHEUS_PORT}
Grafana URL:          http://${local_ip}:${GRAFANA_PORT}
Grafana Login:        ${GRAFANA_ADMIN_USER} / ${GRAFANA_ADMIN_PASSWORD}
Blackbox Exporter URL: http://${local_ip}:${BLACKBOX_EXPORTER_PORT}
Artifactory IP:       ${artifactory_ip}

Prometheus Configuration:
Retention Time:       ${PROMETHEUS_RETENTION_TIME}
Scrape Interval:      ${PROMETHEUS_SCRAPE_INTERVAL}
Evaluation Interval:  ${PROMETHEUS_EVALUATION_INTERVAL}

Important Configuration Steps:
1. Log in to Grafana at http://${local_ip}:${GRAFANA_PORT}
2. Change the default password (${GRAFANA_ADMIN_USER}/${GRAFANA_ADMIN_PASSWORD})
3. Add Prometheus data source:
   - URL: http://${local_ip}:${PROMETHEUS_PORT}
   - Access: Proxy
4. Import dashboards for monitoring

Service Management Commands:
Check status:     docker-compose ps
View logs:        docker-compose logs
View specific:    docker-compose logs [service]
Restart services: docker-compose restart
Stop services:    docker-compose stop
Start services:   docker-compose start
Remove services:  docker-compose down

Installation Directory: ${JF_MONITORING_HOME}
Log File:              ${LOG_FILE}"

    # 在屏幕上显示（带颜色）
    echo ""
    echo "================================================"
    success "JF Monitoring installed successfully!"
    echo "================================================"
    echo ""
    echo -e "${YELLOW}Configuration Information:${NC}"
    echo -e "Prometheus Image:     ${GREEN}${PROMETHEUS_IMAGE}${NC}"
    echo -e "Grafana Image:        ${GREEN}${GRAFANA_IMAGE}${NC}"
    echo -e "Blackbox Exporter Image: ${GREEN}${BLACKBOX_EXPORTER_IMAGE}${NC}"
    echo -e "Docker Compose Version: ${GREEN}${DOCKER_COMPOSE_VERSION}${NC}"
    echo ""
    echo -e "${YELLOW}Access Information:${NC}"
    echo -e "Prometheus URL:       ${GREEN}http://${local_ip}:${PROMETHEUS_PORT}${NC}"
    echo -e "Grafana URL:          ${GREEN}http://${local_ip}:${GRAFANA_PORT}${NC}"
    echo -e "Grafana Login:        ${GREEN}${GRAFANA_ADMIN_USER} / ${GRAFANA_ADMIN_PASSWORD}${NC}"
    echo -e "Blackbox Exporter URL: ${GREEN}http://${local_ip}:${BLACKBOX_EXPORTER_PORT}${NC}"
    echo -e "Artifactory IP:       ${GREEN}${artifactory_ip}${NC}"
    echo ""
    echo -e "${YELLOW}Prometheus Configuration:${NC}"
    echo -e "Retention Time:       ${GREEN}${PROMETHEUS_RETENTION_TIME}${NC}"
    echo -e "Scrape Interval:      ${GREEN}${PROMETHEUS_SCRAPE_INTERVAL}${NC}"
    echo -e "Evaluation Interval:  ${GREEN}${PROMETHEUS_EVALUATION_INTERVAL}${NC}"
    echo ""
    echo -e "${YELLOW}Important Configuration Steps:${NC}"
    echo -e "1. Log in to Grafana at ${GREEN}http://${local_ip}:${GRAFANA_PORT}${NC}"
    echo -e "2. Change the default password (${GREEN}${GRAFANA_ADMIN_USER}/${GRAFANA_ADMIN_PASSWORD}${NC})"
    echo -e "3. Add Prometheus data source:"
    echo -e "   - URL: ${GREEN}http://${local_ip}:${PROMETHEUS_PORT}${NC}"
    echo -e "   - Access: ${GREEN}Proxy${NC}"
    echo -e "4. Import dashboards for monitoring"
    echo ""
    echo -e "${YELLOW}Service Management Commands:${NC}"
    echo -e "Check status:     ${GREEN}docker-compose ps${NC}"
    echo -e "View logs:        ${GREEN}docker-compose logs${NC}"
    echo -e "View specific:    ${GREEN}docker-compose logs [service]${NC}"
    echo -e "Restart services: ${GREEN}docker-compose restart${NC}"
    echo -e "Stop services:    ${GREEN}docker-compose stop${NC}"
    echo -e "Start services:   ${GREEN}docker-compose start${NC}"
    echo -e "Remove services:  ${GREEN}docker-compose down${NC}"
    echo ""
    echo -e "${YELLOW}Installation Information:${NC}"
    echo -e "Installation Directory: ${GREEN}${JF_MONITORING_HOME}${NC}"
    echo -e "Log File:              ${GREEN}${LOG_FILE}${NC}"
    echo "================================================"
    
    # 将摘要记录到日志文件（纯文本）
    log_summary "JF MONITORING INSTALLATION SUMMARY" "$summary_content"
    
    # 记录成功消息
    log_plain "✅ JF Monitoring installed successfully!"
    log_plain "Installation completed at: $(date)"
    log_plain "Installation directory: ${JF_MONITORING_HOME}"
}

# 显示故障排除信息并记录到日志
display_troubleshooting_info() {
    local troubleshooting_content="
Troubleshooting steps:
1. Check Docker daemon is running: systemctl status docker
2. Check container logs: docker-compose logs
3. Check Grafana permissions: ls -la grafana/data/
4. Fix permissions: chmod -R 777 grafana/data/
5. Restart services: docker-compose down && docker-compose up -d
6. Check disk space: df -h
7. Check Docker logs: journalctl -u docker.service
8. Check container status: docker ps -a
9. Check image versions in docker-compose.yml
10. Verify network configuration"

    # 记录到日志
    log_summary "TROUBLESHOOTING INFORMATION" "$troubleshooting_content"
}

# 主安装函数
jf_monitoring() {
    log "Starting JF Monitoring installation..."
    
    # 显示当前配置
    display_configuration
    
    # 获取用户输入
    warning "Please provide the following information:"
    
    local local_ip
    local artifactory_ip
    local credentials
    
    local_ip=$(get_user_input "Please input the local IP of this server (e.g., hostname -i): " validate_ip)
    artifactory_ip=$(get_user_input "Please input Artifactory node IP (e.g., hostname -i): " validate_ip)
    
    read -p "Please enter Artifactory Credentials (Identity Token): " -s credentials
    echo  # 换行
    
    if [[ -z "$credentials" ]]; then
        error "Credentials cannot be empty"
        exit 1
    fi
    
    # 记录安装参数到日志
    log_plain "Installation parameters:"
    log_plain "Local IP: ${local_ip}"
    log_plain "Artifactory IP: ${artifactory_ip}"
    log_plain "Credentials: [HIDDEN]"
    
    # 设置权限和创建目录
    setup_directory_permissions
    
    # 检查并修复Grafana权限
    check_and_fix_grafana_permissions
    
    # 生成配置文件
    generate_prometheus_config "$local_ip" "$artifactory_ip" "$credentials"
    generate_grafana_config
    create_blackbox_config
    
    # 检查版本并生成docker-compose配置
    check_compose_version_and_generate
    
    # 启动服务
    if start_monitoring_services; then
        # 显示安装摘要
        display_installation_summary "$local_ip" "$artifactory_ip"
        
        # 可选：显示初始日志
        # read -p "Do you want to see the initial container logs? (yes/no): " show_logs
        # case "${show_logs,,}" in
        #     yes|y)
        #         echo ""
        #         show_container_logs "grafana"
        #         show_container_logs "prometheus"
        #         show_container_logs "blackbox-exporter"
        #         ;;
        # esac
    else
        error "JF Monitoring installation failed"
        
        # 显示并记录故障排除信息
        echo ""
        echo -e "${YELLOW}Troubleshooting steps:${NC}"
        echo "1. Check Docker daemon is running: systemctl status docker"
        echo "2. Check container logs: docker-compose logs"
        echo "3. Check Grafana permissions: ls -la grafana/data/"
        echo "4. Fix permissions: chmod -R 777 grafana/data/"
        echo "5. Restart services: docker-compose down && docker-compose up -d"
        echo "6. Check disk space: df -h"
        echo "7. Check Docker logs: journalctl -u docker.service"
        echo "8. Check container status: docker ps -a"
        echo "9. Check image versions in docker-compose.yml"
        echo "10. Verify network configuration"
        
        # 记录故障排除信息到日志
        display_troubleshooting_info
        
        exit 1
    fi
}

# 主执行流程
main() {
    trap 'log "Installation interrupted at $(date)"' INT TERM
    
    check_root
    log "Starting installation in ${JF_MONITORING_HOME}"
    log "Log file: ${LOG_FILE}"
    
    # 记录脚本开始时间
    local start_time=$(date)
    log_plain "Script execution started at: ${start_time}"
    log_plain "Working directory: ${JF_MONITORING_HOME}"
    
    # 记录配置信息
    log_plain "Configuration:"
    log_plain "  Prometheus Image: ${PROMETHEUS_IMAGE}"
    log_plain "  Grafana Image: ${GRAFANA_IMAGE}"
    log_plain "  Blackbox Exporter Image: ${BLACKBOX_EXPORTER_IMAGE}"
    log_plain "  Docker Compose Version: ${DOCKER_COMPOSE_VERSION}"
    
    # Docker安装
    read -p "Do you need to install Docker? (yes/no): " docker_answer
    case "${docker_answer,,}" in
        yes|y)
            docker_installation
            log_plain "User chose to install Docker"
            ;;
        no|n)
            if ! check_command docker; then
                error "Docker is not installed and you chose not to install it"
                log_plain "Docker not installed and user chose not to install - exiting"
                exit 1
            fi
            success "Docker is already installed"
            log_plain "Docker already installed, skipping installation"
            ;;
        *)
            error "Invalid input. Please answer yes or no"
            log_plain "Invalid input for Docker installation: ${docker_answer}"
            exit 1
            ;;
    esac
    
    # Docker Compose安装
    read -p "Do you need to install Docker Compose? (yes/no): " compose_answer
    case "${compose_answer,,}" in
        yes|y)
            docker_compose_installation
            log_plain "User chose to install Docker Compose"
            jf_monitoring
            ;;
        no|n)
            if ! check_command docker-compose; then
                error "Docker Compose is not installed and you chose not to install it"
                log_plain "Docker Compose not installed and user chose not to install - exiting"
                exit 1
            fi
            success "Docker Compose is already installed"
            log_plain "Docker Compose already installed, skipping installation"
            jf_monitoring
            ;;
        *)
            error "Invalid input. Please answer yes or no"
            log_plain "Invalid input for Docker Compose installation: ${compose_answer}"
            exit 1
            ;;
    esac
    
    # 记录脚本结束时间
    local end_time=$(date)
    log_plain "Script execution completed at: ${end_time}"
    log_plain "Total installation logged to: ${LOG_FILE}"
}

# 执行主函数
main "$@"