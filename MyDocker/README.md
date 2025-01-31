### **一键安装命令**

```
wget -qO- https://raw.githubusercontent.com/fajro86/docker/refs/heads/main/install_docker | bash
```

### **安装后检查**

如果你是 **root** 用户，可以直接运行：

```
docker info | grep 'Docker Root Dir'
```

如果是 **非 root 用户**，建议 **退出并重新登录**，或者手动执行：

```
newgrp docker  # 让 docker 组生效
```



------

### **📂 Docker 数据目录结构**

在 `/opt/MyDocker` 目录下，你会看到类似的文件结构：

```bash
/opt/MyDocker/
├── containers/      # 运行中的容器数据
├── image/           # Docker 镜像
├── volumes/         # 持久化数据卷
├── overlay2/        # 镜像和容器的层存储
├── network/         # Docker 网络配置
└── tmp/             # 临时文件
```

------

### **🔎 如何检查 Docker 存储目录**

可以运行以下命令确认：

```bash
docker info | grep "Docker Root Dir"
```

它应该输出：

```bash
Docker Root Dir: /opt/MyDocker
```

这就表示 **所有 Docker 相关的数据** 已经正确存储到 `/opt/MyDocker` 里了。

------

### **💡 需要做的额外管理**

如果你想 **手动管理 Docker 数据**，可以：

1. **定期备份整个 `/opt/MyDocker` 目录**：

   ```bash
   tar -czvf docker_backup.tar.gz /opt/MyDocker
   ```

   这样可以随时恢复 Docker 数据。

2. **迁移到新服务器**：

   - 在新服务器上 

     解压备份

     ：

     ```bash
     tar -xzvf docker_backup.tar.gz -C /opt/MyDocker
     ```

   - 重启 Docker

     ：

     ```bash
     systemctl restart docker
     ```

3. **清理不用的镜像和容器**：

   ```bash
   docker system prune -a
   ```

   这样可以节省 `/opt/MyDocker` 目录的空间。



### 适用环境**

✅ 个人服务器（VPS）
✅ 树莓派（Raspberry Pi）
✅ Debian 12 / Ubuntu / ARM 设备

### **总结**

✅ **支持 `amd64`、`arm64`、`armhf` 架构**，适配 **VPS、树莓派、物联网设备**
✅ **`sudo -v` 预认证，避免频繁输入密码**
✅ **`rsync` 迁移 Docker 数据时更高效**，只在数据不同步时执行
✅ **如果 `daemon.json` 已有 `data-root`，不重复写入**，避免无意义改动
✅ **非 root 用户可直接运行 Docker，无需每次加 `sudo`**
✅ **如果 Docker 测试失败，自动打印日志，方便调试**
✅ **优化终端输出，用户体验更友好**



