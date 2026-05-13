# Pi4 Dual Display Setup

Настройка Raspberry Pi 4 с двумя дисплеями: **DSI 4.3" (Waveshare реплика)** + **HDMI**.

Wayland (labwc), расширенный рабочий стол с отдельной панелью на каждом экране.

![Pi4 DSI + HDMI](https://img.shields.io/badge/pi-4-ff0000) ![Wayland](https://img.shields.io/badge/wayland-labwc-green) ![Dual Display](https://img.shields.io/badge/displays-DSI%20%2B%20HDMI-blue)

## Стек

| Компонент | Детали |
|-----------|--------|
| **Pi** | Raspberry Pi 4 (8GB), Debian 13 (trixie) |
| **Дисплей DSI** | 4.3", 800×480, реплика Waveshare DSI |
| **Дисплей HDMI** | LG TV, 1360×768 (через HDMI-A-2) |
| **Композитор** | labwc (Wayland) |
| **Панель** | wf-panel-pi |

## Результат

- **Расширенный рабочий стол**: DSI слева, HDMI справа
- **Панель на каждом экране**: отдельный экземпляр wf-panel-pi на каждый дисплей
- **Зеркалирование**: опционально через `wl-mirror`

## Конфигурация

### Названия выходов (Pi4)

```
DSI-1       — DSI дисплей (4.3", 800×480)
HDMI-A-1    — первый HDMI (обычно не подключён)
HDMI-A-2    — второй HDMI (LG TV, 1360×768)
```

### 1. Конфиг панели для DSI

Файл: `~/.config/wfpanel/wfpanel-dsi.ini`

```ini
[panel]
monitor=DSI-1
position=top
height=36
plugins=menu,spacer,network,bluetooth,volume,clock,powermenu
```

*Создаётся автоматически через autostart.*

### 2. Конфиг основной панели (HDMI)

Файл: `~/.config/wfpanel/wfpanel.ini`

```ini
[panel]
monitor=HDMI-A-2
position=top
height=36
plugins=menu,spacer,network,bluetooth,volume,clock,powermenu
```

### 3. panel-watchdog — управление панелями (hotplug-ready)

**Проблема:** wf-panel-pi с жёстким `monitor=` не реагирует на горячее подключение HDMI. Если дисплей не был подключён на момент старта сессии — панель на нём не появляется.

**Решение:** демон `panel-watchdog.sh`, который следит за подключением/отключением дисплеев и перезапускает панели на лету.

Файл: `scripts/panel-watchdog.sh` (в этом репозитории). Путь назначения: `~/.local/bin/panel-watchdog.sh`

```bash
# Установка
mkdir -p ~/.local/bin
cp scripts/panel-watchdog.sh ~/.local/bin/
chmod +x ~/.local/bin/panel-watchdog.sh
```

**Как работает:**
- При старте запускает wf-panel-pi на **всех** подключённых дисплеях
- Мониторит изменения через `inotifywait` на `/sys/class/drm/*/status`
- Дублирует через `udevadm monitor` для надёжности
- При любом изменении (hotplug HDMI) убивает старые панели и запускает новые
- Для DSI-1 использует `wfpanel-dsi.ini`, для HDMI-дисплеев динамически создаёт конфиг

> `lwrespawn` убран, т.к. его `pgrep` ищет по полному пути вместо имени процесса, что приводит к дублям панелей.

### 4. Autostart labwc — системный

Файл: `/etc/xdg/labwc/autostart` — **заменён** `wf-panel-pi` на `panel-watchdog.sh`:

```bash
/usr/bin/pcmanfm-pi &
/home/pi/.local/bin/panel-watchdog.sh &
/usr/bin/kanshi &
/usr/bin/lxsession-xdg-autostart
```

### 5. Autostart labwc — пользовательский

Файл: `~/.config/labwc/autostart` — очищен (всё управление панелями через watchdog):

```bash
#!/bin/bash
# user autostart — всё управление панелями через panel-watchdog.sh
```

### 6. Зеркалирование (опционально)

Установка: `sudo apt install wl-mirror`

Скрипт переключения: `~/.local/bin/toggle-mirror`

```bash
#!/bin/bash
PID_FILE="/tmp/wl-mirror.pid"
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
  kill $(cat "$PID_FILE") 2>/dev/null
  rm -f "$PID_FILE"
  notify-send "Зеркало выключено"
else
  wl-mirror --fullscreen --no-show-cursor DSI-1 &
  echo $! > "$PID_FILE"
  notify-send "Зеркало включено"
fi
```

## Установка (с нуля)

```bash
# 1. Создать конфиг панели для DSI
mkdir -p ~/.config/wfpanel
cat > ~/.config/wfpanel/wfpanel-dsi.ini << 'EOF'
[panel]
monitor=DSI-1
position=top
height=36
plugins=menu,spacer,network,bluetooth,volume,clock,powermenu
EOF

# 2. Установить panel-watchdog
mkdir -p ~/.local/bin
cp scripts/panel-watchdog.sh ~/.local/bin/
chmod +x ~/.local/bin/panel-watchdog.sh

# 3. Исправить системный autostart (заменить wf-panel-pi на watchdog)
sudo sed -i 's|/usr/bin/wf-panel-pi|/home/pi/.local/bin/panel-watchdog.sh|' \
  /etc/xdg/labwc/autostart

# 4. Очистить пользовательский autostart (если был)
mkdir -p ~/.config/labwc
echo '#!/bin/bash' > ~/.config/labwc/autostart
chmod +x ~/.config/labwc/autostart

# 5. Установить wl-mirror (опционально)
sudo apt install -y wl-mirror
```

## Быстрый старт watchdog (без перезагрузки)

```bash
killall -q wf-panel-pi 2>/dev/null
/home/pi/.local/bin/panel-watchdog.sh &
```

Лог: `cat /tmp/panel-watchdog.log`

## Известные проблемы

### Разные разрешения
DSI (800×480) и HDMI (1360×768) — зеркалирование возможно только в режиме 800×480 (HDMI переключается принудительно через `cvt` + `xrandr`, или в Wayland через `wl-mirror`).

## Диагностика

```bash
# Список дисплеев
wlr-randr

# Статус подключения
cat /sys/class/drm/card1-DSI-1/status
cat /sys/class/drm/card1-HDMI-A-2/status

# Панели
pgrep -a wf-panel-pi

# Включить/выключить зеркало
wl-mirror --fullscreen DSI-1 &
pkill wl-mirror
```

## Лицензия

MIT — делайте что хотите.
