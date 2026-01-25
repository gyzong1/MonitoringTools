#!/bin/bash

set -e  # 遇到错误立即退出 

Jf_monitoring_Home=$(pwd)

echo -e "Home path: ${Jf_monitoring_Home}"
echo -e "Uninstall Prometheus & Grafana..."
sleep 1

# Uninstall Prometheus & Grafana
uninstall_jf_monitoring() {
    local date_backup                    # 声明为局部变量
    local backup_dir="backup"
    
    date_backup=$(date +%Y%m%d_%H%M%S)
    
    cd "${Jf_monitoring_Home}" || exit 1
    
    # 检查目录是否存在，不存在则创建
    if [ ! -d "${backup_dir}/backup_${date_backup}" ]; then
        mkdir -p "${backup_dir}/backup_${date_backup}"
    fi
    
    # 停止容器
    docker-compose down
    sleep 1
    
    # 移动文件到备份目录
    /usr/bin/mv grafana blackbox-config prometheus installation.log "${backup_dir}/backup_${date_backup}/"
    
    # 确认备份成功
    if [ $? -eq 0 ]; then
        echo "✅ Backup completed: ${backup_dir}/backup_${date_backup}/"
    else
        echo "❌ Backup failed!"
        exit 1
    fi
}

# 调用函数
uninstall_jf_monitoring

echo -e "\nUninstall completed successfully!"