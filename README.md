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

### 3. Autostart labwc — системный

Файл: `/etc/xdg/labwc/autostart` — **отредактирован** (убраны `lwrespawn`):

```bash
/usr/bin/pcmanfm-pi &
/usr/bin/wf-panel-pi &
/usr/bin/kanshi &
/usr/bin/lxsession-xdg-autostart
```

> `lwrespawn` убран, т.к. его `pgrep` неверно проверяет запущенные процессы (ищет по полному пути вместо имени), что приводит к дублям панелей.

### 4. Autostart labwc — пользовательский (DSI)

Файл: `~/.config/labwc/autostart`

```bash
#!/bin/bash
sleep 4
# Запускаем DSI-панель только если оба дисплея подключены
if wlr-randr 2>/dev/null | grep -q "DSI-1" && \
   wlr-randr 2>/dev/null | grep -q "HDMI-A-2"; then
  if ! pgrep -f "wf-panel-pi.*wfpanel-dsi" > /dev/null 2>&1; then
    /usr/bin/wf-panel-pi \
      -c /home/pi/.config/wfpanel/wfpanel-dsi.ini &
  fi
fi
```

Защита от дублей: проверка, что DSI-панель ещё не запущена.

### 5. Зеркалирование (опционально)

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
# 1. Создать конфиг основной панели
mkdir -p ~/.config/wfpanel
cat > ~/.config/wfpanel/wfpanel.ini << 'EOF'
[panel]
monitor=HDMI-A-2
position=top
height=36
plugins=menu,spacer,network,bluetooth,volume,clock,powermenu
EOF

# 2. Исправить системный autostart (убрать lwrespawn)
sudo sed -i 's|/usr/bin/lwrespawn /usr/bin/wf-panel-pi|/usr/bin/wf-panel-pi|' \
  /etc/xdg/labwc/autostart
sudo sed -i 's|/usr/bin/lwrespawn /usr/bin/pcmanfm-pi|/usr/bin/pcmanfm-pi|' \
  /etc/xdg/labwc/autostart

# 3. Создать пользовательский autostart для DSI
mkdir -p ~/.config/labwc
cat > ~/.config/labwc/autostart << 'EOF'
#!/bin/bash
sleep 4
if wlr-randr 2>/dev/null | grep -q "DSI-1" && \
   wlr-randr 2>/dev/null | grep -q "HDMI-A-2"; then
  if ! pgrep -f "wf-panel-pi.*wfpanel-dsi" > /dev/null 2>&1; then
    cat > /tmp/wfpanel-dsi.ini << 'INI'
[panel]
monitor=DSI-1
position=top
height=36
plugins=menu,spacer,network,bluetooth,volume,clock,powermenu
INI
    /usr/bin/wf-panel-pi -c /tmp/wfpanel-dsi.ini &
  fi
fi
EOF
chmod +x ~/.config/labwc/autostart

# 4. Установить wl-mirror (опционально)
sudo apt install -y wl-mirror
```

## Известные проблемы

### `lwrespawn` дублирует панели
`lwrespawn` использует `pgrep /usr/bin/wf-panel-pi`, но `pgrep` ищет по имени процесса (первые 15 символов), а не по полному пути.
Проверка не срабатывает → второй экземпляр.

**Решение:** не использовать `lwrespawn`, вызывать `/usr/bin/wf-panel-pi` напрямую.

### DSI определяется не сразу
Панель на DSI стартует с задержкой 4 секунды, чтобы дисплей успел инициализироваться.

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
