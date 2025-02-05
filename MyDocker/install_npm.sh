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

# 安装 Docker 和 Docker Compose（确保已安装）
echo "$(date '+%Y-%m-%d %H:%M:%S') - 安装 Docker 和 Docker Compose..."

# 安装 Docker（根据之前的步骤）
# 你可以根据之前的讨论粘贴安装 Docker 的相关代码

# 安装 Docker Compose
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
COMPOSE_URL="https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)"
CHECKSUM_URL="$COMPOSE_URL.sha256"

# 下载并校验 Docker Compose
sudo curl -L "$COMPOSE_URL" -o /usr/local/bin/docker-compose || { echo "❌ Docker Compose 下载失败"; exit 1; }
curl -L "$CHECKSUM_URL" -o docker-compose.sha256 || { echo "❌ Docker Compose 校验文件下载失败"; exit 1; }

# 提取期望的哈希值，并手动校验
EXPECTED_HASH=$(awk '{print $1}' docker-compose.sha256)
ACTUAL_HASH=$(sha256sum /usr/local/bin/docker-compose | awk '{print $1}')

if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
    echo "❌ Docker Compose 校验失败 (期望哈希: $EXPECTED_HASH, 实际哈希: $ACTUAL_HASH)"
    exit 1
fi

sudo chmod +x /usr/local/bin/docker-compose
rm docker-compose.sha256
echo "Docker Compose 版本: $(docker-compose --version)"

# 配置 Nginx Proxy Manager Docker 容器
echo "$(date '+%Y-%m-%d %H:%M:%S') - 配置 Nginx Proxy Manager Docker 容器..."

# 在 Docker 中启动 Nginx Proxy Manager
mkdir -p /opt/MyDocker/nginx-proxy-manager

cat <<EOF > /opt/MyDocker/nginx-proxy-manager/docker-compose.yml
version: '3'

services:
  app:
    image: jc21/nginx-proxy-manager:latest
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

echo "正在启动 Nginx Proxy Manager..."
cd /opt/MyDocker/nginx-proxy-manager
sudo docker-compose up -d

# 检查容器状态
sleep 10
CONTAINER_STATUS=$(sudo docker inspect -f '{{.State.Status}}' nginx-proxy-manager 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "❌ 容器未正常运行！当前状态：$CONTAINER_STATUS"
    sudo docker logs nginx-proxy-manager
    exit 1
fi

# 输出默认管理员账号和密码
echo "🎉 Nginx Proxy Manager 中文版安装完成！"
echo "📝 安装日志已保存到: $LOG_FILE"
echo "🔑 默认管理员账号: admin@example.com"
echo "🔑 默认管理员密码: changeme"
echo "🌐 访问地址: http://<服务器IP>:8118"
