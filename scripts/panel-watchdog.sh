#!/bin/bash
# panel-watchdog.sh — создаёт конфиги для всех дисплеев, держит панели живыми
# v8.1 — 2026-05-30: разные размеры для DSI и HDMI

CONFIG_DIR=/home/pi/.config/wfpanel
LOG_FILE=/tmp/panel-watchdog.log
PID_FILE=/tmp/panel-watchdog.pid

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

log "=== watchdog PID $$ ==="

export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/run/user/1000

for i in $(seq 1 15); do
    [ -e /run/user/1000/wayland-0 ] && break
    sleep 1
done

WIDGETS_LEFT="smenu spacing0 spacing4 launchers spacing8 window-list"
WIDGETS_RIGHT="tray power ejecter spacing2 connect spacing2 bluetooth spacing2 netman spacing2 volumepulse spacing2 clock spacing2 cputemp spacing2 batt"

for disp in $(wlr-randr 2>/dev/null | grep -E "^[A-Z]" | awk '{print $1}'); do
    (
        if [ "$disp" = "DSI-1" ]; then
            ini="$CONFIG_DIR/wfpanel-dsi.ini"
            height=36
            icon=32
        else
            ini="/tmp/wfpanel-${disp}.ini"
            height=34
            icon=28
        fi
        cat > "$ini" << EOF
[panel]
monitor=${disp}
position=top
height=${height}
icon_size=${icon}
widgets_left=${WIDGETS_LEFT}
widgets_right=${WIDGETS_RIGHT}
EOF

        log "  сторож $disp (h=$height icon=$icon)"
        while true; do
            /usr/bin/wf-panel-pi -c "$ini" > /dev/null 2>&1
            log "  $disp перезапущен (exit=$?)"
            sleep 1
        done
    ) &
done

log "  запущены"
wait
