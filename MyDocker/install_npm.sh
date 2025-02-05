#!/bin/bash

set -e  # 遇到错误直接退出
trap 'echo "脚本错误：$(basename $0) 行号: $LINENO, 错误命令: $BASH_COMMAND, 错误代码: $?"' ERR

# 提前认证 sudo，避免超时
sudo -v

# 日志记录
LOG_FILE="nginx_proxy_manager_install.log"
[ -f "$LOG_FILE" ] && mv "$LOG_FILE" "$LOG_FILE.$(date +%Y%m%d%H%M%S).bak"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "脚本开始时间: $(date '+%Y-%m-%d %H:%M:%S')"

# 检查是否为 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本 (使用 sudo)"
    exit 1
fi

# 检查是否安装 Docker 和 Docker Compose
if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
    echo "❌ 系统中没有安装 Docker 或 Docker Compose！"
    read -p "是否自动安装 Docker 和 Docker Compose？(y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        echo "正在从 GitHub 拉取并执行 Docker 和 Docker Compose 安装脚本..."
        curl -fsSL https://raw.githubusercontent.com/fajro86/MyProjects/main/MyDocker/install_docker.sh -o install_docker.sh
        sudo bash install_docker.sh
    else
        echo "脚本退出，未安装 Docker 和 Docker Compose。"
        exit 0
    fi
fi

# 检查系统类型和版本
. /etc/os-release
MIN_DEBIAN_VERSION="11"  # Debian 11 (Bullseye) 是 Docker 支持的最低版本
MIN_UBUNTU_VERSION="18.04"

if [[ "$ID" == "debian" ]]; then
    if [[ $(lsb_release -rs) < "$MIN_DEBIAN_VERSION" ]]; then
        echo "❌ Debian 系统版本低于所需的最低版本 ($MIN_DEBIAN_VERSION)"
        exit 1
    fi
elif [[ "$ID" == "ubuntu" ]]; then
    if [[ $(lsb_release -rs) < "$MIN_UBUNTU_VERSION" ]]; then
        echo "❌ Ubuntu 系统版本低于所需的最低版本 ($MIN_UBUNTU_VERSION)"
        exit 1
    fi
else
    echo "❌ 不支持的系统: $ID"
    exit 1
fi

# 检查并删除现有的 nginx-proxy-manager 容器
EXISTING_CONTAINER=$(sudo docker ps -a -q -f name=nginx-proxy-manager)
if [ -n "$EXISTING_CONTAINER" ]; then
    echo "⚠️ 检测到现有的 nginx-proxy-manager 容器，正在删除..."
    sudo docker rm -f nginx-proxy-manager
fi

# 配置 Nginx Proxy Manager Docker 容器
echo "$(date '+%Y-%m-%d %H:%M:%S') - 配置 Nginx Proxy Manager Docker 容器..."

# 在 Docker 中启动 Nginx Proxy Manager
mkdir -p /opt/MyDocker/nginx-proxy-manager

cat <<EOF > /opt/MyDocker/nginx-proxy-manager/docker-compose.yml
version: '3'

services:
  app:
    image: chishin/nginx-proxy-manager-zh:latest
    container_name: nginx-proxy-manager
    environment:
      - DB_SQLITE_FILE=/data/database.sqlite
      - DB_SQLITE_PASSWORD=changeme
    volumes:
      - /opt/MyDocker/nginx-proxy-manager/data:/data
      - /opt/MyDocker/nginx-proxy-manager/letsencrypt:/etc/letsencrypt
    ports:
      - "8188:80"
      - "4443:443"
      - "8118:81"  # 添加管理面板端口
    restart: unless-stopped
EOF

# 使用 Docker Compose 启动容器
if ! sudo docker-compose up -d --remove-orphans; then
    echo "❌ 启动 Nginx Proxy Manager 容器失败"
    exit 1
fi

# 检查容器状态
sleep 10
CONTAINER_STATUS=$(sudo docker inspect -f '{{.State.Status}}' nginx-proxy-manager 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "❌ 容器未正常运行！当前状态：$CONTAINER_STATUS"
    sudo docker logs nginx-proxy-manager || { echo "❌ 获取容器日志失败"; exit 1; }
    exit 1
fi

# 获取服务器 IP 地址
SERVER_IP=$(hostname -I | awk '{print $1}')

# 输出默认管理员账号和密码
echo "🎉 Nginx Proxy Manager 中文版安装完成！"
echo "📝 安装日志已保存到: $LOG_FILE"
echo "🔑 默认管理员账号: admin@example.com"
echo "🔑 默认管理员密码: changeme"
echo "🌐 访问地址: http://$SERVER_IP:8118"
