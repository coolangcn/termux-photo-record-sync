#!/data/data/com.termux/files/usr/bin/bash

# Termux 录音同步到 NAS 脚本
# 作者: coolangcn
# 版本: 1.0.23
# 最后修改时间: 2026-03-25

# ==================== 配置区 ====================

# 默认配置（将根据手机型号自动更新）
PHONE_MODEL=""
RECORD_DIR="$HOME/records"
AUDIO_DURATION=60

# ==================== 函数定义 ====================

# 显示帮助信息
show_help() {
    echo "🎙️ Termux 录音同步到 NAS 脚本"
    echo "================================"
    echo ""
    echo "用法:"
    echo "  安装并配置:     ./all_in_one.sh install [手机型号]"
    echo "  启动服务:       ./all_in_one.sh start"
    echo "  停止服务:       ./all_in_one.sh stop"
    echo "  查看录音日志:   ./all_in_one.sh record-log"
    echo "  检查并修复服务: ./all_in_one.sh watchdog"
    echo "  显示帮助:       ./all_in_one.sh help"
    echo ""
    echo "示例:"
    echo "  ./all_in_one.sh install Sony-1"
    echo "  ./all_in_one.sh start"
    echo "  ./all_in_one.sh watchdog"
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
    pkg install -y termux-api rclone cronie
    
    # 检查是否安装成功
    if ! command -v termux-microphone-record &> /dev/null; then
        echo "❌ 错误: termux-microphone-record 未安装成功"
        exit 1
    fi
    
    if ! command -v rclone &> /dev/null; then
        echo "❌ 错误: rclone 未安装成功"
        exit 1
    fi
    
    echo "✅ 必要包安装完成"
}

# 发送 Termux 通知
send_notification() {
    local title="$1"
    local message="$2"
    local id="${3:-termux_sync_watchdog}"
    
    if command -v termux-notification &> /dev/null; then
        termux-notification -t "$title" -c "$message" --id "$id"
    else
        echo "⚠️ termux-api 未安装，无法发送通知"
    fi
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
    
    # 停止录音同步服务
    if pgrep -f "all_in_one.sh.*record_loop" > /dev/null; then
        pkill -f "all_in_one.sh.*record_loop"
        echo "🎙️ 录音同步服务已停止"
    else
        echo "🎙️ 录音同步服务未运行"
    fi
    
    if pgrep -f "all_in_one.sh start" > /dev/null; then
        pkill -f "all_in_one.sh start"
        echo "🎙️ 录音同步服务 (all_in_one.sh start) 已停止"
    else
        echo "🎙️ 录音同步服务 (all_in_one.sh start) 未运行"
    fi
    
    # 停止旧的脚本进程
    if pgrep -f "record_loop.sh" > /dev/null; then
        pkill -f "record_loop.sh"
        echo "🎙️ 旧录音同步服务已停止"
    else
        echo "🎙️ 旧录音同步服务未运行"
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
    rm -f "$HOME/watchdog.log"
}

# 录音循环函数 - 最小延迟快速切换模式
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
        sleep 1
        pkill -9 termux-microphone-record 2>/dev/null
        sleep 1
    fi
    
    # --- 启动信息 ---
    echo "🎙️ 循环录音脚本启动 (最小延迟快速切换模式) $(date)" | tee -a "$LOG_FILE"
    echo "录音目录：$RECORD_DIR" | tee -a "$LOG_FILE"
    echo "上传目标：$UPLOAD_TARGET" | tee -a "$LOG_FILE"
    echo "录音时长：${AUDIO_DURATION}s" | tee -a "$LOG_FILE"
    
    # --- 最小延迟主循环 ---
    # 注意：由于手机麦克风通常只能被一个进程独占使用
    # 无法实现真正的双线程同时录音，只能通过最小化切换延迟来优化
    
    while true; do
        # 快速清理残留进程
        termux-microphone-record -q 2>/dev/null
        pkill -9 termux-microphone-record 2>/dev/null
        
        TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
        FILE="$RECORD_DIR/TermuxAudioRecording_${TIMESTAMP}.m4a"
        
        echo "🎧 开始录音：$FILE" | tee -a "$LOG_FILE"
        
        # 使用 -l 0 启动无限录音，然后通过 -q 控制停止
        termux-microphone-record -e wav -r 16000 -l 0 -f "$FILE" 2>/dev/null &
        PID=$!
        
        # 等待录音进程启动并创建文件
        START_WAIT=0
        while [ $START_WAIT -lt 15 ] && [ ! -f "$FILE" ]; do
            sleep 0.1
            START_WAIT=$((START_WAIT + 1))
        done
        
        # 检查录音文件是否已创建
        if [ ! -f "$FILE" ]; then
            echo "❌ 录音进程启动失败，未创建文件 $(date)" | tee -a "$LOG_FILE"
            kill $PID 2>/dev/null
            termux-microphone-record -q 2>/dev/null
            pkill -9 termux-microphone-record 2>/dev/null
            sleep 0.5
            continue
        fi
        
        # 等待录音时长
        echo "⏳ 录音中... 持续 ${AUDIO_DURATION} 秒..." | tee -a "$LOG_FILE"
        sleep "$AUDIO_DURATION"
        
        # 发送 -q 信号停止录音
        echo "⏹️ 停止录音..." | tee -a "$LOG_FILE"
        termux-microphone-record -q 2>/dev/null
        
        # 快速等待进程结束
        STOP_WAIT=0
        while [ $STOP_WAIT -lt 10 ] && ps -p $PID > /dev/null 2>&1; do
            sleep 0.1
            STOP_WAIT=$((STOP_WAIT + 1))
        done
        pkill -9 termux-microphone-record 2>/dev/null
        
        # 检查录音文件
        if [ ! -s "$FILE" ]; then
            echo "⚠️ 当前录音文件为空或录音失败 $(date)" | tee -a "$LOG_FILE"
            rm -f "$FILE" 2>/dev/null
            sleep 0.3
            continue
        fi
        
        # 按日期文件夹存放
        CURRENT_DATE=$(date +%Y-%m-%d)
        DATE_TARGET="$UPLOAD_TARGET/$CURRENT_DATE"
        echo "📤 上传录音文件: $(basename "$FILE") 至 $DATE_TARGET" | tee -a "$LOG_FILE"
        
        # 后台上传，不阻塞下一次录音
        (
            rclone_log_output=$(rclone move "$FILE" "$DATE_TARGET" --ignore-errors --retries 3 --low-level-retries 1 --quiet 2>&1)
            if [ $? -eq 0 ]; then
                echo "✅ 上传成功: $(basename "$FILE") 至 $DATE_TARGET $(date)" | tee -a "$LOG_FILE"
            else
                echo "❌ 上传失败: $(basename "$FILE")" | tee -a "$LOG_FILE"
            fi
        ) &
        
        # 极短暂等待后立即开始下一次录音
        sleep 0.2
    done
}

# 检查服务状态
check_service_status() {
    local service_name="$1"
    local pattern="$2"
    
    if pgrep -f "$pattern" > /dev/null; then
        return 0 # 正在运行
    else
        return 1 # 未运行
    fi
}

# 守护进程
watchdog() {
    echo "🔍 正在检查同步服务状态... $(date)"
    local restarted=0
    local log_file="$HOME/watchdog.log"
    
    # 确保日志文件存在
    touch "$log_file"

    # 1. 检查照片同步服务
    if ! check_service_status "照片同步" "all_in_one.sh.*photo_loop"; then
        echo "❌ 照片同步服务已停止，正在尝试重启..." | tee -a "$log_file"
        
        # 重新导出变量并后台运行
        (
            PHOTO_UPLOAD_TARGET="synology:/download/records/${PHONE_MODEL}_Photos"
            UPLOAD_TARGET="$PHOTO_UPLOAD_TARGET"
            export UPLOAD_TARGET COMPRESSION_QUALITY CAMERA_ID INTERVAL_SECONDS
            photo_loop
        ) &
        
        send_notification "🚨 同步服务异常" "📸 照片同步服务已停止并尝试自动重启" "photo_watchdog"
        restarted=1
    else
        echo "✅ 照片同步服务正常"
    fi

    # 2. 检查录音同步服务
    if ! check_service_status "录音同步" "all_in_one.sh.*record_loop"; then
        echo "❌ 录音同步服务已停止，正在尝试重启..." | tee -a "$log_file"
        
        # 重新导出变量并后台运行
        (
            RECORD_UPLOAD_TARGET="synology:/download/records/${PHONE_MODEL}"
            UPLOAD_TARGET="$RECORD_UPLOAD_TARGET"
            export UPLOAD_TARGET AUDIO_DURATION
            record_loop
        ) &
        
        send_notification "🚨 同步服务异常" "🎙️ 录音同步服务已停止并尝试自动重启" "record_watchdog"
        restarted=1
    else
        echo "✅ 录音同步服务正常"
    fi

    if [ $restarted -eq 1 ]; then
        echo "✅ Watchdog 处理完成。有服务被重启。" | tee -a "$log_file"
    else
        echo "✅ Watchdog 检查完成。所有服务运行正常。"
    fi
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
        (crontab -l 2>/dev/null | grep -v "$HOME/all_in_one.sh"; echo "@reboot $HOME/all_in_one.sh start"; echo "*/10 * * * * $HOME/all_in_one.sh watchdog") | crontab -
        echo "✅ 定时任务已设置：重启自动启动服务，且每10分钟进行一次健康检查 (Watchdog)"
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
    echo "📂 NAS 音频接收目录: synology:/download/records/${PHONE_MODEL}"
    echo ""
    echo "📄 脚本版本信息:"
    echo "  版本号: 1.0.23"
    echo "  最后修改时间: 2026-03-25"
    echo ""
    echo "📌 使用说明:"
    echo "  启动服务: $HOME/all_in_one.sh start"
    echo "  停止服务: $HOME/all_in_one.sh stop"
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
    echo "🚀 启动录音同步服务..."
    
    # 检查是否已安装脚本
    if [ ! -f "$HOME/all_in_one.sh" ]; then
        echo "❌ 错误: 请先运行安装命令: $0 install [手机型号]"
        exit 1
    fi
    
    # 创建日志文件
    touch "$HOME/record_loop.log"
    
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
    
    echo "✅ 服务已启动"
    echo "日志:"
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
        record-log)
            if [ -f "$HOME/record_loop.log" ]; then
                tail -f "$HOME/record_loop.log"
            else
                echo "❌ 录音日志文件不存在"
                exit 1
            fi
            ;;
        watchdog)
            watchdog
            ;;
        help|*)
            show_help
            ;;
    esac
}

# ==================== 程序入口 ====================
main "$@"