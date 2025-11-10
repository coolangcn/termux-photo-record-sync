#!/data/data/com.termux/files/usr/bin/bash


# ========== 配置区 ==========

RECORD_DIR="$HOME/records"

mkdir -p "$RECORD_DIR"


UPLOAD_TARGET="synology:/download/records/Pixel_5"

DURATION=60  # 录音时长 (秒)

LOG_FILE="$HOME/record_loop.log"

PID_FILE="$HOME/record_loop.pid"

# ============================



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
echo "录音时长：${DURATION}s" | tee -a "$LOG_FILE"



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

    echo "⏳ 录音中... 持续 ${DURATION} 秒..." | tee -a "$LOG_FILE"

    sleep "$DURATION"



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



    # 【核心修改】：使用 cd 进入目录，并 rclone move 整个目录中所有符合条件的 (.acc) 文件

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