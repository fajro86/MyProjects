#!/bin/bash
# 一键部署 Traefik + Portainer (Debian 12)
# 功能：自动化配置反向代理、SSL证书、可视化面板
# 作者：你的名字
# 日期：2024-06-06

set -e  # 遇到错误立即退出

# 用户输入交互
read -p "请输入你的域名（例如 example.com）: " DOMAIN
read -p "请输入你的邮箱（用于SSL证书申请）: " EMAIL

# 定义目录结构
BASE_DIR="/opt/MyDocker"
TRAEFIK_DIR="${BASE_DIR}/traefik"
PORTAINER_DIR="${BASE_DIR}/portainer"

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo "错误：Docker 未安装！请先安装 Docker。"
    exit 1
fi

# 创建目录结构
mkdir -p ${TRAEFIK_DIR}/{config,letsencrypt} ${PORTAINER_DIR}/data

# 生成 Traefik 配置文件
cat > ${TRAEFIK_DIR}/config/traefik.yml <<EOF
api:
  dashboard: true
  insecure: true  # 通过域名访问时需关闭

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

# 生成 Traefik 的 docker-compose.yml
cat > ${TRAEFIK_DIR}/docker-compose.yml <<EOF
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

# 生成 Portainer 的 docker-compose.yml
cat > ${PORTAINER_DIR}/docker-compose.yml <<EOF
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
      - "traefik.http.routers.portainer.rule=Host(\`docker.${DOMAIN}\`)"
      - "traefik.http.routers.portainer.tls=true"
      - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  traefik_network:
    external: true
EOF

# 启动 Traefik
echo "正在启动 Traefik..."
cd ${TRAEFIK_DIR}
docker-compose up -d

# 启动 Portainer
echo "正在启动 Portainer..."
cd ${PORTAINER_DIR}
docker-compose up -d

# 输出部署结果
echo "==================================================="
echo "✅ 部署完成！请按以下步骤操作："
echo ""
echo "1. 到域名服务商处添加 DNS 解析："
echo "   - 将 'docker.${DOMAIN}' 和 '*.${DOMAIN}' 指向本机 IP"
echo ""
echo "2. 访问以下地址："
echo "   - Portainer 面板: https://docker.${DOMAIN}"
echo "   - Traefik 面板（本地）: http://localhost:8080"
echo ""
echo "3. 后续部署新应用时，只需在 docker-compose.yml 中添加标签："
echo "   labels:"
echo "     - \"traefik.enable=true\""
echo "     - \"traefik.http.routers.应用名.rule=Host(\`子域名.${DOMAIN}\`)\""
echo "     - \"traefik.http.routers.应用名.tls=true\""
echo "==================================================="
