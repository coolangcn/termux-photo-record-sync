# Termux 照片和录音同步到 NAS

这是一个用于在 Termux 环境中自动拍摄照片和录制音频，并将它们同步到 NAS 的解决方案。

## 功能特性

- 📸 定时拍照并压缩上传到 NAS
- 🎙️ 循环录音并上传到 NAS
- 🔄 自动同步，断线重连
- ⏰ 系统重启后自动启动
- 📋 一键部署安装
- 📱 支持多设备区分存储（通过手机型号）

## 文件说明

- `all_in_one.sh`: 一体化脚本（包含所有功能）

## 部署安装

### 方法一：从 GitHub 直接下载安装（推荐）

在 Termux 中运行以下命令：

```bash
curl -s https://raw.githubusercontent.com/coolangcn/termux-photo-record-sync/main/all_in_one.sh -o all_in_one.sh && chmod +x all_in_one.sh && ./all_in_one.sh install
```

### 方法二：手动下载安装

1. 克隆或下载此仓库到您的计算机
2. 将 `all_in_one.sh` 文件传输到您的 Android 设备上的 Termux 环境
3. 在 Termux 中运行脚本：

```bash
chmod +x all_in_one.sh
./all_in_one.sh install
```

安装脚本将自动完成以下操作：
- 安装必要的依赖项（termux-api, rclone, imagemagick）
- 配置 rclone 连接您的 NAS
- 安装照片和录音同步脚本到您的主目录
- 询问您的手机型号以区分不同设备的存储路径
- 设置系统重启后自动启动服务

## 配置

安装完成后，您可能需要根据您的需求修改以下配置：

### rclone 配置
运行以下命令配置 rclone 连接您的 NAS：
```bash
rclone config
```

## 使用方法

### 启动服务
```bash
./all_in_one.sh start
```

### 停止服务
```bash
./all_in_one.sh stop
```

### 查看日志
```bash
./all_in_one.sh photo-log
./all_in_one.sh record-log
```

## 注意事项

1. 确保您的设备已授予 Termux 相机和麦克风权限
2. 确保设备连接到互联网以便上传文件到 NAS
3. 建议在设备充电时使用此功能以避免电池消耗过快
4. 根据您的存储空间和 NAS 容量合理设置拍照间隔和录音时长
5. 如果希望系统重启后自动启动服务，需要安装 `cronie` 包：
   ```bash
   pkg install cronie
   ```

## 许可证

本项目采用 MIT 许可证