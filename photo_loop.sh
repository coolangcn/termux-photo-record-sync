#!/data/data/com.termux/files/usr/bin/bash


# ========== 配置区 ==========

RECORD_DIR="$HOME/records"

mkdir -p "$RECORD_DIR"


UPLOAD_TARGET="" 

CAMERA_ID=1      

INTERVAL_SECONDS=60 

COMPRESSION_QUALITY=60 # 【新增配置】压缩质量 (0-100)，80 是一个较好的平衡点

LOG_FILE="$HOME/photo_loop.log"

PID_FILE="$HOME/photo_loop.pid"

# ============================



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



# 检查 UPLOAD_TARGET 是否已设置

if [ -z "$UPLOAD_TARGET" ]; then

    echo "❌ 错误: UPLOAD_TARGET 未设置，请通过安装脚本运行此脚本" | tee -a "$LOG_FILE"

    exit 1

fi



# 写入当前 PID

echo $$ > "$PID_FILE"

trap 'rm -f "$PID_FILE"; echo "🛑 拍照脚本结束 $(date)" | tee -a "$LOG_FILE"; exit 0' INT TERM EXIT



# --- 启动信息 ---

echo "📸 定时拍照脚本启动 $(date)" | tee -a "$LOG_FILE"
echo "照片目录：$RECORD_DIR" | tee -a "$LOG_FILE"
echo "压缩质量：${COMPRESSION_QUALITY}%" | tee -a "$LOG_FILE" # 新增日志
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

    

    # 2. 【核心优化】：执行压缩

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