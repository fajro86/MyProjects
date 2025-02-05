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

# 配置 Docker 数据目录
docker_data_dir="/opt/MyDocker/nginx-proxy-manager"
sudo mkdir -p "$docker_data_dir"
sudo systemctl stop docker

# 迁移 Docker 数据（如果存在旧数据）
if [ -d /var/lib/docker ] && [ ! -L /var/lib/docker ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 迁移 Docker 数据..."
    sudo rsync -a --delete /var/lib/docker/ "$docker_data_dir"/ || { echo "❌ 数据迁移失败"; exit 1; }
    sudo mv /var/lib/docker "/var/lib/docker.bak.$(date +%s)"
    sudo ln -s "$docker_data_dir" /var/lib/docker
fi

# 设置权限和所有权
sudo chmod -R 750 "$docker_data_dir"
sudo groupadd -f docker
sudo chown -R root:docker "$docker_data_dir"

# 拉取并运行 Nginx Proxy Manager Docker 镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - 启动 Nginx Proxy Manager..."

docker run -d \
  --name=nginx-proxy-manager \
  -p 8188:80 \
  -p 8189:443 \
  -p 8190:81 \
  -v "$docker_data_dir/data":/data \
  -v "$docker_data_dir/letsencrypt":/etc/letsencrypt \
  --restart unless-stopped \
  jc21/nginx-proxy-manager:latest

echo "✅ Nginx Proxy Manager 安装完成！"
echo "📁 数据目录: $docker_data_dir"
echo "🛠️ 你可以通过 http://<your-ip>:8188 访问 Nginx Proxy Manager 面板"
