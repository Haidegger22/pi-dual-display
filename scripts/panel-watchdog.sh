#!/bin/bash
# panel-watchdog.sh — держит панели живыми на всех дисплеях
# v8.2 — 2026-11-01: конфиг панели 1.43+ лежит в ~/.config/wf-panel-pi/wf-panel-pi.ini
#   (старый путь ~/.config/wfpanel/wfpanel-<монитор>.ini панель больше НЕ читает)

CONFIG_DIR=/home/pi/.config/wf-panel-pi
CONFIG_FILE="$CONFIG_DIR/wf-panel-pi.ini"
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
# порядок = порядок на панели: трей (в нём значок температуры NVMe) стоит перед cputemp
WIDGETS_RIGHT="power ejecter spacing2 connect spacing2 bluetooth spacing2 netman spacing2 volumepulse spacing2 clock spacing2 tray spacing2 cputemp spacing2 batt"

for disp in $(wlr-randr 2>/dev/null | grep -E "^[A-Z]" | awk '{print $1}'); do
    (
        if [ "$disp" = "DSI-1" ]; then
            ini="$CONFIG_FILE"
            height=36
            icon=32
        else
            ini="/tmp/wf-panel-${disp}.ini"
            height=34
            icon=28
        fi
        # Рабочий конфиг панели настраивается руками (отступы меню, порядок виджетов):
        # если файл есть — не трогаем. Временные конфиги для доп. дисплеев генерируем всегда.
        if [ "$disp" = "DSI-1" ] && [ -f "$ini" ]; then
            log "  $disp: конфиг уже есть, оставляю как настроено ($ini)"
        else
            cat > "$ini" << EOF
[panel]
monitor=${disp}
position=top
height=${height}
icon_size=${icon}
widgets_left=${WIDGETS_LEFT}
widgets_right=${WIDGETS_RIGHT}
EOF
        fi

        log "  сторож $disp (h=$height icon=$icon)"
        while true; do
            # wf-panel-pi 1.43+ не поддерживает флаг -c (панель отвечает
            # «Неизвестный параметр -c» и сразу выходит с кодом 0 -> watchdog
            # крутил бы перезапуск каждую секунду). Конфиг панель берёт сама:
            # ~/.config/wf-panel-pi/wf-panel-pi.ini
            /usr/bin/wf-panel-pi > /dev/null 2>&1
            log "  $disp перезапущен (exit=$?)"
            sleep 1
        done
    ) &
done

log "  запущены"
wait
