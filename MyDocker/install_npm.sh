#!/bin/bash

set -e  # 遇到错误直接退出
trap 'echo "脚本错误：$(basename $0) 行号: $LINENO, 错误命令: $BASH_COMMAND, 错误代码: $?"' ERR

# 检查是否为 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本 (使用 sudo)"
    exit 1
fi

# 检查是否安装 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ 系统中没有安装 Docker！"
    read -p "是否自动安装 Docker？(y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        echo "正在从 GitHub 拉取并执行 Docker 安装脚本..."
        curl -fsSL https://raw.githubusercontent.com/fajro86/MyProjects/main/MyDocker/install_docker.sh -o install_docker.sh
        sudo bash install_docker.sh
    else
        echo "脚本退出，未安装 Docker。"
        exit 0
    fi
fi

# 检查是否安装 Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "❌ 系统中没有安装 Docker Compose！"
    read -p "是否自动安装 Docker Compose？(y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        echo "正在从 GitHub 拉取并执行 Docker Compose 安装脚本..."
        curl -fsSL https://raw.githubusercontent.com/fajro86/MyProjects/main/MyDocker/install_docker.sh -o install_docker.sh
        sudo bash install_docker.sh
    else
        echo "脚本退出，未安装 Docker Compose。"
        exit 0
    fi
fi

# 配置 Nginx Proxy Manager Docker 容器
echo "$(date '+%Y-%m-%d %H:%M:%S') - 配置 Nginx Proxy Manager Docker 容器..."

# 检查目标目录是否存在，如果没有，创建它
NPM_DIR="/opt/MyDocker/nginx-proxy-manager"
if [ ! -d "$NPM_DIR" ]; then
    echo "⚠️ 目录不存在，创建目录: $NPM_DIR"
    sudo mkdir -p "$NPM_DIR"
fi

# 创建 Docker Compose 配置文件
cat <<EOF > "$NPM_DIR/docker-compose.yml"
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

# 检查 docker-compose.yml 是否成功创建
if [ ! -f "$NPM_DIR/docker-compose.yml" ]; then
    echo "❌ 未能创建 docker-compose.yml 文件"
    exit 1
fi

echo "🔧 配置文件已创建: $NPM_DIR/docker-compose.yml"

# 进入目标目录并启动容器
cd "$NPM_DIR" || { echo "❌ 无法进入目录"; exit 1; }

# 启动 Nginx Proxy Manager 容器
echo "正在启动 Nginx Proxy Manager..."
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
