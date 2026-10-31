# Pi4 Dual Display Setup

Настройка Raspberry Pi 4 с двумя дисплеями: **DSI 4.3"** + **HDMI**.

Wayland (labwc), расширенный рабочий стол с отдельной панелью на каждом экране.

## Стек

- **Pi:** Raspberry Pi 4 (8GB), Debian 13 (trixie)
- **DSI:** 4.3", 800x480, реплика Waveshare DSI
- **HDMI:** LG TV, 1360x768 (HDMI-A-2)
- **Композитор:** labwc **0.9.2+** (только rpi-сборка)
- **Панель:** wf-panel-pi + panel-watchdog.sh

## Названия выходов

```
DSI-1       — DSI дисплей (4.3", 800x480)
HDMI-A-1    — не используется
HDMI-A-2    — LG TV (1360x768)
```

## Конфигурация

### 1. labwc

**Важно:** использовать только rpi-версию labwc! Debian-версия 0.8.3 выдаёт чёрный экран на DSI.

```bash
sudo apt install labwc=0.9.2-1+rpt4
```

Закрепить версию (чтобы не откатилась):

```ini
# /etc/apt/preferences.d/pin-labwc-stable
Package: labwc
Pin: version 0.9.2-1+rpt4
Pin-Priority: 1001
```

### 2. panel-watchdog

Демон, который следит за дисплеями и запускает панель на каждом.

```bash
cp scripts/panel-watchdog.sh ~/.local/bin/
chmod +x ~/.local/bin/panel-watchdog.sh
```

Системный autostart (`/etc/xdg/labwc/autostart`):

```bash
/usr/bin/pcmanfm-pi &
/home/pi/.local/bin/panel-watchdog.sh &
/usr/bin/kanshi &
/usr/bin/lxsession-xdg-autostart
```

### 3. Конфиг панели

С версии wf-panel-pi **1.43** панель читает единственный файл `~/.config/wf-panel-pi/wf-panel-pi.ini`
(старый путь `~/.config/wfpanel/wfpanel-<монитор>.ini` больше не используется).

```bash
mkdir -p ~/.config/wf-panel-pi
cp configs/wf-panel-pi/wf-panel-pi.ini ~/.config/wf-panel-pi/wf-panel-pi.ini
```

### 4. Управление громкостью (BT + HDMI)

Хоткеи labwc (`configs/labwc/rc.xml`):

| Клавиша | Действие |
|---------|----------|
| `Shift+F5` | Громче (+5%) |
| `Shift+F4` | Тише (-5%) |
| `Shift+F3` | Mute |

Работают через `@DEFAULT_SINK@` — переключаются между HDMI и BT автоматически.

### 5. Bluetooth audio

При подключении BT-колонки автоматически создаётся combined-sink и перезапускаются панели:

```bash
cp scripts/bt-combine.sh ~/.local/bin/
cp scripts/bt-panel-restart.sh ~/.local/bin/
chmod +x ~/.local/bin/bt-combine.sh ~/.local/bin/bt-panel-restart.sh

cp configs/systemd/bt-audio.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now bt-audio.path
```

Подробнее: [pi4-audio-volume-fix](https://github.com/Haidegger22/pi4-audio-volume-fix)

### 6. Подсветка DSI

```bash
cp scripts/toggle-backlight.sh ~/.local/bin/
chmod +x ~/.local/bin/toggle-backlight.sh
# Хоткей: Shift+F8 (уже в rc.xml)
```

## Установка с нуля

```bash
# 1. labwc (rpi)
sudo apt install labwc=0.9.2-1+rpt4

# 2. Конфиг панели (1.43+)
mkdir -p ~/.config/wf-panel-pi
cp configs/wf-panel-pi/wf-panel-pi.ini ~/.config/wf-panel-pi/wf-panel-pi.ini

# 3. watchdog
mkdir -p ~/.local/bin
cp scripts/panel-watchdog.sh ~/.local/bin/
chmod +x ~/.local/bin/panel-watchdog.sh

# 4. Системный autostart
sudo cp configs/labwc/autostart-system /etc/xdg/labwc/autostart

# 5. Пользовательский autostart
cp configs/labwc/autostart-user ~/.config/labwc/autostart

# 6. Хоткеи
cp configs/labwc/rc.xml ~/.config/labwc/rc.xml

# 7. BT audio
cp scripts/bt-combine.sh ~/.local/bin/
cp scripts/bt-panel-restart.sh ~/.local/bin/
chmod +x ~/.local/bin/bt-combine.sh ~/.local/bin/bt-panel-restart.sh
cp configs/systemd/bt-audio.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now bt-audio.path

# 8. Перезагрузка
sudo reboot
```

## Диагностика

```bash
# Дисплеи
wlr-randr
cat /sys/class/drm/card1-DSI-1/status
cat /sys/class/drm/card1-HDMI-A-2/status

# Панели
pgrep -a wf-panel-pi
tail -f /tmp/panel-watchdog.log

# Аудио
pactl get-default-sink
pactl list sinks short

# labwc
labwc --version
```

## Файлы репозитория

```
scripts/
├── panel-watchdog.sh       # watchdog панелей (hotplug)
├── bt-combine.sh            # BT combine-sink + триггер
├── bt-panel-restart.sh      # перезапуск панелей при BT
└── toggle-backlight.sh      # подсветка DSI

configs/
├── wf-panel-pi/
│   └── wf-panel-pi.ini      # рабочий конфиг панели (1.43+)
├── wfpanel-obsolete/
│   ├── wfpanel.ini          # старый путь (панель <1.43, больше не читается)
│   └── wfpanel-dsi.ini
├── labwc/
│   ├── rc.xml               # хоткеи
│   ├── autostart-system     # системный autostart
│   └── autostart-user       # пользовательский
├── systemd/
│   ├── bt-audio.path        # path-unit
│   └── bt-audio.service     # сервис
└── apt/
    └── README.md            # pinning labwc
```

## Устранение проблем

**Чёрный экран на DSI после обновления labwc** — проверьте версию:
```bash
labwc --version  # должно быть 0.9.2+
```

**Панели перезапускаются каждые 30с** — удалите старый timer:
```bash
systemctl --user disable --now bt-volume-check.timer
```

**Не регулируется громкость BT** — проверьте default sink:
```bash
pactl get-default-sink  # должно быть bluez_output...
```

## Ссылки

- pi4-audio-volume-fix: https://github.com/Haidegger22/pi4-audio-volume-fix

---

## ⚠️ Важно: ядро 6.18+ требует KMS

После обновления ядра до **6.18.29+rpt-rpi-v8** драйвер `vc4-fkms-v3d` перестал видеть второй HDMI-порт (HDMI-A-2).

**Решение:** переключиться на `vc4-kms-v3d` (полный KMS):

```ini
# /boot/firmware/config.txt
dtoverlay=vc4-kms-v3d
```

С полным KMS оба порта (HDMI-A-1, HDMI-A-2) и DSI работают корректно, EDID читается, монитор определяется автоматически.

`hdmi_force_hotplug` **не нужен** с полным KMS — монитор детектится сам.

## Исправления 2026-05-30

| Что | Было | Стало |
|-----|------|-------|
| Драйвер | `vc4-fkms-v3d` | `vc4-kms-v3d` |
| Порт для TV | HDMI-A-2 не появлялся | HDMI-A-2 работает |
| Разрешение TV | 640×480 (фейк) | 1360×768 (EDID) |
| Панель HDMI | 36px / без иконок | 34px / иконки 28px |
| Панель DSI | 36px / без иконок | 36px / иконки 32px |
| cmdline.txt | с video=... | чистый, без video= |

## Исправления 2026-11-01 — wf-panel-pi 1.43

После обновления пакетов (wf-panel-pi 1.43) **панель исчезла**: watchdog запускал её
с флагом `-c /path/to/wfpanel-dsi.ini`, а в 1.43 такого параметра больше нет.

| Что | Было | Стало |
|-----|------|-------|
| Запуск панели | `wf-panel-pi -c "$ini"` | `wf-panel-pi` (без аргументов) |
| Откуда конфиг | явный путь через `-c` | сам из `~/.config/wf-panel-pi/wf-panel-pi.ini` |
| Формат конфига | `plugins=menu,spacer,network,...` | `widgets_left=...` / `widgets_right=...` |
| Симптом | панели нет, в логе `перезапущен (exit=0)` каждую секунду | панель на месте, виджеты в нужном порядке |

**Как распознать:** `wf-panel-pi --help` — если в списке параметров нет `-c`, версия 1.43+.
Панель в этом случае печатает `Неизвестный параметр -c` и выходит с кодом 0 (то есть
«успешно»), поэтому watchdog считает выход нормальным и перезапускает бесконечно.

**Проверка порядка виджетов:** в `widgets_left` / `widgets_right` порядок перечисления =
порядок на панели. Например `... clock spacing2 tray spacing2 cputemp ...` даёт
часы → температура NVMe (tray) → температура CPU (cputemp).

## Исправления 2026-11-01 (продолжение) — где живёт конфиг панели

Долго искали, почему правки конфига не действуют: панель 1.43 читает
**`~/.config/wf-panel-pi/wf-panel-pi.ini`**, а не `~/.config/wfpanel/wfpanel-<монитор>.ini`
(последний — наследие старых версий, панель его игнорирует молча).

| Что | Было | Стало |
|-----|------|-------|
| Файл конфига | `~/.config/wfpanel/wfpanel-dsi.ini` | `~/.config/wf-panel-pi/wf-panel-pi.ini` |
| Проверить, что читает панель | — | `strace -f -e trace=openat wf-panel-pi` (в старом пути `.ini` не будет) |

**Порядок «NVMe рядом с CPU»:** значок температуры NVMe — это SNI-элемент внутри плагина
`tray`, поэтому его позиция определяется местом `tray` в `widgets_right`. Рабочая строка:

```
widgets_right=power ejecter spacing2 connect spacing2 bluetooth spacing2 netman spacing2 volumepulse spacing2 clock spacing2 tray spacing2 cputemp spacing2 batt
```

даёт: … часы → **NVMe (tray)** → **CPU (cputemp)** → батарея. Две температурные плашки
встают вплотную друг к другу справа от часов.

⚠️ `panel-watchdog.sh` **не должен** генерировать этот файл заново: в нём живут ручные
настройки (отступы меню `smenu_padding`, порядок виджетов). Скрипт проверяет наличие файла
и оставляет его как есть.
