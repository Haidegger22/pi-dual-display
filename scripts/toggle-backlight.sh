#!/bin/bash

BL_DIR="/sys/class/backlight/10-0045"
BL="$BL_DIR/brightness"
MAX=$(cat "$BL_DIR/max_brightness")
CUR=$(cat "$BL")
SAVED="/tmp/backlight.saved"

if [ "$CUR" = "0" ]; then
    # Подсветка выключена — включаем
    VAL=$(cat "$SAVED" 2>/dev/null || echo "$MAX")
    echo "$VAL" > "$BL"
    notify-send "🔆 Подсветка включена" -t 2000
    exit 0
fi

# Сохраняем и выключаем
echo "$CUR" > "$SAVED"
echo 0 > "$BL"
notify-send "🌙 Подсветка выключена" "Нажми любую клавишу или пошевели мышью..." -t 3000

# Ждём любое событие ввода через Python (надёжнее cat + timeout)
python3 << 'EOF' 2>/dev/null
import select
import os
import glob

fds = []
for dev in sorted(glob.glob('/dev/input/event*')):
    try:
        fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
        fds.append(fd)
    except Exception:
        pass

if fds:
    # Ждём любое событие на любом устройстве (таймаут 12 часов)
    select.select(fds, [], [], 43200)
    for fd in fds:
        os.close(fd)
EOF

# Включаем подсветку обратно
VAL=$(cat "$SAVED" 2>/dev/null || echo "$MAX")
echo "$VAL" > "$BL"
rm -f "$SAVED"
notify-send "🔆 Подсветка включена" -t 2000
