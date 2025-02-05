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

# 1. 安装 Docker（如果未安装）
echo "$(date '+%Y-%m-%d %H:%M:%S') - 检查并安装 Docker..."
if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，正在安装..."
    sudo apt update
    sudo apt install -y docker.io
    sudo systemctl start docker
    sudo systemctl enable docker
else
    echo "Docker 已安装"
fi

# 2. 安装 Docker Compose（如果未安装）
echo "$(date '+%Y-%m-%d %H:%M:%S') - 检查并安装 Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose 未安装，正在安装..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "Docker Compose 已安装"
fi

# 3. 拉取并配置 Nginx Proxy Manager 镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - 拉取 Nginx Proxy Manager 镜像..."
docker pull jc21/nginx-proxy-manager:latest

# 4. 配置 Nginx Proxy Manager 的 Docker 容器
echo "$(date '+%Y-%m-%d %H:%M:%S') - 配置 Nginx Proxy Manager Docker 容器..."
mkdir -p /opt/nginx-proxy-manager
cd /opt/nginx-proxy-manager

cat <<EOF > docker-compose.yml
version: '3'

services:
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    environment:
      - DB_SQLITE_FILE=/data/database.sqlite
      - MYSQL_ROOT_PASSWORD=example  # 如果使用 MySQL 作为数据库
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    ports:
      - "8188:8188"   # 可根据需求修改端口
      - "80:80"
      - "443:443"
EOF

# 5. 启动容器
echo "$(date '+%Y-%m-%d %H:%M:%S') - 启动 Nginx Proxy Manager 容器..."
docker-compose up -d

# 6. 申请 SSL 证书
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始申请 SSL 证书..."
read -p "请输入您要为 Nginx Proxy Manager 配置的域名 (如: your-domain.com): " domain
read -p "请输入您的邮箱地址 (用于 Certbot 证书申请): " email

# 检查邮箱和域名是否为空
if [ -z "$domain" ] || [ -z "$email" ]; then
    echo "❌ 域名和邮箱不能为空，请重新运行脚本并提供有效的域名和邮箱！"
    exit 1
fi

# 安装 Certbot
echo "$(date '+%Y-%m-%d %H:%M:%S') - 安装 Certbot..."
sudo apt update
sudo apt install -y certbot

# 申请证书
echo "$(date '+%Y-%m-%d %H:%M:%S') - 使用 Certbot 申请 SSL 证书..."
sudo certbot certonly --standalone -d $domain --email $email --agree-tos --non-interactive

# 配置 Nginx 证书
echo "$(date '+%Y-%m-%d %H:%M:%S') - 配置 Nginx 使用 SSL 证书..."
sudo cp /etc/letsencrypt/live/$domain/fullchain.pem /opt/nginx-proxy-manager/letsencrypt/$domain.crt
sudo cp /etc/letsencrypt/live/$domain/privkey.pem /opt/nginx-proxy-manager/letsencrypt/$domain.key

# 7. 配置 Nginx Proxy Manager 使用 SSL 证书
echo "$(date '+%Y-%m-%d %H:%M:%S') - 配置 Nginx Proxy Manager 使用 SSL..."
docker exec -it nginx-proxy-manager bash -c "sed -i 's|ssl_certificate .*|ssl_certificate /etc/letsencrypt/$domain.crt;|' /etc/nginx/conf.d/default.conf"
docker exec -it nginx-proxy-manager bash -c "sed -i 's|ssl_certificate_key .*|ssl_certificate_key /etc/letsencrypt/$domain.key;|' /etc/nginx/conf.d/default.conf"

# 8. 重载 Nginx 配置
echo "$(date '+%Y-%m-%d %H:%M:%S') - 重载 Nginx 配置..."
docker exec nginx-proxy-manager nginx -s reload

# 9. 结束安装
echo "🎉 Nginx Proxy Manager 安装完成！"
echo "📁 Nginx Proxy Manager 配置目录: /opt/nginx-proxy-manager"
echo "🛠️ 你可以访问 Nginx Proxy Manager 面板：http://$domain:8188"
echo "📝 安装日志已保存到: $LOG_FILE"
