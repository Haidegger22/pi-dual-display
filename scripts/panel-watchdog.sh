#!/bin/bash
# panel-watchdog.sh — v8: создаёт конфиги для всех дисплеев, держит панели живыми

CONFIG_DIR=/home/pi/.config/wfpanel
LOG_FILE=/tmp/panel-watchdog.log
PID_FILE=/tmp/panel-watchdog.pid

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

log "=== watchdog v8 PID $$ ==="

export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/run/user/1000

for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -e /run/user/1000/wayland-0 ] && break
    sleep 1
done

WIDGETS_LEFT="smenu spacing0 spacing4 launchers spacing8 window-list"
WIDGETS_RIGHT="tray power ejecter spacing2 connect spacing2 bluetooth spacing2 netman spacing2 volumepulse spacing2 clock spacing2 cputemp spacing2 batt"

make_config() {
    local disp="$1" ini="$2"
    cat > "$ini" << EOF
[panel]
monitor=${disp}
position=top
height=36
widgets_left=${WIDGETS_LEFT}
widgets_right=${WIDGETS_RIGHT}
EOF
}

# Запускаем по одной панели на дисплей и держим их в цикле
for disp in $(wlr-randr 2>/dev/null | grep -E "^[A-Z]" | awk '{print $1}'); do
    (
        if [ "$disp" = "DSI-1" ]; then
            ini="$CONFIG_DIR/wfpanel-dsi.ini"
            [ -f "$ini" ] || make_config "$disp" "$ini"
        else
            ini="/tmp/wfpanel-${disp}.ini"
            make_config "$disp" "$ini"
        fi

        log "  сторож $disp запущен"
        while true; do
            /usr/bin/wf-panel-pi -c "$ini" > /dev/null 2>&1
            log "  $disp перезапущен (exit=$?)"
            sleep 1
        done
    ) &
done

log "  все сторожа запущены"
wait