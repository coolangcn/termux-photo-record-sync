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

# 检查参数 (支持通过 -s 传递参数)
PHONE_MODEL=""
if [ $# -gt 0 ]; then
    PHONE_MODEL="$1"
fi

# 如果没有通过参数传递，则尝试从标准输入读取
if [ -z "$PHONE_MODEL" ]; then
    # 检查是否有标准输入
    if [ ! -t 0 ]; then
        read PHONE_MODEL
    fi
fi

# 如果仍然没有手机型号，则提示用户输入
if [ -z "$PHONE_MODEL" ]; then
    echo "📱 请输入您的手机型号（例如: Pixel_5, Samsung_S21等）:"
    read PHONE_MODEL
fi

if [ -z "$PHONE_MODEL" ]; then
    echo "❌ 错误: 手机型号不能为空"
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

# 运行安装脚本，传递手机型号参数
echo "🚀 运行安装脚本..."
# 使用多种方式确保参数能传递给 install.sh 脚本
if [ ! -t 0 ]; then
    # 如果有标准输入，通过管道传递
    echo "$PHONE_MODEL" | ./install.sh
else
    # 如果没有标准输入，通过参数传递
    ./install.sh <<< "$PHONE_MODEL"
fi

# 清理临时目录
cd ~
rm -rf "$TEMP_DIR"

echo "✅ 安装完成！"
echo ""
echo "📱 手机型号: $PHONE_MODEL"
echo "📂 NAS 照片接收目录: synology:/download/records/${PHONE_MODEL}_Photos"
echo "📂 NAS 音频接收目录: synology:/download/records/${PHONE_MODEL}"
echo ""
echo "💡 提示: 如果您希望系统重启后自动启动同步服务，请确保已安装 cronie 包:"
echo "   pkg install cronie"
echo ""
echo "📌 您现在可以使用以下命令来启动服务:"
echo "   ~/start_sync.sh"