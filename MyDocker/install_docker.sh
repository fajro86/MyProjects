#!/bin/bash

set -e  # 遇到错误直接退出
trap 'echo "脚本错误：$(basename $0) 行号: $LINENO, 错误命令: $BASH_COMMAND, 错误代码: $?"' ERR

# 提前认证 sudo，避免超时
sudo -v

# 日志记录
LOG_FILE="docker_install.log"
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

# 定义卸载 Docker 函数
uninstall_old_docker() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 卸载旧版 Docker..."
    sudo apt remove --purge -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io || true
    sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
    echo "✅ 旧版 Docker 已卸载"
}

# 1. 检查旧版本 Docker
if dpkg -l | grep -q 'docker\|containerd'; then
    echo "⚠️ 检测到已安装的 Docker 或 Containerd 组件，请选择操作："
    echo "1) 卸载旧版并重新安装"
    echo "2) 覆盖安装（保留旧版配置）"
    echo "3) 退出脚本"
    while true; do
        # 强制从终端读取输入
        read -p "请输入选项 (1/2/3): " choice </dev/tty
        case $choice in
            1)
                uninstall_old_docker
                break
                ;;
            2)
                echo "⚠️ 继续覆盖安装（可能因版本冲突导致问题）..."
                break
                ;;
            3)
                echo "退出脚本"
                exit 0
                ;;
            *)
                echo "❌ 无效选项，请重新输入"
                ;;
        esac
    done
fi

# 2. 安装 Docker 依赖包
echo "$(date '+%Y-%m-%d %H:%M:%S') - 检查并安装 Docker 依赖包..."
for pkg in ca-certificates curl gnupg2 software-properties-common rsync jq; do
    if ! dpkg -l | grep -q "$pkg"; then
        echo "$pkg 未安装，正在安装..."
        sudo apt install -y "$pkg" || { echo "⚠️ $pkg 安装失败，继续安装其他包..." >> "$LOG_FILE"; }
    fi
done

# 3. 添加 Docker 官方 GPG 密钥
echo "$(date '+%Y-%m-%d %H:%M:%S') - 添加 Docker GPG 密钥..."
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || { echo "❌ GPG 密钥下载失败"; exit 1; }

# 4. 自动检测系统并添加 Docker APT 源
. /etc/os-release
ARCH=$(dpkg --print-architecture)
DOCKER_SOURCE="https://download.docker.com/linux/$ID"
echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $DOCKER_SOURCE $VERSION_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. 安装 Docker
echo "$(date '+%Y-%m-%d %H:%M:%S') - 安装 Docker..."
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io || { echo "❌ Docker 安装失败"; exit 1; }

# 6. 配置 Docker 数据目录
docker_data_dir="/opt/MyDocker"
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

# 7. 配置 Docker `daemon.json`
daemon_config="/etc/docker/daemon.json"
docker_daemon_config="{
  \"data-root\": \"$docker_data_dir\",
  \"selinux-enabled\": false,
  \"userns-remap\": \"\"
}"

echo "$(date '+%Y-%m-%d %H:%M:%S') - 配置 Docker daemon.json..."
sudo mkdir -p /etc/docker
if [ -f "$daemon_config" ]; then
    sudo cp "$daemon_config" "$daemon_config.bak.$(date +%Y%m%d%H%M%S)"
fi
sudo tee "$daemon_config" > /dev/null <<< "$docker_daemon_config"

# 8. 启动 Docker 并设置开机启动
echo "$(date '+%Y-%m-%d %H:%M:%S') - 启动 Docker..."
sudo systemctl start docker
sudo systemctl enable docker

# 9. 允许非 root 用户运行 Docker
if ! groups $USER | grep -q "\bdocker\b"; then
    echo "添加 $USER 到 Docker 组（重新登录后生效）..."
    sudo usermod -aG docker $USER
    echo "⚠️ 已将 $USER 添加到 Docker 组。请注意，Docker 组的用户具有等同于 root 的权限。"
fi

# 10. 安装 Docker Compose（带哈希校验）
echo "$(date '+%Y-%m-%d %H:%M:%S') - 安装 Docker Compose..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
COMPOSE_URL="https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)"
CHECKSUM_URL="$COMPOSE_URL.sha256"

# 下载并校验 Docker Compose
sudo curl -L "$COMPOSE_URL" -o /usr/local/bin/docker-compose || { echo "❌ Docker Compose 下载失败"; exit 1; }
curl -L "$CHECKSUM_URL" -o docker-compose.sha256 || { echo "❌ Docker Compose 校验文件下载失败"; exit 1; }
sha256sum -c docker-compose.sha256 || { echo "❌ Docker Compose 校验失败"; exit 1; }
sudo chmod +x /usr/local/bin/docker-compose
rm docker-compose.sha256
echo "Docker Compose 版本: $(docker-compose --version)"

# 11. 运行 Docker 测试
echo "$(date '+%Y-%m-%d %H:%M:%S') - 运行 Docker 测试..."
if ! sudo docker run --rm hello-world > /dev/null; then
    echo "❌ Docker 测试失败，请检查日志："
    sudo journalctl -u docker --no-pager | tail -n 20
    exit 1
fi
echo "✅ Docker 测试成功！"

# 12. 检查磁盘空间
disk_space=$(df --output=avail -h "$docker_data_dir" | tail -n 1)
if [[ "$disk_space" =~ [0-9]+[MG] ]]; then
    echo "⚠️ 磁盘空间不足（当前剩余 $disk_space），建议扩展磁盘空间。"
else
    echo "💾 磁盘空间情况: $disk_space"
fi

# 13. 清理临时文件
cleanup() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 清理临时文件..."
    rm -f docker-compose.sha256
}
trap cleanup EXIT

echo "🎉 Docker 安装完成！"
echo "📁 Docker 数据目录: $docker_data_dir"
echo "🛠️ 你可以运行以下命令检查 Docker 状态:"
echo "    sudo docker info | grep 'Docker Root Dir'"
echo "📝 安装日志已保存到: $LOG_FILE"
