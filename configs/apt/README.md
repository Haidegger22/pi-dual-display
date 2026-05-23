# Apt Pinning для labwc

## Проблема
В Debian trixie labwc 0.8.3 — старая версия, которая неправильно работает с DSI-дисплеем на Pi4.
Raspberry Pi репозиторий содержит labwc 0.9.2 с патчами для Pi.

## Решение
Установить правильную версию из rpi-репозитория и закрепить её:

```bash
sudo apt install labwc=0.9.2-1+rpt4
```

После установки рекомендуется закрепить версию:

```ini
# /etc/apt/preferences.d/pin-labwc-stable
Package: labwc
Pin: version 0.9.2-1+rpt4
Pin-Priority: 1001
```

## Удаление старого pin (если был установлен ранее)
```bash
sudo rm /etc/apt/preferences.d/pin-labwc  # pin на 0.8.3
```
