# Pi4 Dual Display Setup

Настройка Raspberry Pi 4 с двумя дисплеями: **DSI 4.3" (Waveshare реплика)** + **HDMI**.

Wayland (labwc), расширенный рабочий стол с отдельной панелью на каждом экране.

![Pi4 DSI + HDMI](https://img.shields.io/badge/pi-4-ff0000) ![Wayland](https://img.shields.io/badge/wayland-labwc-green) ![Dual Display](https://img.shields.io/badge/displays-DSI%20%2B%20HDMI-blue)

## Стек

| Компонент | Детали |
|-----------|--------|
| **Pi** | Raspberry Pi 4 (8GB), Debian 13 (trixie) |
| **Дисплей DSI** | 4.3", 800x480, реплика Waveshare DSI |
| **Дисплей HDMI** | LG TV, 1360x768 (через HDMI-A-2) |
| **Композитор** | labwc (Wayland) — **только rpi-версия 0.9.2+** |
| **Панель** | wf-panel-pi |

## Результат

- **Расширенный рабочий стол**: DSI слева, HDMI справа
- **Панель на каждом экране**: отдельный экземпляр wf-panel-pi на каждый дисплей
- **Зеркалирование**: опционально через `wl-mirror`
- **Bluetooth audio**: автоматическое переключение панелей при подключении BT-колонки

## Конфигурация

### Названия выходов (Pi4)

```
DSI-1       — DSI дисплей (4.3", 800x480)
HDMI-A-1    — первый HDMI (обычно не подключён)
HDMI-A-2    — второй HDMI (LG TV, 1360x768)
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

Создаётся автоматически через panel-watchdog.

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

**Проблема:** wf-panel-pi с жёстким `monitor=` не реагирует на горячее подключение HDMI.

**Решение:** демон `panel-watchdog.sh`, который следит за подключением/отключением дисплеев и перезапускает панели на лету.

Файл: `scripts/panel-watchdog.sh`. Путь назначения: `~/.local/bin/panel-watchdog.sh`

```bash
mkdir -p ~/.local/bin
cp scripts/panel-watchdog.sh ~/.local/bin/
chmod +x ~/.local/bin/panel-watchdog.sh
```

### 4. Autostart labwc — системный

Файл: `/etc/xdg/labwc/autostart` — заменён `wf-panel-pi` на `panel-watchdog.sh`:

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

### 6. Bluetooth Audio + systemd-path

При подключении BT-колонки `bt-combine.sh` создаёт combine-sink для программной регулировки громкости и сбрасывает панели через systemd path-unit.

**Установка systemd units:**

```bash
mkdir -p ~/.config/systemd/user
cp configs/systemd/bt-audio.path ~/.config/systemd/user/
cp configs/systemd/bt-audio.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now bt-audio.path
```

**Установка скриптов:**

```bash
cp scripts/bt-combine.sh ~/.local/bin/
cp scripts/bt-panel-restart.sh ~/.local/bin/
chmod +x ~/.local/bin/bt-combine.sh ~/.local/bin/bt-panel-restart.sh
```

**Как работает:**
- `bt-combine.sh` создаёт combined-sink при подключении BT-аудио и создаёт файл `/tmp/bt-sink-trigger`
- `bt-audio.path` (systemd path-unit) отслеживает изменения этого файла
- `bt-audio.service` запускает `bt-panel-restart.sh`, который перезапускает панели для обновления списка аудиовыходов

### 7. Зеркалирование (опционально)

```bash
sudo apt install wl-mirror
```

Скрипт переключения: `~/.local/bin/toggle-mirror.sh`

## Установка labwc (важно!)

**Используйте ТОЛЬКО версию из rpi-репозитория!** Debian-версия (0.8.3) некорректно работает с DSI-дисплеем.

```bash
# Установить из rpi-репа
sudo apt install labwc=0.9.2-1+rpt4

# Закрепить версию (чтобы не откатилась)
sudo tee /etc/apt/preferences.d/pin-labwc-stable << 'EOF'
Package: labwc
Pin: version 0.9.2-1+rpt4
Pin-Priority: 1001
EOF
```

## Установка (с нуля)

```bash
# 1. labwc (rpi-версия)
sudo apt install labwc=0.9.2-1+rpt4

# 2. Конфиг панели для DSI
mkdir -p ~/.config/wfpanel
cp configs/wfpanel/wfpanel-dsi.ini ~/.config/wfpanel/

# 3. Установить panel-watchdog
mkdir -p ~/.local/bin
cp scripts/panel-watchdog.sh ~/.local/bin/
chmod +x ~/.local/bin/panel-watchdog.sh

# 4. Исправить системный autostart
sudo sed -i 's|/usr/bin/wf-panel-pi|/home/pi/.local/bin/panel-watchdog.sh|' \
  /etc/xdg/labwc/autostart

# 5. Очистить пользовательский autostart
mkdir -p ~/.config/labwc
echo '#!/bin/bash' > ~/.config/labwc/autostart
chmod +x ~/.config/labwc/autostart

# 6. Bluetooth audio path-unit
cp configs/systemd/bt-audio.* ~/.config/systemd/user/
cp scripts/bt-combine.sh ~/.local/bin/
cp scripts/bt-panel-restart.sh ~/.local/bin/
systemctl --user daemon-reload
systemctl --user enable --now bt-audio.path

# 7. Всё
sudo reboot
```

## Быстрый старт watchdog (без перезагрузки)

```bash
killall -q wf-panel-pi 2>/dev/null
/home/pi/.local/bin/panel-watchdog.sh &
```

Лог: `cat /tmp/panel-watchdog.log`

## Известные проблемы

### labwc 0.8.3 (Debian) — НЕ использовать
Debian-версия 0.8.3 оставляет zombie-процессы labwc и приводит к чёрному экрану на DSI. Фикс: установить 0.9.2 из rpi-репозитория (см. выше).

### bt-volume-check.timer (устарел)
Старый timer на 30 секунд убивал панели каждые полминуты. Заменён на systemd path-unit, который срабатывает только при реальном подключении BT.

### Разные разрешения
DSI (800x480) и HDMI (1360x768) — зеркалирование только в режиме 800x480.

## Диагностика

```bash
# Список дисплеев
wlr-randr

# Статус подключения
cat /sys/class/drm/card1-DSI-1/status
cat /sys/class/drm/card1-HDMI-A-2/status

# Панели
pgrep -a wf-panel-pi

# BT path-unit
systemctl --user status bt-audio.path
systemctl --user status bt-audio.service

# Включить/выключить зеркало
wl-mirror --fullscreen DSI-1 &
pkill wl-mirror
```

## Файлы в репозитории

```
scripts/
├── panel-watchdog.sh      # watchdog панелей (hotplug)
├── bt-combine.sh           # BT combine-sink + триггер
├── bt-panel-restart.sh     # перезапуск панелей при BT
└── toggle-backlight.sh     # переключение подсветки DSI

configs/
├── wfpanel/
│   ├── wfpanel.ini         # панель HDMI
│   └── wfpanel-dsi.ini     # панель DSI
├── labwc/
│   ├── autostart-user      # пользовательский autostart
│   └── autostart-system    # системный autostart
├── systemd/
│   ├── bt-audio.path       # path-unit для BT-триггера
│   └── bt-audio.service    # сервис перезапуска панелей
└── apt/
    └── README.md           # документация по pinning labwc
```

## Лицензия

MIT — делайте что хотите.
