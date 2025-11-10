#!/data/data/com.termux/files/usr/bin/bash

# Termux 照片和录音同步到 NAS 下载安装脚本
# 作者: coolangcn

GITHUB_USER="coolangcn"
GITHUB_REPO="termux-photo-record-sync"
GITHUB_BRANCH="main"

echo "📸🎙️ Termux 照片和录音同步到 NAS 下载安装脚本"
echo "================================================"

# 检查是否在 Termux 环境中运行
if [ ! -d "/data/data/com.termux/files/usr" ]; then
    echo "❌ 错误: 此脚本必须在 Termux 环境中运行"
    exit 1
fi

# 检查是否安装了 curl
if ! command -v curl &> /dev/null; then
    echo "📥 安装 curl..."
    pkg install -y curl
fi

# 创建临时目录
TEMP_DIR=$(mktemp -d)
echo "📁 创建临时目录: $TEMP_DIR"

# 进入临时目录
cd "$TEMP_DIR"

echo "📥 从 GitHub 下载安装文件..."

# 从 GitHub 下载文件
FILES=("install.sh" "photo_loop.sh" "record_loop.sh")

for file in "${FILES[@]}"; do
    echo "📥 下载 $file..."
    curl -s -O "https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/$file"
    
    # 检查下载是否成功
    if [ ! -f "$file" ]; then
        echo "❌ 错误: 无法下载 $file"
        exit 1
    fi
done

# 添加执行权限
chmod +x install.sh

# 运行安装脚本，保持标准输入连接
echo "🚀 运行安装脚本..."
bash -i ./install.sh

# 清理临时目录
cd ~
rm -rf "$TEMP_DIR"

echo "✅ 安装完成！"
echo ""
echo "💡 提示: 如果您希望系统重启后自动启动同步服务，请确保已安装 cronie 包:"
echo "   pkg install cronie"
echo ""
echo "📌 您现在可以使用以下命令来启动服务:"
echo "   ~/start_sync.sh"