#!/bin/bash
# ScriptsBacup.v1.6.2.sh — WordPress site and DB backup
# Author: GitKitNet
# Version: 1.6.2 (Telegram + Logging + Rotation)

### 🔔 Telegram Notification Function
function SendTelegram() {
    local MESSAGE=$1
    local BOT_API="764154****************************************"
    local CHAT_ID="-100**********"
    local API_URL="https://api.telegram.org/bot${BOT_API}/sendMessage"

    curl -s -X POST "$API_URL" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${MESSAGE}" \
        -d "parse_mode=HTML" > /dev/null
}

### 📦 Backup One or More WordPress Sites
function ScriptsBacup() {
    if [ $# -eq 0 ]; then
        read -p "Enter directories/files to backup (space-separated): " INPUT
        set -- $INPUT
    fi

    local DATE=$(date +%Y%m%d_%H%M)

    for ITEM in "$@"; do
        if [ ! -e "$ITEM" ]; then
            echo "❌ Error: '$ITEM' does not exist." >&2
            SendTelegram "❌ <b>ERROR</b>: path <b>'$ITEM'</b> does not exist."
            continue
        fi

        local ABS_PATH=$(realpath "$ITEM")
        local SITE_DIR=$(dirname "$ABS_PATH")
        local BACKUP_PARENT=$(dirname "$SITE_DIR")
        local BACKUP_DIR="${BACKUP_PARENT}/backups"
        local LOG_FILE="${BACKUP_DIR}/backup.log"

        mkdir -p "$BACKUP_DIR"

        local RAW_NAME=$(basename "$ITEM")
        local SANITIZED_NAME=$(echo "$RAW_NAME" | sed 's/\./_/g')
        local ARCHIVE_NAME="${SANITIZED_NAME}_${DATE}.tar.gz"
        local OUTPUT_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

        echo "🔄 $(date '+%Y-%m-%d %H:%M:%S') — Archiving '$ITEM'" | tee -a "$LOG_FILE"
        tar czf "$OUTPUT_PATH" "$ITEM"
        echo "✅ Archive created: $OUTPUT_PATH" | tee -a "$LOG_FILE"

        local CONFIG_PATH="$ITEM/wp-config.php"
        if [ -f "$CONFIG_PATH" ]; then
            echo "🔍 Found wp-config.php — parsing DB credentials..." | tee -a "$LOG_FILE"

            local DB_NAME=$(grep DB_NAME "$CONFIG_PATH" | cut -d \' -f 4)
            local DB_USER=$(grep DB_USER "$CONFIG_PATH" | cut -d \' -f 4)
            local DB_PASS=$(grep DB_PASSWORD "$CONFIG_PATH" | cut -d \' -f 4)
            local DB_HOST=$(grep DB_HOST "$CONFIG_PATH" | cut -d \' -f 4)

            local SQL_FILE="${BACKUP_DIR}/${SANITIZED_NAME}_${DATE}.sql.gz"

            echo "💾 Dumping DB '${DB_NAME}'..." | tee -a "$LOG_FILE"
            mysqldump -h "$DB_HOST" -u "$DB_USER" -p"${DB_PASS}" "$DB_NAME" | gzip > "$SQL_FILE"

            if [ $? -eq 0 ]; then
                echo "✅ DB dump created: $SQL_FILE" | tee -a "$LOG_FILE"
                SendTelegram "✅ <b>${RAW_NAME}</b>: backup OK at <code>$(date '+%H:%M %d-%m-%Y')</code>"
            else
                echo "❌ Error creating DB dump for $DB_NAME" | tee -a "$LOG_FILE"
                SendTelegram "❌ <b>${RAW_NAME}</b>: error dumping <b>${DB_NAME}</b> at <code>$(date '+%H:%M %d-%m-%Y')</code>"
            fi
        else
            echo "ℹ️  No wp-config.php found in '$ITEM' — skipping DB dump." | tee -a "$LOG_FILE"
            SendTelegram "⚠️ <b>${RAW_NAME}</b>: archive only (no wp-config.php)"

        fi

        # ♻️ Очищення старих архівів (залишити лише 5 останніх)
        echo "🧹 Cleaning old backups..." | tee -a "$LOG_FILE"
        ls -1t "${BACKUP_DIR}/${SANITIZED_NAME}_"*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
        ls -1t "${BACKUP_DIR}/${SANITIZED_NAME}_"*.sql.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
    done
}


# Массовый бекап: принимает пути или шаблоны вида /var/www/*/data/www/*
function ScriptsBacupAll() {
    if [ $# -eq 0 ]; then
        echo "❗ Usage: ScriptsBacupAll /var/www/*/data/www/* or ~/www/*"
        return 1
    fi

    local DATE=$(date +%Y%m%d_%H%M)
    local TOTAL=0
    local SKIPPED=0

    SendTelegram "🚀 <b>Mass backup started</b> at <code>${DATE}</code>"

    for PATTERN in "$@"; do
        for DOMAIN_PATH in $PATTERN; do
            if [ -d "$DOMAIN_PATH" ]; then
                local SITE_NAME=$(basename "$DOMAIN_PATH")
                if [ -f "$DOMAIN_PATH/wp-config.php" ]; then
                    echo "📦 Backing up: $SITE_NAME"
                    ScriptsBacup "$DOMAIN_PATH"
                    ((TOTAL++))
                else
                    echo "⏭ Skipped: $SITE_NAME (no wp-config.php)"
                    ((SKIPPED++))
                fi
            fi
        done
    done

    local END_TIME=$(date '+%H:%M %d-%m-%Y')
    SendTelegram "✅ <b>Mass backup finished</b> at <code>${END_TIME}</code>\n🔹 Success: <b>${TOTAL}</b>\n🔸 Skipped: <b>${SKIPPED}</b>"
}

# Массовый бекап для FastPanel с таймером и подтверждением
function ScriptsBacupAllPanel() {
    local BACKUP_PANEL="/var/www/*/data/www/*"
    local TIMER=15
    local CONFIRM=""

    echo -en "\nЧерез ${TIMER} секунд будет выполнен бекап всех сайтов в FastPanel.\n\n"

    for ((i=TIMER; i>0; i--)); do
        echo -ne "\r\tДля отмены Нажмите [Ctrl+C / Nn / 0]. Осталось:\t ${i} секунд ..."
        read -t 1 -n 1 CONFIRM
        if [[ "$CONFIRM" =~ ^[Nn0]$ ]]; then
            echo -e "\n❌ Отменено пользователем. Бекап не выполнен."
            return 0
        fi
    done

    echo -e "\n⏳ Запуск бекапа..."
    ScriptsBacupAll ${BACKUP_PANEL}
    echo -e "\n✅ Завершение бекапа."
}
