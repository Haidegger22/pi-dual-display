#!/bin/bash
# panel-watchdog.sh — держит панель wf-panel-pi живой (Wayland/labwc)
# v8.3 — 2026-11-21: убран горячий цикл перезапуска панели.
#
# Что было не так в v8.2:
#   * панель 1.43 — GApplication-unique. Сторож звал /usr/bin/wf-panel-pi КАЖДУЮ
#     итерацию, даже когда панель уже работала: новый экземпляр мгновенно выходил
#     с кодом 0 -> в логе «перезапущен (exit=0)» каждые 1.5 с;
#   * вместе с панелью этот цикл каждые ~9 с рестартил nvme-temp-tray
#     (`sleep 8; systemctl restart ...` внутри цикла) -> значок температуры
#     мигал: пропадал и появлялся, цифра то есть, то нет;
#   * сторож стартовал дважды (строка была и в /etc/xdg/labwc/autostart,
#     и в ~/.config/labwc/autostart), pid-файл не спасал от гонки старта —
#     два цикла множили рестарты.
#
# Что теперь:
#   * единственный экземпляр через flock (гонок нет);
#   * панель запускается ТОЛЬКО если её нет; если жива — просто ждём;
#   * виджет NVMe перезапускается один раз и только после фактического
#     старта панели (панель, стартовавшая позже виджета, SNI-итем не подхватывает);
#   * если панель вышла сразу — пауза 10 с вместо горячего цикла.

CONFIG_DIR=/home/pi/.config/wf-panel-pi
CONFIG_FILE="$CONFIG_DIR/wf-panel-pi.ini"
LOG_FILE=/tmp/panel-watchdog.log
LOCK_FILE=/tmp/panel-watchdog.lock
WIDGET_UNIT=nvme-temp-tray.service
PANEL=/usr/bin/wf-panel-pi

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }
# Вывод панели больше не выбрасываем: без него не видно, почему она теряет
# значок трея. Файл ротируется по размеру, чтобы не рос бесконечно.
PANEL_LOG=/tmp/panel.log
panel_log() {
    if [ -f "$PANEL_LOG" ] && [ "$(stat -c %s "$PANEL_LOG")" -gt 512000 ]; then
        mv -f "$PANEL_LOG" "$PANEL_LOG.1"
    fi
}

# один сторож на сессию: второй экземпляр молча выходит
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/run/user/1000

panel_alive() { pgrep -x wf-panel-pi >/dev/null 2>&1; }

widget_ensure() {
    # Не перезапускаем работающий виджет — только поднимаем, если он лёг.
    if systemctl --user is-active --quiet "$WIDGET_UNIT"; then
        return
    fi
    systemctl --user reset-failed "$WIDGET_UNIT" >/dev/null 2>&1
    systemctl --user start "$WIDGET_UNIT" >/dev/null 2>&1
}

log "=== watchdog PID $$ (v8.3) ==="

# ждём Wayland (до 15 с)
for _ in $(seq 1 15); do
    [ -e /run/user/1000/wayland-0 ] && break
    sleep 1
done

# Конфиг панели настраивается руками (отступы меню, порядок виджетов) —
# генерируем только если файла ещё нет.
if [ ! -f "$CONFIG_FILE" ]; then
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << 'EOF'
[panel]
monitor=DSI-1
position=top
height=36
icon_size=32
widgets_left=smenu spacing0 spacing4 launchers spacing8 window-list
widgets_right=power ejecter spacing2 connect spacing2 bluetooth spacing2 netman spacing2 volumepulse spacing2 clock spacing2 tray spacing2 cputemp spacing2 batt
EOF
    log "  конфиг создан заново ($CONFIG_FILE)"
fi

# Панель уже поднята (например, сторож перезапустили руками) — виджет проверить.
if panel_alive; then
    log "  панель уже работает (pid $(pgrep -x wf-panel-pi | head -1))"
    widget_ensure
fi

while true; do
    if panel_alive; then
        sleep 5
        continue
    fi

    log "  панели нет — запуск"
    started=$(date +%s)
    panel_log
    "$PANEL" >> "$PANEL_LOG" 2>&1 &
    sleep 8

    if panel_alive; then
        # панель стартовала ПОЗЖЕ виджета -> SNI-значок иначе не появится
        systemctl --user restart "$WIDGET_UNIT" > /dev/null 2>&1
        log "  панель поднялась (за $(( $(date +%s) - started )) с), виджет перезапущен"
        while panel_alive; do
            sleep 5
        done
        log "  панель исчезла — перезапуск"
    else
        # панель вышла сразу: не крутим горячий цикл
        log "  панель не удержалась, пауза 10 с"
        sleep 10
    fi
done
