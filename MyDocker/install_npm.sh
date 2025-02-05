#!/bin/bash

# 定义根目录和项目目录
ROOT_DIR="/opt/MyDocker"
PROJECT_DIR="${ROOT_DIR}/volumes/nginx-proxy-manager"

# 创建必要的目录
mkdir -p "${PROJECT_DIR}/"{data,letsencrypt,logs} || { echo "错误：创建项目目录失败！"; exit 1; }
mkdir -p "${ROOT_DIR}/"{containers,image,overlay2,network,tmp} || { echo "错误：创建根目录失败！"; exit 1; }

# 生成 docker-compose.yml 文件
cat > "${PROJECT_DIR}/docker-compose.yml" <<EOF
version: '3.8'
services:
  nginx-proxy-manager:
    image: 'chishin/nginx-proxy-manager-zh:latest'
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
      - '8188:81'
    volumes:
      - ${PROJECT_DIR}/data:/data
      - ${PROJECT_DIR}/letsencrypt:/etc/letsencrypt
      - ${PROJECT_DIR}/logs:/var/log/nginx
    networks:
      - npm-network

networks:
  npm-network:
    driver: bridge
EOF

# 启动容器
cd "${PROJECT_DIR}" || { echo "错误：无法进入项目目录！"; exit 1; }
docker compose up -d

# 等待容器启动
sleep 10

# 检查容器状态
CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' nginx-proxy-manager 2>/dev/null)
if [ "${CONTAINER_STATUS}" != "running" ]; then
  echo "错误：容器未正常运行！当前状态：${CONTAINER_STATUS}"
  exit 1
fi

# 检查管理界面访问
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:81)
if [ "${HTTP_CODE}" -ne 200 ]; then
  echo "警告：管理界面访问异常 (HTTP Code: ${HTTP_CODE})"
else
  echo "管理界面访问正常"
fi

# 检查目录权限
VOLUME_DIRS=("${PROJECT_DIR}/data" "${PROJECT_DIR}/letsencrypt" "${PROJECT_DIR}/logs")
for DIR in "${VOLUME_DIRS[@]}"; do
  if [ ! -w "${DIR}" ]; then
    echo "警告：目录 ${DIR} 不可写，可能导致权限问题！"
  fi
done

echo "安装完成！管理界面：http://<服务器IP>:81"
echo "默认账号：admin@example.com"
echo "默认密码：changeme"
