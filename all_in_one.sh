#!/data/data/com.termux/files/usr/bin/bash

# Termux 照片和录音同步到 NAS 一体化脚本
# 作者: coolangcn
# 版本: 1.0.20
# 最后修改时间: 2025-11-11

# ==================== 配置区 ====================

# 默认配置（将根据手机型号自动更新）
PHONE_MODEL=""
RECORD_DIR="$HOME/records"
CAMERA_ID=1
INTERVAL_SECONDS=60
COMPRESSION_QUALITY=60
AUDIO_DURATION=60

# ==================== 函数定义 ====================

# 显示帮助信息
show_help() {
    echo "📸🎙️ Termux 照片和录音同步到 NAS 一体化脚本"
    echo "================================================"
    echo ""
    echo "用法:"
    echo "  安装并配置:     ./all_in_one.sh install [手机型号]"
    echo "  启动服务:       ./all_in_one.sh start"
    echo "  停止服务:       ./all_in_one.sh stop"
    echo "  查看照片日志:   ./all_in_one.sh photo-log"
    echo "  查看录音日志:   ./all_in_one.sh record-log"
    echo "  显示帮助:       ./all_in_one.sh help"
    echo ""
    echo "示例:"
    echo "  ./all_in_one.sh install Sony-1"
    echo "  ./all_in_one.sh start"
    echo "  ./all_in_one.sh stop"
    echo ""
}

# 检查是否在 Termux 环境中运行
check_termux() {
    if [ ! -d "/data/data/com.termux/files/usr" ]; then
        echo "❌ 错误: 此脚本必须在 Termux 环境中运行"
        exit 1
    fi
}

# 安装必要的包
install_packages() {
    echo "📥 安装必要的包..."
    pkg update -y
    pkg install -y termux-api rclone imagemagick cronie
    
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
}

# 配置 rclone
configure_rclone() {
    echo "⚙️ 配置 rclone..."
    if [ ! -f "$HOME/.config/rclone/rclone.conf" ]; then
        echo "📝 请配置 rclone 连接到您的 NAS:"
        rclone config
    else
        echo "✅ rclone 已配置"
    fi
}

# 停止正在运行的服务
stop_services() {
    echo "🛑 停止正在运行的服务..."
    
    # 停止照片同步服务
    if pgrep -f "photo_loop_function.sh" > /dev/null; then
        pkill -f "photo_loop_function.sh"
        echo "📸 照片同步服务已停止"
    else
        echo "📸 照片同步服务未运行"
    fi
    
    # 停止录音同步服务
    if pgrep -f "record_loop_function.sh" > /dev/null; then
        pkill -f "record_loop_function.sh"
        echo "🎙️ 录音同步服务已停止"
    else
        echo "🎙️ 录音同步服务未运行"
    fi
    
    # 清理可能残留的录音进程
    pkill -9 termux-microphone-record 2>/dev/null
    
    # 等待进程完全停止
    sleep 2
}

# 清理旧的文件
cleanup_old_files() {
    echo "🧹 清理旧的文件..."
    rm -f "$HOME/all_in_one.pid"
    rm -f "$HOME/photo_loop.pid"
    rm -f "$HOME/record_loop.pid"
    rm -f "$HOME/photo_loop.log"
    rm -f "$HOME/record_loop.log"
    rm -f "$HOME/photo_loop_nohup.log"
    rm -f "$HOME/record_loop_nohup.log"
}

# 照片循环函数
photo_loop() {
    # 创建必要的目录
    RECORD_DIR="$HOME/records"
    mkdir -p "$RECORD_DIR"
    
    # PID 文件
    PID_FILE="$HOME/photo_loop.pid"
    
    # 日志文件
    LOG_FILE="$HOME/photo_loop.log"
    
 
    
    # 检查 UPLOAD_TARGET 是否已设置
    if [ -z "$UPLOAD_TARGET" ]; then
        echo "❌ 错误: UPLOAD_TARGET 未设置" | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # --- 防重复执行 (PID 锁机制) ---
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            echo "⚠️ 脚本已在运行 (PID: $OLD_PID)，退出 $(date)" | tee -a "$LOG_FILE"
            exit 1
        else
            echo "🧹 清理旧 PID 文件，继续运行 $(date)" | tee -a "$LOG_FILE"
            rm -f "$PID_FILE"
        fi
    fi
    
    # 写入当前 PID
    echo $$ > "$PID_FILE"
    trap 'rm -f "$PID_FILE"; echo "🛑 拍照脚本结束 $(date)" | tee -a "$LOG_FILE"; exit 0' INT TERM EXIT
    
    # --- 启动信息 ---
    echo "📸 定时拍照脚本启动 $(date)" | tee -a "$LOG_FILE"
    echo "照片目录：$RECORD_DIR" | tee -a "$LOG_FILE"
    echo "压缩质量：${COMPRESSION_QUALITY}%" | tee -a "$LOG_FILE"
    echo "上传目标：$UPLOAD_TARGET" | tee -a "$LOG_FILE"
    echo "拍照间隔：${INTERVAL_SECONDS}s" | tee -a "$LOG_FILE"
    
    # --- 主循环 ---
    while true; do
        TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
        FILE="$RECORD_DIR/CameraPhoto_${TIMESTAMP}.jpg"
        TEMP_FILE="$FILE.tmp" # 临时文件用于防止压缩失败导致数据丢失
        
        echo "📷 正在拍照：$FILE" | tee -a "$LOG_FILE"
        
        # 1. 执行拍照命令
        termux-camera-photo -c "$CAMERA_ID" "$TEMP_FILE" 2>/dev/null
        PHOTO_STATUS=$?
        
        sleep 2 # 等待文件写入完成
        
        if [ $PHOTO_STATUS -ne 0 ]; then
            echo "❌ 拍照命令执行失败 (状态码: $PHOTO_STATUS) $(date)" | tee -a "$LOG_FILE"
            rm -f "$TEMP_FILE" 2>/dev/null # 清理可能的临时文件
            sleep 60
            continue
        fi
        
        if [ ! -s "$TEMP_FILE" ]; then
            echo "⚠️ 照片文件未生成或为空 $(date)" | tee -a "$LOG_FILE"
            sleep 60
            continue
        fi
        
        # 2. 执行压缩
        ORIGINAL_SIZE=$(du -h "$TEMP_FILE" | awk '{print $1}')
        echo "⚙️ 压缩中 (质量: ${COMPRESSION_QUALITY}%) 原大小: $ORIGINAL_SIZE" | tee -a "$LOG_FILE"
        
        # 使用 convert 命令压缩，并直接输出到最终文件路径
        magick convert "$TEMP_FILE" -quality "$COMPRESSION_QUALITY" "$FILE"
        COMPRESSION_STATUS=$?
        
        # 无论压缩成功与否，删除原始临时文件
        rm -f "$TEMP_FILE"
        
        if [ $COMPRESSION_STATUS -ne 0 ] || [ ! -s "$FILE" ]; then
            echo "❌ 图片压缩失败或文件为空 $(date)" | tee -a "$LOG_FILE"
            sleep 60
            continue
        fi
        
        COMPRESSED_SIZE=$(du -h "$FILE" | awk '{print $1}')
        echo "✅ 压缩完成。现大小: $COMPRESSED_SIZE" | tee -a "$LOG_FILE"
        
        # 3. 移动和上传逻辑
        echo "📤 移动照片至 NAS: $UPLOAD_TARGET/$(basename "$FILE")" | tee -a "$LOG_FILE"
        
        rclone_log_output=$(rclone move "$FILE" "$UPLOAD_TARGET" --ignore-errors --retries 3 --low-level-retries 1 --quiet 2>&1)
        RCLONE_STATUS=$?
        
        if [ $RCLONE_STATUS -eq 0 ]; then
            echo "✅ 移动成功 (照片已上传) $(date)" | tee -a "$LOG_FILE"
        else
            echo "❌ 移动失败 (状态码: $RCLONE_STATUS)。本地照片保留。" | tee -a "$LOG_FILE"
            echo "--- Rclone 错误详情 ---" | tee -a "$LOG_FILE"
            echo "$rclone_log_output" | tee -a "$LOG_FILE"
            echo "------------------------" | tee -a "$LOG_FILE"
        fi
        
        # 等待 INTERVAL_SECONDS 秒后，进行下一次拍照
        echo "😴 等待 ${INTERVAL_SECONDS} 秒..." | tee -a "$LOG_FILE"
        sleep "$INTERVAL_SECONDS"
    done
}

# 录音循环函数
record_loop() {
    # 创建必要的目录
    RECORD_DIR="$HOME/records"
    mkdir -p "$RECORD_DIR"
    
    # PID 文件
    PID_FILE="$HOME/record_loop.pid"
    
    # 日志文件
    LOG_FILE="$HOME/record_loop.log"
    
 
    
    # 检查 UPLOAD_TARGET 是否已设置
    if [ -z "$UPLOAD_TARGET" ]; then
        echo "❌ 错误: UPLOAD_TARGET 未设置" | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # --- 防重复执行 (使用 PID 文件作为锁) ---
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            echo "⚠️ 脚本已在运行 (PID: $OLD_PID)，退出 $(date)" | tee -a "$LOG_FILE"
            exit 1
        else
            echo "🧹 清理旧 PID 文件，继续运行 $(date)" | tee -a "$LOG_FILE"
            rm -f "$PID_FILE"
        fi
    fi
    
    # 写入当前 PID
    echo $$ > "$PID_FILE"
    # 使用 trap 确保脚本退出时清理 PID 文件和所有录音进程
    trap 'rm -f "$PID_FILE"; termux-microphone-record -q 2>/dev/null; pkill termux-microphone-record 2>/dev/null; echo "🛑 录音脚本结束 $(date)" | tee -a "$LOG_FILE"; exit 0' INT TERM EXIT
    
    # --- 启动前强制清理 ---
    if pgrep termux-microphone-record > /dev/null; then
        echo "🚨 启动前，尝试终止残留录音进程..." | tee -a "$LOG_FILE"
        termux-microphone-record -q 2>/dev/null
        sleep 2
        pkill -9 termux-microphone-record 2>/dev/null
        sleep 2
    fi
    
    # --- 启动信息 ---
    echo "🎙️ 循环录音脚本启动 (Q模式) $(date)" | tee -a "$LOG_FILE"
    echo "录音目录：$RECORD_DIR" | tee -a "$LOG_FILE"
    echo "上传目标：$UPLOAD_TARGET" | tee -a "$LOG_FILE"
    echo "录音时长：${AUDIO_DURATION}s" | tee -a "$LOG_FILE"
    
    # --- 主循环 ---
    while true; do
        # 循环内清理残留录音进程
        termux-microphone-record -q 2>/dev/null
        sleep 1
        pkill -9 termux-microphone-record 2>/dev/null
        sleep 1
        
        TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
        FILE="$RECORD_DIR/TermuxAudioRecording_${TIMESTAMP}.acc" # 当前文件仍需生成文件名
        
        echo "🎧 开始录音：$FILE" | tee -a "$LOG_FILE"
        
        # 使用 -l 0 启动无限录音
        termux-microphone-record -e acc -l 0 -f "$FILE" 2>/dev/null &
        PID=$!
        
        # 等待录音进程启动并开始写入文件
        sleep 3
        
        # 检查录音文件是否已创建
        if [ ! -f "$FILE" ]; then
            echo "❌ 录音进程启动失败，未创建文件 $(date)" | tee -a "$LOG_FILE"
            # 尝试清理
            termux-microphone-record -q 2>/dev/null
            pkill -9 termux-microphone-record 2>/dev/null
            sleep 3
            continue
        fi
        
        # 通过 sleep 精确控制录音时长
        echo "⏳ 录音中... 持续 ${AUDIO_DURATION} 秒..." | tee -a "$LOG_FILE"
        sleep "$AUDIO_DURATION"
        
        # 发送 -q 信号，终止录音
        echo "⏹️ 终止录音..." | tee -a "$LOG_FILE"
        termux-microphone-record -q 2>/dev/null
        
        # 等待录音进程完全退出，并写入文件
        sleep 2
        
        # 再次使用 pkill 确保进程完全终止，防止残留
        pkill -9 termux-microphone-record 2>/dev/null
        sleep 1
        
        # 检查当前文件大小，如果为空则删除并跳过上传
        if [ ! -s "$FILE" ]; then
            echo "⚠️ 当前录音文件为空或录音失败 $(date)" | tee -a "$LOG_FILE"
            rm -f "$FILE" 2>/dev/null
            sleep 3
            continue
        fi
        
        echo "📤 移动所有 .acc 文件至 NAS: $UPLOAD_TARGET/" | tee -a "$LOG_FILE"
        
        # 使用 cd 进入目录，并 rclone move 整个目录中所有符合条件的 (.acc) 文件
        # --include "*.acc" 确保只移动录音文件，不移动日志或 PID 文件
        rclone_log_output=$(cd "$RECORD_DIR" && rclone move . "$UPLOAD_TARGET" --include "*.acc" --ignore-errors --retries 3 --low-level-retries 1 --quiet 2>&1)
        RCLONE_STATUS=$?
        
        if [ $RCLONE_STATUS -eq 0 ]; then
            echo "✅ 移动成功 (所有 .acc 文件已上传) $(date)" | tee -a "$LOG_FILE"
        else
            echo "❌ 移动失败 (状态码: $RCLONE_STATUS)。本地录音文件保留。" | tee -a "$LOG_FILE"
            echo "--- Rclone 错误详情 ---" | tee -a "$LOG_FILE"
            echo "$rclone_log_output" | tee -a "$LOG_FILE"
            echo "------------------------" | tee -a "$LOG_FILE"
        fi
        
        # 等待 3 秒后，进行下一次录音
        echo "😴 等待 3 秒..." | tee -a "$LOG_FILE"
        sleep 3
    done
}

# 安装脚本
install_script() {
    echo "💾 安装 Termux 照片和录音同步到 NAS 一体化脚本..."
    
    # 停止正在运行的服务
    stop_services
    
    # 清理旧的文件
    cleanup_old_files
    
    # 复制当前脚本到 HOME 目录
    cp "$0" "$HOME/all_in_one.sh"
    chmod +x "$HOME/all_in_one.sh"
    
    # 【修复】使用 sed 将手机型号永久写入新脚本的配置区
    # 使用 | 作为分隔符，避免 $HOME 路径中的 / 导致冲突
    if ! sed -i "s|^PHONE_MODEL=\"\"|PHONE_MODEL=\"$PHONE_MODEL\"|" "$HOME/all_in_one.sh"; then
        echo "❌ 错误: 无法将手机型号写入 $HOME/all_in_one.sh"
        exit 1
    fi
    echo "✅ 手机型号 ($PHONE_MODEL) 已保存到 $HOME/all_in_one.sh"
    
    echo "✅ 一体化脚本已安装到 $HOME"
    
    # 设置定时任务以自动启动脚本
    echo "⏰ 设置定时任务以自动启动脚本..."
    
    # 检查是否安装了 cronie 包
    if ! command -v crontab &> /dev/null; then
        echo "⚠️ 未找到 crontab 命令，正在安装 cronie 包..."
        pkg install -y cronie
    fi
    
    # 再次检查是否安装了 crontab
    if command -v crontab &> /dev/null; then
        # 备份现有的 crontab
        if crontab -l > "$HOME/crontab_backup_$(date +%Y%m%d_%H%M%S)" 2>/dev/null; then
            echo "📋 已备份现有 crontab 到 $HOME"
        fi
        
        # 创建新的 crontab 条目
        (crontab -l 2>/dev/null | grep -v "$HOME/all_in_one.sh start"; echo "@reboot $HOME/all_in_one.sh start") | crontab -
        echo "✅ 定时任务已设置，系统重启后将自动启动同步服务"
    else
        echo "❌ 无法安装或找不到 crontab，无法设置定时任务"
        echo "💡 您可以手动运行以下命令来启动服务:"
        echo "   $HOME/all_in_one.sh start"
    fi
    
    # 显示使用说明和 NAS 接收目录
    echo ""
    echo "🎉 部署完成！"
    echo ""
    echo "📱 手机型号: $PHONE_MODEL"
    echo "📂 NAS 照片接收目录: synology:/download/records/${PHONE_MODEL}_Photos"
    echo "📂 NAS 音频接收目录: synology:/download/records/${PHONE_MODEL}"
    echo ""
    echo "📄 脚本版本信息:"
    echo "  版本号: 1.0.19"
    echo "  最后修改时间: 2025-11-11"
    echo ""
    echo "📌 使用说明:"
    echo "  启动服务: $HOME/all_in_one.sh start"
    echo "  停止服务: $HOME/all_in_one.sh stop"
    echo "  查看照片日志: tail -f $HOME/photo_loop.log"
    echo "  查看录音日志: tail -f $HOME/record_loop.log"
    echo ""
    echo "📝 注意事项:"
    echo "  1. 请确保已正确配置 rclone 连接到您的 NAS"
    echo "  2. 如果设置了定时任务，系统重启后服务将自动启动"
    echo ""
    echo "🔧 配置文件位置:"
    echo "  一体化脚本: $HOME/all_in_one.sh"
    echo "  rclone 配置: ~/.config/rclone/rclone.conf"
}

# 启动服务
start_services() {
    echo "🚀 启动照片和录音同步服务..."
    
    # 检查是否已安装脚本
    if [ ! -f "$HOME/all_in_one.sh" ]; then
        echo "❌ 错误: 请先运行安装命令: $0 install [手机型号]"
        exit 1
    fi
    
    # 创建日志文件
    touch "$HOME/photo_loop.log" "$HOME/record_loop.log"
    
    # 启动照片同步服务
    if pgrep -f "all_in_one.sh.*photo_loop" > /dev/null; then
        echo "📸 照片同步服务已在运行"
    else
        # 更新照片脚本中的 UPLOAD_TARGET
        PHOTO_UPLOAD_TARGET="synology:/download/records/${PHONE_MODEL}_Photos"
        echo "🔄 启动照片同步服务，上传目标: $PHOTO_UPLOAD_TARGET"
        
        # 直接调用函数，不使用临时脚本
        (
            UPLOAD_TARGET="$PHOTO_UPLOAD_TARGET"
            export UPLOAD_TARGET COMPRESSION_QUALITY CAMERA_ID INTERVAL_SECONDS
            photo_loop
        ) &
        echo "📸 照片同步服务已启动"
    fi
    
    # 启动录音同步服务
    if pgrep -f "all_in_one.sh.*record_loop" > /dev/null; then
        echo "🎙️ 录音同步服务已在运行"
    else
        # 更新录音脚本中的 UPLOAD_TARGET
        RECORD_UPLOAD_TARGET="synology:/download/records/${PHONE_MODEL}"
        echo "🔄 启动录音同步服务，上传目标: $RECORD_UPLOAD_TARGET"
        
        # 直接调用函数，不使用临时脚本
        (
            UPLOAD_TARGET="$RECORD_UPLOAD_TARGET"
            export UPLOAD_TARGET AUDIO_DURATION
            record_loop
        ) &
        echo "🎙️ 录音同步服务已启动"
    fi
    
    echo "✅ 所有服务已启动"
    echo "日志:"
    echo "  照片日志: tail -f $HOME/photo_loop.log"
    echo "  录音日志: tail -f $HOME/record_loop.log"
}

# 主函数
main() {
    # 检查是否在 Termux 环境中运行
    check_termux
    
    # 解析命令行参数
    case "${1:-}" in
        install)
            if [ -z "${2:-}" ]; then
                echo "📱 请输入您的手机型号（例如: Pixel_5, Samsung_S21等）:"
                read PHONE_MODEL
            else
                PHONE_MODEL="$2"
            fi
            
            if [ -z "$PHONE_MODEL" ]; then
                echo "❌ 错误: 手机型号不能为空"
                exit 1
            fi
            
            # 安装必要的包
            install_packages
            
            # 配置 rclone
            configure_rclone
            
            # 安装脚本
            install_script
            ;;
        start)
            # 【修复】PHONE_MODEL 变量在脚本启动时已从顶部配置区加载
            # 我们只需要检查它是否为空
            
            if [ -z "$PHONE_MODEL" ]; then
                echo "❌ 错误: 手机型号未设置。"
                echo "💡 请先运行安装命令以设置型号:"
                echo "   $0 install [您的手机型号]"
                exit 1
            fi
            
            echo "✅ 成功加载手机型号: $PHONE_MODEL"
            start_services
            ;;
        stop)
            stop_services
            ;;
        photo-log)
            if [ -f "$HOME/photo_loop.log" ]; then
                tail -f "$HOME/photo_loop.log"
            else
                echo "❌ 照片日志文件不存在"
                exit 1
            fi
            ;;
        record-log)
            if [ -f "$HOME/record_loop.log" ]; then
                tail -f "$HOME/record_loop.log"
            else
                echo "❌ 录音日志文件不存在"
                exit 1
            fi
            ;;
        help|*)
            show_help
            ;;
    esac
}

# ==================== 程序入口 ====================
main "$@"