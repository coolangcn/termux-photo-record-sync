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

- `photo_loop.sh`: 照片拍摄和同步脚本
- `record_loop.sh`: 音频录制和同步脚本
- `install.sh`: 一键部署安装脚本
- `download_and_install.sh`: 从 GitHub 下载并安装的脚本

## 部署安装

### 方法一：从 GitHub 直接下载安装（推荐）

在 Termux 中运行以下命令：

```bash
curl -s https://raw.githubusercontent.com/coolangcn/termux-photo-record-sync/main/download_and_install.sh | bash
```

### 方法二：手动下载安装

1. 克隆或下载此仓库到您的计算机
2. 将所有 `.sh` 文件传输到您的 Android 设备上的 Termux 环境
3. 在 Termux 中运行安装脚本：

```bash
chmod +x install.sh
./install.sh
```

安装脚本将自动完成以下操作：
- 安装必要的依赖项（termux-api, rclone, imagemagick）
- 配置 rclone 连接您的 NAS
- 安装照片和录音同步脚本到您的主目录
- 询问您的手机型号以区分不同设备的存储路径
- 创建启动和停止脚本
- 设置系统重启后自动启动服务

## 配置

安装完成后，您可能需要根据您的需求修改以下配置：

### 照片同步配置 (`~/photo_loop.sh`)
- `UPLOAD_TARGET`: 修改为您的 NAS 目标路径
- `CAMERA_ID`: 摄像头 ID（通常为 0 或 1）
- `INTERVAL_SECONDS`: 拍照间隔（秒）
- `COMPRESSION_QUALITY`: 照片压缩质量（0-100）

### 音频录制配置 (`~/record_loop.sh`)
- `UPLOAD_TARGET`: 修改为您的 NAS 目标路径
- `DURATION`: 每段录音的时长（秒）

### rclone 配置
运行以下命令配置 rclone 连接您的 NAS：
```bash
rclone config
```

## 使用方法

### 启动服务
```bash
~/start_sync.sh
```

### 停止服务
```bash
~/stop_sync.sh
```

### 查看日志
```bash
# 查看照片同步日志
tail -f ~/photo_loop.log

# 查看录音同步日志
tail -f ~/record_loop.log
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