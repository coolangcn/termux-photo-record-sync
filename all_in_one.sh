#!/data/data/com.termux/files/usr/bin/bash

# Termux 照片和录音同步到 NAS 一体化脚本
# 作者: coolangcn
# 版本: 1.0.22
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
    
    # 停止照片同步服务
    if pgrep -f "all_in_one.sh.*photo_loop" > /dev/null; then
        pkill -f "all_in_one.sh.*photo_loop"
        echo "📸 照片同步服务已停止"
    else
        echo "📸 照片同步服务未运行"
    fi
    
    if pgrep -f "all_in_one.sh start" > /dev/null; then
        pkill -f "all_in_one.sh start"
        echo "📸 照片同步服务 (all_in_one.sh start) 已停止"
    else
        echo "📸 照片同步服务 (all_in_one.sh start) 未运行"
    fi
    
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
    if pgrep -f "photo_loop.sh" > /dev/null; then
        pkill -f "photo_loop.sh"
        echo "📸 旧照片同步服务已停止"
    else
        echo "📸 旧照片同步服务未运行"
    fi
    
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
        
        # 1. 执行拍照命令（带重试机制）
        RETRY_COUNT=0
        MAX_RETRIES=3
        PHOTO_SUCCESS=false
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$PHOTO_SUCCESS" = false ]; do
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "🔄 拍照尝试 $RETRY_COUNT/$MAX_RETRIES..." | tee -a "$LOG_FILE"
            
            # 清理可能存在的旧临时文件
            rm -f "$TEMP_FILE" 2>/dev/null
            
            # 检查termux-api是否可用
            if ! command -v termux-camera-photo &> /dev/null; then
                echo "❌ termux-camera-photo 命令不存在，请安装 termux-api" | tee -a "$LOG_FILE"
                break
            fi
            
            # 执行拍照命令（保留错误输出以便调试）
            echo "📸 使用相机ID: $CAMERA_ID 拍照到: $TEMP_FILE" | tee -a "$LOG_FILE"
            PHOTO_OUTPUT=$(termux-camera-photo -c "$CAMERA_ID" "$TEMP_FILE" 2>&1)
            PHOTO_STATUS=$?
            
            echo "📊 拍照命令返回状态码: $PHOTO_STATUS" | tee -a "$LOG_FILE"
            if [ -n "$PHOTO_OUTPUT" ]; then
                echo "📋 拍照命令输出: $PHOTO_OUTPUT" | tee -a "$LOG_FILE"
            fi
            
            # 列出目录内容查看文件状态
            echo "📁 目录内容:" | tee -a "$LOG_FILE"
            ls -la "$RECORD_DIR" | grep -E "(CameraPhoto|$TIMESTAMP)" | tee -a "$LOG_FILE" || echo "(无匹配文件)" | tee -a "$LOG_FILE"
            
            # 等待文件写入完成（增加等待时间）
            sleep 5
            
            # 再次检查文件
            echo "🔍 检查文件: $TEMP_FILE" | tee -a "$LOG_FILE"
            if [ -e "$TEMP_FILE" ]; then
                if [ -s "$TEMP_FILE" ]; then
                    FILE_SIZE=$(stat -c%s "$TEMP_FILE" 2>/dev/null || echo "0")
                    echo "✅ 照片文件已生成，大小: $FILE_SIZE 字节" | tee -a "$LOG_FILE"
                    PHOTO_SUCCESS=true
                else
                    echo "⚠️ 文件存在但为空 (大小为0)" | tee -a "$LOG_FILE"
                fi
            else
                echo "⚠️ 文件不存在: $TEMP_FILE" | tee -a "$LOG_FILE"
            fi
            
            if [ "$PHOTO_SUCCESS" = false ]; then
                echo "⏱️ 等待后重试..." | tee -a "$LOG_FILE"
                sleep 3
            fi
        done
        
        if [ "$PHOTO_SUCCESS" = false ]; then
            echo "❌ 拍照失败，已达到最大重试次数 $(date)" | tee -a "$LOG_FILE"
            rm -f "$TEMP_FILE" 2>/dev/null
            # 检查termux-api权限
            echo "🔧 请检查:" | tee -a "$LOG_FILE"
            echo "   1. Termux:API 应用是否已安装" | tee -a "$LOG_FILE"
            echo "   2. 相机权限是否已授予 Termux" | tee -a "$LOG_FILE"
            echo "   3. 相机是否被其他应用占用" | tee -a "$LOG_FILE"
            sleep 30
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
        
        # 3. 移动和上传逻辑（按日期文件夹存放）
        CURRENT_DATE=$(date +%Y-%m-%d)
        DATE_TARGET="$UPLOAD_TARGET/$CURRENT_DATE"
        echo "📤 移动照片至 NAS: $DATE_TARGET/$(basename "$FILE")" | tee -a "$LOG_FILE"
        
        rclone_log_output=$(rclone move "$FILE" "$DATE_TARGET" --ignore-errors --retries 3 --low-level-retries 1 --quiet 2>&1)
        RCLONE_STATUS=$?
        
        if [ $RCLONE_STATUS -eq 0 ]; then
            echo "✅ 移动成功 (照片已上传至 $DATE_TARGET) $(date)" | tee -a "$LOG_FILE"
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
    echo "📂 NAS 照片接收目录: synology:/download/records/${PHONE_MODEL}_Photos"
    echo "📂 NAS 音频接收目录: synology:/download/records/${PHONE_MODEL}"
    echo ""
    echo "📄 脚本版本信息:"
    echo "  版本号: 1.0.19"
    echo "  最后修改时间: 2025-11-16"
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