#!/usr/bin/env python3
"""Draws the DMG window background: app on the left, arrow, Applications on the right.

Writes background.png (1x) and background@2x.png next to this script.
Icon positions here must match scripts/dmg/settings.py.
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
# Taller than the visible area: newer Finder versions overlay path and status bars at the bottom.
WIDTH, HEIGHT = 660, 520
APP_X, APPS_X, ICON_Y = 165, 495, 190


def font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                f = ImageFont.truetype(path, size)
                if bold:
                    try:
                        f.set_variation_by_name("Semibold")
                    except Exception:
                        pass
                return f
            except OSError:
                continue
    return ImageFont.load_default()


def draw(scale):
    w, h = WIDTH * scale, HEIGHT * scale
    img = Image.new("RGB", (w, h))
    px = img.load()
    top, bottom = (246, 247, 252), (226, 230, 246)
    for y in range(h):
        t = y / (h - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = color

    d = ImageDraw.Draw(img)

    title = "Drag AeroWall to Applications to install"
    f = font(17 * scale, bold=True)
    tw = d.textlength(title, font=f)
    d.text(((w - tw) / 2, 40 * scale), title, font=f, fill=(40, 40, 70))

    # Arrow between the two icons.
    y = ICON_Y * scale
    x0, x1 = (APP_X + 75) * scale, (APPS_X - 75) * scale
    color = (110, 90, 220)
    d.line([(x0, y), (x1 - 18 * scale, y)], fill=color, width=6 * scale)
    d.polygon([(x1, y), (x1 - 24 * scale, y - 16 * scale), (x1 - 24 * scale, y + 16 * scale)], fill=color)

    hint = "Then open AeroWall from Applications. It lives in the menu bar."
    f2 = font(12 * scale)
    hw = d.textlength(hint, font=f2)
    d.text(((w - hw) / 2, 335 * scale), hint, font=f2, fill=(100, 100, 130))
    return img


if __name__ == "__main__":
    draw(1).save(os.path.join(HERE, "background.png"))
    draw(2).save(os.path.join(HERE, "background@2x.png"))
    print("Wrote DMG backgrounds")
