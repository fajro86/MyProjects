#!/bin/bash
# 一键部署 Traefik + Portainer (Debian 12)
# 完全修复版本：解决 YAML 语法和变量替换冲突
# GitHub: https://github.com/fajro86/MyProjects/blob/main/MyDocker/install%20Traefik%20Portainer.sh

set -e

read -p "请输入你的域名（例如 example.com）: " DOMAIN
read -p "请输入你的邮箱（用于SSL证书申请）: " EMAIL

BASE_DIR="/opt/MyDocker"
TRAEFIK_DIR="${BASE_DIR}/traefik"
PORTAINER_DIR="${BASE_DIR}/portainer"

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "错误：Docker 未安装！请先安装 Docker。"
    exit 1
fi

mkdir -p ${TRAEFIK_DIR}/{config,letsencrypt} ${PORTAINER_DIR}/data

# 生成 Traefik 配置（保持不变）
cat > ${TRAEFIK_DIR}/config/traefik.yml <<EOF
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

# 生成 Traefik docker-compose.yml（保持不变）
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

# 修复 Portainer 的 docker-compose.yml（关键修改！）
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
      - 'traefik.http.routers.portainer.rule=Host(`docker.${DOMAIN}`)'  # 使用单引号包裹
      - "traefik.http.routers.portainer.tls=true"
      - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  traefik_network:
    external: true
EOF

# 启动服务
cd ${TRAEFIK_DIR} && docker-compose up -d
cd ${PORTAINER_DIR} && docker-compose up -d

echo "==================================================="
echo "✅ 终极修复完成！请访问："
echo "- Portainer 面板: https://docker.${DOMAIN}"
echo "==================================================="
