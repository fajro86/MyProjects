#!/bin/bash

set -e  # 遇到错误直接退出
trap 'echo "脚本错误：$(basename $0) 行号: $LINENO, 错误命令: $BASH_COMMAND, 错误代码: $?"' ERR

# 提前认证 sudo，避免超时
sudo -v

# 日志记录
LOG_FILE="docker_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "脚本开始时间: $(date '+%Y-%m-%d %H:%M:%S')"

# 1. 检查旧版本 Docker
if dpkg -l | grep -q docker; then
    echo "⚠️ 检测到已安装的 Docker 或 Containerd 组件，请选择操作："
    echo "1) 卸载旧版并重新安装"
    echo "2) 覆盖安装（保留旧版配置）"
    echo "3) 退出脚本"

    while true; do
        read -p "请输入选项 (1/2/3): " choice
        case $choice in
            1)
                echo "🔄 卸载旧版 Docker..."
                sudo apt remove --purge -y docker docker-engine docker.io containerd runc
                sudo rm -rf /var/lib/docker /etc/docker /var/lib/containerd
                echo "✅ 旧版 Docker 已卸载"
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

# 2. 安装 Docker 依赖包
echo "📦 正在检查并安装 Docker 依赖包..."
for pkg in ca-certificates curl gnupg2 software-properties-common rsync jq; do
    if ! dpkg -l | grep -q "$pkg"; then
        sudo apt install -y "$pkg" || echo "⚠️ $pkg 安装失败，继续安装其他包..."
    fi
done

# 3. 添加 Docker 官方 GPG 密钥
echo "🔑 添加 Docker GPG 密钥..."
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 4. 自动检测系统并添加 Docker APT 源
. /etc/os-release
ARCH=$(dpkg --print-architecture)
DOCKER_SOURCE="https://download.docker.com/linux/${ID}"

echo "📌 添加 Docker APT 源..."
echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $DOCKER_SOURCE $VERSION_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. 安装 Docker
echo "🚀 安装 Docker..."
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io

# 6. 配置 Docker 数据目录
DOCKER_DATA_DIR="/opt/MyDocker"
echo "📂 配置 Docker 数据目录: $DOCKER_DATA_DIR"
sudo mkdir -p "$DOCKER_DATA_DIR"

if [ -d /var/lib/docker ] && [ ! -L /var/lib/docker ]; then
    echo "🔄 迁移 Docker 数据..."
    sudo rsync -a --delete /var/lib/docker/ "$DOCKER_DATA_DIR"/
    sudo mv /var/lib/docker "/var/lib/docker.bak.$(date +%s)"
    sudo ln -s "$DOCKER_DATA_DIR" /var/lib/docker
fi

sudo chmod -R 750 "$DOCKER_DATA_DIR"
sudo groupadd -f docker
sudo chown -R root:docker "$DOCKER_DATA_DIR"

# 7. 配置 Docker `daemon.json`
DAEMON_CONFIG="/etc/docker/daemon.json"
DOCKER_DAEMON_CONFIG="{
  \"data-root\": \"$DOCKER_DATA_DIR\",
  \"selinux-enabled\": false,
  \"userns-remap\": \"\"
}"

echo "🛠️ 配置 Docker daemon.json..."
sudo mkdir -p /etc/docker
echo "$DOCKER_DAEMON_CONFIG" | sudo tee "$DAEMON_CONFIG" > /dev/null

# 8. 启动 Docker 并设置开机启动
echo "🔄 启动 Docker..."
sudo systemctl restart docker
sudo systemctl enable docker

# 9. 允许非 root 用户运行 Docker
if ! groups $USER | grep -q "\bdocker\b"; then
    echo "👤 添加 $USER 到 Docker 组..."
    sudo usermod -aG docker $USER
fi

# 10. 安装 Docker Compose
echo "📥 安装 Docker Compose..."
DOCKER_COMPOSE_BIN="/usr/local/bin/docker-compose"
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

if [[ "$ARCH" == "x86_64" ]]; then
    COMPOSE_ARCH="linux-x86_64"
elif [[ "$ARCH" == "aarch64" ]]; then
    COMPOSE_ARCH="linux-aarch64"
else
    echo "❌ 不支持的架构: $ARCH"
    exit 1
fi

COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-${OS}-${COMPOSE_ARCH}"
CHECKSUM_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-${OS}-${COMPOSE_ARCH}.sha256"

rm -f "docker-compose-${OS}-${COMPOSE_ARCH}"

echo "📥 下载 Docker Compose..."
curl -fsSL "$COMPOSE_URL" -o "docker-compose-${OS}-${COMPOSE_ARCH}"

if [[ ! -s "docker-compose-${OS}-${COMPOSE_ARCH}" ]]; then
    echo "❌ 下载的 Docker Compose 文件为空，安装失败！"
    exit 1
fi

if curl -fsSL "$CHECKSUM_URL" -o "docker-compose-${OS}-${COMPOSE_ARCH}.sha256"; then
    echo "🔍 校验 Docker Compose..."
    sha256sum --check --ignore-missing "docker-compose-${OS}-${COMPOSE_ARCH}.sha256"
    if [[ $? -ne 0 ]]; then
        echo "❌ 校验失败！是否继续安装？(y/N)"
        read -p "输入选项: " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
else
    echo "⚠️ 无法获取 SHA256 校验文件，跳过校验！"
fi

sudo mv "docker-compose-${OS}-${COMPOSE_ARCH}" "$DOCKER_COMPOSE_BIN"
sudo chmod +x "$DOCKER_COMPOSE_BIN"

echo "✅ Docker Compose 安装成功！版本: $($DOCKER_COMPOSE_BIN --version)"

# 11. 测试 Docker
echo "🛠️ 运行 Docker 测试..."
if ! sudo docker run --rm hello-world > /dev/null; then
    echo "❌ Docker 测试失败！请检查日志"
    exit 1
fi

# 12. 完成信息
echo "🎉 Docker 安装完成！"
echo "📁 Docker 数据目录: $DOCKER_DATA_DIR"
echo "🛠️ 运行 'newgrp docker' 使 Docker 组生效"
echo "📝 安装日志已保存到: $LOG_FILE"
