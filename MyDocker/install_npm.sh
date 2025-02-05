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

# 询问是否申请证书
echo "选择证书申请方式："
echo "1) 跳过证书申请"
echo "2) 立即申请自签名证书"
echo "3) 立即申请 Let's Encrypt 证书"

# 获取用户选择
read -p "请输入选项 (1/2/3): " choice

case $choice in
    1)
        echo "跳过证书申请，继续安装..."
        ;;
    2)
        # 自签名证书生成
        echo "正在生成自签名证书..."
        ssl_dir="/opt/MyDocker/nginx-proxy-manager/letsencrypt"
        sudo mkdir -p "$ssl_dir"
        read -p "请输入用于生成证书的域名: " domain
        read -p "请输入用于生成证书的邮箱: " email
        sudo openssl req -x509 -nodes -newkey rsa:2048 -keyout "$ssl_dir/selfsigned.key" -out "$ssl_dir/selfsigned.crt" -days 365 -subj "/CN=$domain/emailAddress=$email"
        echo "自签名证书已生成"
        ;;
    3)
        # Let's Encrypt 证书申请
        echo "正在申请 Let's Encrypt 证书..."
        ssl_dir="/opt/MyDocker/nginx-proxy-manager/letsencrypt"
        sudo mkdir -p "$ssl_dir"
        read -p "请输入用于申请证书的域名: " domain
        read -p "请输入用于申请证书的邮箱: " email

        # 需要确保域名解析已指向服务器 IP
        if ! command -v certbot &> /dev/null; then
            echo "Certbot 未安装，正在安装..."
            sudo apt install -y certbot
        fi

        # 使用 certbot 自动申请证书
        sudo certbot certonly --standalone --agree-tos --no-eff-email -d "$domain" --email "$email"
        
        # 复制证书到指定目录
        sudo cp /etc/letsencrypt/live/$domain/fullchain.pem "$ssl_dir/cert.pem"
        sudo cp /etc/letsencrypt/live/$domain/privkey.pem "$ssl_dir/key.pem"
        echo "Let's Encrypt 证书已申请并存储"
        ;;
    *)
        echo "无效选项，退出安装"
        exit 1
        ;;
esac

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
    restart: unless-stopped
EOF

echo "正在启动 Nginx Proxy Manager..."
cd /opt/MyDocker/nginx-proxy-manager
sudo docker-compose up -d

echo "🎉 Nginx Proxy Manager 中文版安装完成！"
echo "📝 安装日志已保存到: $LOG_FILE"
