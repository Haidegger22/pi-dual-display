#!/usr/bin/env python3
"""
NVMe-температура в трее панели wf-panel-pi (Wayland/labwc).

Рисует цифру температуры NVMe в иконке трея, обновляется каждые 10 секунд.
Источник данных: smartctl (через sudo без пароля), резерв — health.log «чёрного ящика».
Ободок по периметру: зелёный <=49°, золотой <=64°, алый >=65°.

ВАЖНО про размер: слот трея в wf-panel-pi — квадрат примерно 30x28 px, и панель
растягивает картинку на него целиком. Крупный холст (96x96) панель сжимает, и
цифры теряют форму (выглядят вытянутыми). Поэтому рисуем сразу 32x32 — почти 1:1.

Запуск вручную:  WAYLAND_DISPLAY=wayland-0 ~/.local/bin/nvme-temp-tray.py
Автозапуск:      user-сервис nvme-temp-tray.service
"""
import os
import re
import subprocess
import sys

import cairo

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")

from gi.repository import AyatanaAppIndicator3 as AppIndicator
from gi.repository import GLib, Gtk

DISK = "/dev/sda"
# Панель ищет иконку по имени в теме (а не по пути к файлу), поэтому PNG
# кладём в каталог иконок hicolor и отдаём панели короткое имя.
ICON_DIR = os.path.expanduser("~/.local/share/icons/hicolor/32x32/apps")
# Каталоги прошлых версий: там остаются иконки другого размера, их надо убрать,
# иначе панель может подхватить старую.
OLD_ICON_DIRS = (
    os.path.expanduser("~/.local/share/icons/hicolor/96x96/apps"),
    os.path.expanduser("~/.local/share/icons/hicolor/48x48/apps"),
)
ICON_PREFIX = "nvme-temp"
REFRESH_SEC = 10
SIZE = 32          # ровно под слот трея (панель показывает иконку ~30x28)


def read_temp():
    """Температура NVMe: сначала smartctl, затем health.log. None, если не удалось."""
    try:
        out = subprocess.run(
            ["sudo", "-n", "smartctl", "-A", DISK],
            capture_output=True, text=True, timeout=20,
        ).stdout
        m = re.search(r"^Temperature:\s+(\d+)", out, re.M)
        if m:
            return int(m.group(1))
    except Exception:
        pass
    try:
        line = subprocess.run(
            ["tail", "-1", "/var/log/blackbox/health.log"],
            capture_output=True, text=True, timeout=5,
        ).stdout
        m = re.search(r"NVMe (\d+)°C", line)
        if m:
            return int(m.group(1))
    except Exception:
        pass
    return None


def temp_color(t):
    """Цвет неонового ободка: зелёный до 49°, золотой до 64°, алый от 65°."""
    if t is None:
        return (0.62, 0.62, 0.62)      # серый — нет данных
    if t <= 49:
        return (0.10, 0.95, 0.35)      # неоново-зелёный
    if t <= 64:
        return (1.00, 0.78, 0.10)      # золотой
    return (1.00, 0.16, 0.16)          # алый


THEME_ROOTS = (
    "/usr/share/icons",
    os.path.expanduser("~/.local/share/icons"),
    os.path.expanduser("~/.icons"),
)


def current_icon_theme():
    """Активная GTK-тема иконок (на Pi4 это PiXtrix)."""
    try:
        out = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        return out.strip("'\"")
    except (OSError, subprocess.SubprocessError):
        return ""


def sync_to_theme(name):
    """Копирует иконку в текущую тему.

    wf-panel-pi 1.43+ ищет значок трея в АКТИВНОЙ теме (PiXtrix), а не только в
    hicolor. Без этой копии значок молча не рисуется: именно поэтому после
    ребута/перезапуска панели плашка NVMe пропадала, хотя сервис был active и
    SNI-регистрация на месте. Проверено 01.11.2026.
    """
    theme = current_icon_theme()
    if not theme or theme == "hicolor":
        return
    src = os.path.join(ICON_DIR, name + ".png")
    if not os.path.exists(src):
        return
    src_mtime = os.path.getmtime(src)
    changed = False
    for root in THEME_ROOTS:
        theme_root = os.path.join(root, theme)
        if not os.path.isdir(theme_root):
            continue
        for sub in ("32x32/apps", "32x32/status"):
            dst_dir = os.path.join(theme_root, sub)
            dst = os.path.join(dst_dir, name + ".png")
            if os.path.exists(dst) and os.path.getmtime(dst) >= src_mtime:
                continue
            # каталог системной темы принадлежит root -> install через sudo -n
            subprocess.run(
                ["sudo", "-n", "install", "-D", "-m", "644", src, dst],
                capture_output=True, timeout=10,
            )
            changed = True
        # подчистить прошлые значения в теме, чтобы не копились
        for sub in ("32x32/apps", "32x32/status"):
            d = os.path.join(theme_root, sub)
            if not os.path.isdir(d):
                continue
            for f in os.listdir(d):
                if f.startswith(ICON_PREFIX + "-") and f != name + ".png":
                    subprocess.run(["sudo", "-n", "rm", "-f", os.path.join(d, f)],
                                   capture_output=True, timeout=10)
    if changed:
        for root in THEME_ROOTS:
            theme_root = os.path.join(root, theme)
            if os.path.isdir(theme_root):
                subprocess.run(["sudo", "-n", "gtk-update-icon-cache", "-f", "-t", theme_root],
                               capture_output=True, timeout=20)


def draw_icon(t):
    """Плашка в стиле штатного виджета CPU (светло-серая + тёмная цифра)
    и неоновый ободок по периметру; цвет ободка — по температуре.

    Возвращает имя иконки для панели (без пути и расширения).
    """
    os.makedirs(ICON_DIR, exist_ok=True)
    W = H = SIZE
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
    cr = cairo.Context(surf)
    cr.set_source_rgba(0, 0, 0, 0)
    cr.paint()

    neon = temp_color(t)
    rad = 4.5        # скругление плашки
    m = 2.0          # поле под свечение

    def rounded():
        cr.new_sub_path()
        cr.arc(W - m - rad, m + rad, rad, -1.5708, 0)
        cr.arc(W - m - rad, H - m - rad, rad, 0, 1.5708)
        cr.arc(m + rad, H - m - rad, rad, 1.5708, 3.1416)
        cr.arc(m + rad, m + rad, rad, 3.1416, 4.7124)
        cr.close_path()

    # неоновое свечение: несколько всё более узких обводок
    for alpha, width in ((0.20, 4.0), (0.35, 2.5), (0.55, 1.5)):
        rounded()
        cr.set_source_rgba(*neon, alpha)
        cr.set_line_width(width)
        cr.stroke()

    # сама плашка — как у CPU: светло-серая с тонкой тёмной рамкой
    rounded()
    cr.set_source_rgba(0.83, 0.83, 0.83, 1.0)
    cr.fill_preserve()
    cr.set_source_rgba(0.30, 0.30, 0.30, 1.0)
    cr.set_line_width(0.9)
    cr.stroke()

    # неоновая линия по краю плашки (яркая, поверх фона)
    rounded()
    cr.set_source_rgba(*neon, 0.95)
    cr.set_line_width(1.6)
    cr.stroke()

    # цифра — тёмно-серая, как у штатного виджета
    txt = f"{t}°" if t is not None else "--"
    cr.set_source_rgba(0.22, 0.22, 0.22, 1.0)
    cr.select_font_face("DejaVu Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    cr.set_font_size(14)
    ext = cr.text_extents(txt)
    cr.move_to((W - ext.width) / 2 - ext.x_bearing,
               (H - ext.height) / 2 - ext.y_bearing)
    cr.show_text(txt)

    name = f"{ICON_PREFIX}-{t}" if t is not None else f"{ICON_PREFIX}-na"
    path = os.path.join(ICON_DIR, name + ".png")
    surf.write_to_png(path)

    # Убираем прошлые значения и кэш темы: панель wf-panel-pi читает
    # icon-theme.cache и без этого продолжает показывать старое значение.
    for f in os.listdir(ICON_DIR):
        if f.startswith(ICON_PREFIX + "-") and f != name + ".png":
            try:
                os.remove(os.path.join(ICON_DIR, f))
            except OSError:
                pass
    for d in OLD_ICON_DIRS:
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if f.startswith(ICON_PREFIX + "-"):
                try:
                    os.remove(os.path.join(d, f))
                except OSError:
                    pass
    cache = os.path.join(os.path.dirname(os.path.dirname(ICON_DIR)), "icon-theme.cache")
    if os.path.exists(cache):
        try:
            os.remove(cache)
        except OSError:
            pass
    sync_to_theme(name)
    return name


class NvmeTray:
    def __init__(self):
        self.temp = read_temp()
        self.ind = AppIndicator.Indicator.new(
            "nvme-temp", draw_icon(self.temp), AppIndicator.IndicatorCategory.HARDWARE
        )
        self.ind.set_status(AppIndicator.IndicatorStatus.ACTIVE)
        self.ind.set_title("NVMe")
        # theme path уже при первом показе: панель может стартовать после значка
        self.ind.set_icon_theme_path(ICON_DIR)
        self.ind.set_icon_full(draw_icon(self.temp), self.label())

        menu = Gtk.Menu()
        self.header = Gtk.MenuItem(label=self.label())
        self.header.set_sensitive(False)
        menu.append(self.header)
        menu.append(Gtk.SeparatorMenuItem())
        item = Gtk.MenuItem(label="Обновить сейчас")
        item.connect("activate", lambda *_: self.refresh())
        menu.append(item)
        item = Gtk.MenuItem(label="Выход")
        item.connect("activate", lambda *_: Gtk.main_quit())
        menu.append(item)
        menu.show_all()
        self.ind.set_menu(menu)

        GLib.timeout_add_seconds(REFRESH_SEC, self.refresh)

    def label(self):
        return f"NVMe {self.temp}°C" if self.temp is not None else "NVMe: нет данных"

    def refresh(self):
        self.temp = read_temp()
        # set_icon_theme_path перестраивает тему иконок в панели: без этого
        # wf-panel-pi держит картинку в кэше и продолжает показывать старое значение.
        self.ind.set_icon_theme_path(ICON_DIR)
        self.ind.set_icon_full(draw_icon(self.temp), self.label())
        self.header.set_label(self.label())
        return True


def main():
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        print("нет графической сессии (нужны DISPLAY или WAYLAND_DISPLAY)", file=sys.stderr)
        return 1
    NvmeTray()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
