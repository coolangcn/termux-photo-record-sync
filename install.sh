#!/data/data/com.termux/files/usr/bin/bash

# Termux 照片和录音同步到 NAS 一键部署脚本
# 作者: coolangcn
# 版本: 1.0.13
# 最后修改时间: 2025-11-10

set -e

echo "📸🎙️ Termux 照片和录音同步到 NAS 一键部署脚本"
echo "================================================"

# 检查是否在 Termux 环境中运行
if [ ! -d "/data/data/com.termux/files/usr" ]; then
    echo "❌ 错误: 此脚本必须在 Termux 环境中运行"
    exit 1
fi

# 获取手机型号参数
if [ $# -eq 0 ]; then
    echo "❌ 错误: 请提供手机型号作为参数"
    echo "💡 用法: $0 <手机型号>"
    echo "💡 例如: $0 Pixel_5"
    exit 1
fi

PHONE_MODEL="$1"

# 创建必要的目录
RECORD_DIR="$HOME/records"
mkdir -p "$RECORD_DIR"

# 安装必要的包
echo "📥 安装必要的包..."
pkg update -y
pkg install -y termux-api rclone imagemagick

# 检查是否安装成功
if ! command -v termux-camera-photo &> /dev/null; then
    echo "❌ 错误: termux-camera-photo 未安装成功"
    exit 1
fi

if ! command -v termux-microphone-record &> /dev/null; then
    echo "❌ 错误: termux-microphone-record 未安装成功"
    exit 1
fi

if ! command -v rclone &> /dev/null; then
    echo "❌ 错误: rclone 未安装成功"
    exit 1
fi

if ! command -v magick &> /dev/null; then
    echo "❌ 错误: imagemagick 未安装成功"
    exit 1
fi

echo "✅ 必要包安装完成"

# 配置 rclone
echo "⚙️ 配置 rclone..."
if [ ! -f "$HOME/.config/rclone/rclone.conf" ]; then
    echo "📝 请配置 rclone 连接到您的 NAS:"
    rclone config
else
    echo "✅ rclone 已配置"
fi

# 停止正在运行的服务
echo "🛑 停止正在运行的服务..."
if pgrep -f "photo_loop.sh" > /dev/null; then
    pkill -f "photo_loop.sh"
    echo "📸 照片同步服务已停止"
fi

if pgrep -f "record_loop.sh" > /dev/null; then
    pkill -f "record_loop.sh"
    echo "🎙️ 录音同步服务已停止"
fi

# 清理可能残留的录音进程
pkill -9 termux-microphone-record 2>/dev/null

# 清理旧的脚本文件
echo "🧹 清理旧的脚本文件..."
rm -f "$HOME/photo_loop.sh"
rm -f "$HOME/record_loop.sh"
rm -f "$HOME/start_sync.sh"
rm -f "$HOME/stop_sync.sh"

# 复制并安装脚本
echo "💾 安装照片和录音同步脚本..."

# 复制 photo_loop.sh (从当前目录)
cp "$(dirname "$0")/photo_loop.sh" "$HOME/photo_loop.sh" 2>/dev/null || {
    echo "❌ 错误: 无法找到 photo_loop.sh，请确保它与 install.sh 在同一目录"
    exit 1
}

# 复制 record_loop.sh (从当前目录)
cp "$(dirname "$0")/record_loop.sh" "$HOME/record_loop.sh" 2>/dev/null || {
    echo "❌ 错误: 无法找到 record_loop.sh，请确保它与 install.sh 在同一目录"
    exit 1
}

# 显示替换前的 UPLOAD_TARGET 值
echo "🔍 替换前的配置:"
echo "  照片脚本中的 UPLOAD_TARGET: $(grep 'UPLOAD_TARGET=' "$HOME/photo_loop.sh" | head -n 1)"
echo "  音频脚本中的 UPLOAD_TARGET: $(grep 'UPLOAD_TARGET=' "$HOME/record_loop.sh" | head -n 1)"

// 更新 photo_loop.sh 中的 UPLOAD_TARGET
echo "🔄 更新照片脚本中的 UPLOAD_TARGET..."
sed -i "s|UPLOAD_TARGET=\"\"|UPLOAD_TARGET=\"synology:/download/records/${PHONE_MODEL}_Photos\"|" "$HOME/photo_loop.sh"
// 检查 sed 命令是否成功执行
if [ $? -eq 0 ]; then
    echo "✅ 照片脚本中的 UPLOAD_TARGET 更新成功"
else
    echo "❌ 照片脚本中的 UPLOAD_TARGET 更新失败"
fi

// 更新 record_loop.sh 中的 UPLOAD_TARGET
echo "🔄 更新音频脚本中的 UPLOAD_TARGET..."
sed -i "s|UPLOAD_TARGET=\"\"|UPLOAD_TARGET=\"synology:/download/records/${PHONE_MODEL}\"|" "$HOME/record_loop.sh"
// 检查 sed 命令是否成功执行
if [ $? -eq 0 ]; then
    echo "✅ 音频脚本中的 UPLOAD_TARGET 更新成功"
else
    echo "❌ 音频脚本中的 UPLOAD_TARGET 更新失败"
fi

// 显示替换后的 UPLOAD_TARGET 值
echo "🔍 替换后的配置:"
echo "  照片脚本中的 UPLOAD_TARGET: $(grep 'UPLOAD_TARGET=' "$HOME/photo_loop.sh" | head -n 1)"
echo "  音频脚本中的 UPLOAD_TARGET: $(grep 'UPLOAD_TARGET=' "$HOME/record_loop.sh" | head -n 1)"

// 添加执行权限
chmod +x "$HOME/photo_loop.sh"
chmod +x "$HOME/record_loop.sh"

echo "✅ 照片和录音同步脚本已安装到 $HOME"

// 创建启动脚本
cat > "$HOME/start_sync.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

// 启动照片和录音同步服务

echo "🚀 启动照片和录音同步服务..."

// 启动照片同步服务
if pgrep -f "photo_loop.sh" > /dev/null; then
    echo "📸 照片同步服务已在运行"
else
    nohup "$HOME/photo_loop.sh" > "$HOME/photo_loop_nohup.log" 2>&1 &
    echo "📸 照片同步服务已启动"
fi

// 启动录音同步服务
if pgrep -f "record_loop.sh" > /dev/null; then
    echo "🎙️ 录音同步服务已在运行"
else
    nohup "$HOME/record_loop.sh" > "$HOME/record_loop_nohup.log" 2>&1 &
    echo "🎙️ 录音同步服务已启动"
fi

echo "✅ 所有服务已启动"
echo "日志:"
echo "  照片日志: tail -f $HOME/photo_loop.log"
echo "  录音日志: tail -f $HOME/record_loop.log"
EOF

chmod +x "$HOME/start_sync.sh"

// 创建停止脚本
cat > "$HOME/stop_sync.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

// 停止照片和录音同步服务

echo "🛑 停止照片和录音同步服务..."

// 停止照片同步服务
if pgrep -f "photo_loop.sh" > /dev/null; then
    pkill -f "photo_loop.sh"
    echo "📸 照片同步服务已停止"
else
    echo "📸 照片同步服务未运行"
fi

// 停止录音同步服务
if pgrep -f "record_loop.sh" > /dev/null; then
    pkill -f "record_loop.sh"
    echo "🎙️ 录音同步服务已停止"
else
    echo "🎙️ 录音同步服务未运行"
fi

// 清理可能残留的录音进程
pkill -9 termux-microphone-record 2>/dev/null

echo "✅ 所有服务已停止"
EOF

chmod +x "$HOME/stop_sync.sh"

// 设置定时任务以自动启动脚本
echo "⏰ 设置定时任务以自动启动脚本..."

// 检查是否安装了 cronie 包
if ! command -v crontab &> /dev/null; then
    echo "⚠️ 未找到 crontab 命令，正在安装 cronie 包..."
    pkg install -y cronie
fi

// 再次检查是否安装了 crontab
if command -v crontab &> /dev/null; then
    // 备份现有的 crontab
    if crontab -l > "$HOME/crontab_backup_$(date +%Y%m%d_%H%M%S)" 2>/dev/null; then
        echo "📋 已备份现有 crontab 到 $HOME"
    fi

    // 创建新的 crontab 条目
    (crontab -l 2>/dev/null; echo "@reboot $HOME/start_sync.sh") | crontab -
    echo "✅ 定时任务已设置，系统重启后将自动启动同步服务"
else
    echo "❌ 无法安装或找不到 crontab，无法设置定时任务"
    echo "💡 您可以手动运行以下命令来启动服务:"
    echo "   $HOME/start_sync.sh"
fi

// 显示使用说明和 NAS 接收目录
echo ""
echo "🎉 部署完成！"
echo ""
echo "📱 手机型号: $PHONE_MODEL"
echo "📂 NAS 照片接收目录: synology:/download/records/${PHONE_MODEL}_Photos"
echo "📂 NAS 音频接收目录: synology:/download/records/${PHONE_MODEL}"
echo ""
echo "📄 脚本版本信息:"
echo "  版本号: 1.0.13"
echo "  最后修改时间: 2025-11-10"
echo ""
echo "📌 使用说明:"
echo "  启动服务: $HOME/start_sync.sh"
echo "  停止服务: $HOME/stop_sync.sh"
echo "  查看照片日志: tail -f $HOME/photo_loop.log"
echo "  查看录音日志: tail -f $HOME/record_loop.log"
echo ""
echo "📝 注意事项:"
echo "  1. 请确保已正确配置 rclone 连接到您的 NAS"
echo "  2. 如果设置了定时任务，系统重启后服务将自动启动"
echo ""
echo "🔧 配置文件位置:"
echo "  照片同步脚本: $HOME/photo_loop.sh"
echo "  录音同步脚本: $HOME/record_loop.sh"
echo "  rclone 配置: ~/.config/rclone/rclone.conf"