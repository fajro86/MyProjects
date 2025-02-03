#!/bin/bash

set -e  # 遇到错误直接退出
sudo -v  # 提前认证 sudo，避免超时

# 日志记录
LOG_FILE="docker_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "脚本开始时间: $(date)"

# 1. 检查旧版本 Docker
if dpkg -l | grep -q docker; then
    echo "⚠️ 检测到已安装的 Docker 版本，建议先卸载旧版本："
    echo "    sudo apt remove --purge docker docker-engine docker.io containerd runc"
    read -p "是否继续安装？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 2. 安装 Docker 依赖包
echo "正在安装 Docker 依赖包..."
sudo apt install -y ca-certificates curl gnupg2 software-properties-common rsync jq || { echo "❌ 依赖安装失败"; exit 1; }

# 3. 添加 Docker 官方 GPG 密钥
echo "正在添加 Docker GPG 密钥..."
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || { echo "❌ GPG 密钥下载失败"; exit 1; }

# 4. 自动检测 CPU 架构并添加 Docker APT 源
. /etc/os-release
ARCH=$(dpkg --print-architecture)
echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $VERSION_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. 安装 Docker
echo "正在安装 Docker..."
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io || { echo "❌ Docker 安装失败"; exit 1; }

# 6. 配置 Docker 数据目录
DOCKER_DATA_DIR="/opt/MyDocker"
echo "配置 Docker 数据目录: $DOCKER_DATA_DIR"
sudo mkdir -p "$DOCKER_DATA_DIR"
sudo systemctl stop docker

# 确保 Docker 目录存在并迁移数据
if [ -d /var/lib/docker ] && [ ! -L /var/lib/docker ]; then
    if [ "$(ls -A /var/lib/docker)" ]; then
        echo "迁移 Docker 数据..."
        sudo rsync -a --delete /var/lib/docker/ "$DOCKER_DATA_DIR"/ || { echo "❌ 数据迁移失败"; exit 1; }
        sudo mv /var/lib/docker "/var/lib/docker.bak.$(date +%s)"
        sudo ln -s "$DOCKER_DATA_DIR" /var/lib/docker
    else
        echo "源目录为空，无需迁移"
    fi
fi

# 设置权限
sudo chmod -R 700 "$DOCKER_DATA_DIR"
sudo groupadd -f docker
sudo chown -R root:docker "$DOCKER_DATA_DIR"

# 7. 配置 Docker `daemon.json`
DAEMON_CONFIG="/etc/docker/daemon.json"
if [ -f "$DAEMON_CONFIG" ] && grep -q '"data-root"' "$DAEMON_CONFIG"; then
    echo "已存在 Docker data-root 配置，跳过修改"
else
    echo "配置 Docker daemon.json..."
    sudo mkdir -p /etc/docker
    if [ -f "$DAEMON_CONFIG" ]; then
        sudo cp "$DAEMON_CONFIG" "$DAEMON_CONFIG.bak"
    fi
    sudo tee "$DAEMON_CONFIG" > /dev/null <<EOF
{
  "data-root": "$DOCKER_DATA_DIR",
  "selinux-enabled": false,
  "userns-remap": ""
}
EOF
fi

# 8. 启动 Docker 并设置开机启动
echo "启动 Docker..."
sudo systemctl start docker
sudo systemctl enable docker

# 9. 允许非 root 用户运行 Docker
if ! groups $USER | grep -q "\bdocker\b"; then
    echo "添加 $USER 到 Docker 组（重新登录后生效）..."
    sudo usermod -aG docker $USER
fi

# 10. 安装 Docker Compose
echo "安装 Docker Compose..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || { echo "❌ Docker Compose 下载失败"; exit 1; }
sudo chmod +x /usr/local/bin/docker-compose
echo "Docker Compose 版本: $(docker-compose --version)"

# 11. 运行 Docker 测试
echo "运行 Docker 测试..."
if ! sudo docker run --rm hello-world; then
    echo "❌ Docker 测试失败，请检查日志："
    sudo journalctl -u docker --no-pager | tail -n 20
    exit 1
fi

# 12. 完成信息
echo "🎉 Docker 安装完成！"
echo "📁 Docker 数据目录: $DOCKER_DATA_DIR"
echo "🔄 请重新登录以使 Docker 组权限生效，或运行 'newgrp docker'"
echo "🛠️ 你可以运行以下命令检查 Docker 状态:"
echo "    sudo docker info | grep 'Docker Root Dir'"
echo "📝 安装日志已保存到: $LOG_FILE"
