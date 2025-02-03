#!/bin/bash

set -e  # 遇到错误直接退出
trap 'echo "脚本错误：$(basename $0) 行号: $LINENO, 错误命令: $BASH_COMMAND, 错误代码: $?"' ERR

LOG_FILE="docker_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "📌 脚本开始时间: $(date '+%Y-%m-%d %H:%M:%S')"

# 1. 检查并卸载旧版本 Docker
if dpkg -l | grep -q docker; then
    echo "⚠️ 检测到已安装的 Docker 组件，请选择操作："
    echo "1) 卸载旧版并重新安装"
    echo "2) 覆盖安装（保留旧版配置）"
    echo "3) 退出脚本"

    while true; do
        read -p "请输入选项 (1/2/3): " choice </dev/tty
        case "$choice" in
            1)
                echo "🔄 卸载旧版 Docker..."
                sudo systemctl stop docker || true
                sudo apt remove --purge -y docker-ce docker-ce-cli containerd.io docker.io docker-compose-plugin
                sudo rm -rf /var/lib/docker /etc/docker /var/lib/containerd
                echo "✅ 旧版 Docker 已彻底卸载"
                break
                ;;
            2)
                echo "⚠️ 选择覆盖安装，将保留现有 Docker 配置"
                break
                ;;
            3)
                echo "🚪 退出脚本"
                exit 0
                ;;
            *)
                echo "❌ 无效选项，请重新输入"
                ;;
        esac
    done
fi

# 2. 安装 Docker 依赖
echo "📦 正在安装 Docker 依赖..."
sudo apt update
sudo apt install -y ca-certificates curl gnupg2 software-properties-common jq rsync

# 3. 添加 Docker GPG 密钥
echo "🔑 添加 Docker GPG 密钥..."
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 4. 配置 Docker APT 源
. /etc/os-release
ARCH=$(dpkg --print-architecture)
DOCKER_SOURCE="https://download.docker.com/linux/${ID}"

echo "📌 使用 Docker APT 源: $DOCKER_SOURCE"
echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $DOCKER_SOURCE $VERSION_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. 安装 Docker
echo "🚀 安装 Docker..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 6. 配置 Docker 目录
DOCKER_DATA_DIR="/opt/MyDocker"
echo "📂 配置 Docker 数据目录: $DOCKER_DATA_DIR"
sudo mkdir -p "$DOCKER_DATA_DIR"

# **新修正点**：确保 `/etc/docker` 目录存在
sudo mkdir -p /etc/docker

# 7. 配置 daemon.json
DAEMON_CONFIG="/etc/docker/daemon.json"
DOCKER_DAEMON_CONFIG="{
  \"data-root\": \"$DOCKER_DATA_DIR\",
  \"log-driver\": \"json-file\",
  \"log-opts\": { \"max-size\": \"100m\", \"max-file\": \"3\" }
}"

echo "⚙️ 配置 Docker daemon.json..."
echo "$DOCKER_DAEMON_CONFIG" | sudo tee "$DAEMON_CONFIG" > /dev/null

# 8. 启动 Docker 并设置开机启动
echo "🔄 启动 Docker..."
sudo systemctl enable --now docker

# 9. 添加当前用户到 Docker 组
if ! groups $USER | grep -q "\bdocker\b"; then
    echo "👤 添加 $USER 到 Docker 组..."
    sudo usermod -aG docker $USER
    echo "⚠️ 重新登录后生效，或运行 'newgrp docker'"
fi

# 10. 安装 Docker Compose
DOCKER_COMPOSE_PATH="/usr/local/bin/docker-compose"
if [ ! -f "$DOCKER_COMPOSE_PATH" ]; then
    echo "📦 安装 Docker Compose..."
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
    COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)"
    
    sudo curl -L "$COMPOSE_URL" -o "$DOCKER_COMPOSE_PATH"
    sudo chmod +x "$DOCKER_COMPOSE_PATH"
    
    # **修正点**：检查下载文件是否存在
    if [ ! -f "$DOCKER_COMPOSE_PATH" ]; then
        echo "❌ Docker Compose 下载失败"
        exit 1
    fi
    
    # **修正点**：检查 SHA256 校验是否成功
    echo "🔍 校验 Docker Compose..."
    if ! sudo sha256sum -c <(curl -fsSL "$COMPOSE_URL.sha256" | awk '{print $1 "  '"$DOCKER_COMPOSE_PATH"'"}'); then
        echo "❌ Docker Compose 校验失败"
        sudo rm -f "$DOCKER_COMPOSE_PATH"
        exit 1
    fi
else
    echo "✅ Docker Compose 已安装，跳过"
fi

# 11. 运行 Docker 测试
echo "🛠️ 运行 Docker 测试..."
if ! sudo docker run --rm hello-world > /dev/null; then
    echo "❌ Docker 测试失败，请检查日志"
    sudo journalctl -u docker --no-pager | tail -n 20
    exit 1
else
    echo "✅ Docker 运行成功！"
fi

# 12. 检查磁盘空间
DISK_SPACE=$(df -h "$DOCKER_DATA_DIR" | awk 'NR==2 {print $4}')
if [ "${DISK_SPACE%G}" -lt 20 ]; then
    echo "⚠️ 磁盘空间不足（剩余 $DISK_SPACE），建议扩展磁盘"
fi

# 13. 结束信息
echo "🎉 Docker 安装完成！"
echo "📁 Docker 数据目录: $DOCKER_DATA_DIR"
echo "🔄 请重新登录以生效 Docker 组权限，或运行 'newgrp docker'"
echo "🛠️ 你可以运行以下命令检查 Docker 状态:"
echo "    sudo docker info | grep 'Docker Root Dir'"
echo "📝 安装日志已保存到: $LOG_FILE"
