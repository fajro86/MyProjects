#!/bin/bash
# 一键部署 Traefik + Portainer (Debian 12)
# 功能：自动配置反向代理、SSL证书、中文面板
# 作者：你的名字
# 仓库：https://github.com/fajro86/MyProjects

set -e

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --email)
      EMAIL="$2"
      shift 2
      ;;
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
done

# 获取用户输入（如果未通过参数传入）
if [[ -z "$DOMAIN" ]]; then
  read -p "请输入你的主域名（例如 example.com）: " DOMAIN
  [[ -z "$DOMAIN" ]] && echo "错误：域名不能为空！" && exit 1
fi

if [[ -z "$EMAIL" ]]; then
  read -p "请输入你的邮箱（用于SSL证书申请）: " EMAIL
  [[ -z "$EMAIL" ]] && echo "错误：邮箱不能为空！" && exit 1
fi

# 定义目录结构
BASE_DIR="/opt/MyDocker"
TRAEFIK_DIR="${BASE_DIR}/traefik"
PORTAINER_DIR="${BASE_DIR}/portainer"

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
  echo "错误：Docker 未安装！正在尝试自动安装..."
  curl -fsSL https://get.docker.com | sudo bash
fi

# 创建目录
mkdir -p "${TRAEFIK_DIR}"/{config,letsencrypt} "${PORTAINER_DIR}"/data

# 生成 Traefik 配置
cat > "${TRAEFIK_DIR}/config/traefik.yml" <<EOF
api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false
    network: traefik_network

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${EMAIL}
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF

# 生成 Traefik docker-compose.yml
cat > "${TRAEFIK_DIR}/docker-compose.yml" <<EOF
version: '3'

services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config/traefik.yml:/etc/traefik/traefik.yml
      - ./letsencrypt:/letsencrypt
    networks:
      - traefik_network

networks:
  traefik_network:
    name: traefik_network
    driver: bridge
EOF

# 生成 Portainer 配置（修复反引号问题）
cat > "${PORTAINER_DIR}/docker-compose.yml" <<EOF
version: '3'

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/data
    networks:
      - traefik_network
    labels:
      - "traefik.enable=true"
      - 'traefik.http.routers.portainer.rule=Host(\`docker.${DOMAIN}\`)'
      - "traefik.http.routers.portainer.tls=true"
      - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  traefik_network:
    external: true
EOF

# 启动服务
cd "${TRAEFIK_DIR}" && docker-compose up -d
cd "${PORTAINER_DIR}" && docker-compose up -d

# 获取公网IP（自动检测）
PUBLIC_IP=$(curl -s 4.ipw.cn || curl -s ifconfig.me || echo "你的VPS_IP")

# 输出部署信息
echo ""
echo "========================================================"
echo "✅ 部署成功！请按以下步骤操作："
echo ""
echo "1. 临时访问方式（无需域名）："
echo "   - Portainer 面板: http://${PUBLIC_IP}:9000"
echo "   - Traefik 面板: http://${PUBLIC_IP}:8080"
echo ""
echo "2. 域名访问配置（推荐）："
echo "   - 到域名控制台添加 DNS 记录："
echo "     A 记录: docker.${DOMAIN} → ${PUBLIC_IP}"
echo "     CNAME 记录: *.${DOMAIN} → ${DOMAIN}"
echo "   - 等待 DNS 生效后访问："
echo "     - Portainer: https://docker.${DOMAIN}"
echo ""
echo "3. 首次访问 Portainer 需设置管理员密码（8位以上）"
echo ""
echo "4. 防火墙检查："
echo "   sudo ufw allow 80,443/tcp"
echo "========================================================"
