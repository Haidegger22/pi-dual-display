#!/bin/bash
# panel-watchdog.sh — следит за подключением дисплеев и перезапускает панели
# Запускается из autostart labwc

CONFIG_DIR=/home/pi/.config/wfpanel
LOG_FILE=/tmp/panel-watchdog.log

log() {
    echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"
}

restart_panels() {
    local cause="$1"

    local displays
    displays=$(wlr-randr 2>/dev/null | grep -E "^[A-Z]" | awk '{print $1}')

    log "===== restart ($cause) — дисплеи: $displays ====="

    # Убиваем старые панели по PID (быстрее pkill)
    for pid in $(pgrep -f "wf-panel-pi" 2>/dev/null); do
        kill "$pid" 2>/dev/null
    done
    sleep 0.3

    for disp in $displays; do
        local ini
        if [ "$disp" = "DSI-1" ]; then
            ini="$CONFIG_DIR/wfpanel-dsi.ini"
        else
            ini="/tmp/wfpanel-${disp}.ini"
            cat > "$ini" << EOF
[panel]
monitor=${disp}
position=top
height=36
plugins=menu,spacer,network,bluetooth,volume,clock,powermenu
EOF
        fi

        if [ -f "$ini" ]; then
            /usr/bin/wf-panel-pi -c "$ini" &
            log "  → $disp ($ini)"
        fi
    done
}

# === Мониторинг: inotify + udev ===
watch_displays() {
    log "=== watchdog запущен ==="

    # inotify: следим за статусными файлами DRM
    while true; do
        inotifywait -q -e modify \
            /sys/class/drm/card1-DSI-1/status \
            /sys/class/drm/card1-HDMI-A-2/status \
            /sys/class/drm/card1-HDMI-A-1/status 2>/dev/null
        sleep 0.5
        restart_panels "inotify"
    done &

    # udev: дополнительный канал
    udevadm monitor --subsystem-match=drm --property --udev 2>/dev/null | \
    while IFS= read -r line; do
        if echo "$line" | grep -qiE "(change|bind|unbind|connected|disconnected)"; then
            sleep 0.5
            restart_panels "udev"
        fi
    done &

    wait
}

# === Первичный запуск ===
restart_panels "startup"

# Запускаем мониторинг
watch_displays
