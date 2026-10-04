#!/usr/bin/env python3
"""Draws the AeroWall app icon and writes the AppIcon asset catalog.

Usage: python3 scripts/generate_icon.py   (requires Pillow)
"""
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "AeroWall", "Assets.xcassets", "AppIcon.appiconset")

S = 2048  # drawn at 2x, downsampled for smooth edges
TILE = int(S * 824 / 1024)  # macOS icon grid: 824pt tile on a 1024pt canvas
OFFSET = (S - TILE) // 2
RADIUS = int(TILE * 0.225)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def vertical_gradient(size, stops):
    w, h = size
    img = Image.new("RGBA", size)
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        for i in range(len(stops) - 1):
            (t0, c0), (t1, c1) = stops[i], stops[i + 1]
            if t0 <= t <= t1:
                color = lerp(c0, c1, (t - t0) / (t1 - t0))
                break
        for x in range(w):
            px[x, y] = color
    return img


def tile_mask():
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [OFFSET, OFFSET, OFFSET + TILE, OFFSET + TILE], radius=RADIUS, fill=255
    )
    return mask


def wave_layer(y_base, amplitude, phase, color, thickness):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    points = []
    for x in range(OFFSET - 40, OFFSET + TILE + 40, 6):
        t = (x - OFFSET) / TILE
        y = y_base + amplitude * math.sin(t * math.pi * 2 + phase)
        points.append((x, y))
    # Fill everything below the curve so waves stack like hills.
    draw.polygon(points + [(OFFSET + TILE + 40, S), (OFFSET - 40, S)], fill=color)
    if thickness:
        draw.line(points, fill=(255, 255, 255, 140), width=thickness)
    return layer


def main():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = tile_mask()

    # Drop shadow under the tile.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 110), (0, 0), mask)
    shadow = ImageChops.offset(shadow, 0, int(S * 0.012)).filter(ImageFilter.GaussianBlur(S * 0.014))
    canvas = Image.alpha_composite(canvas, shadow)

    # Twilight sky.
    tile = vertical_gradient((S, S), [
        (0.0, (32, 24, 92, 255)),
        (0.45, (88, 64, 210, 255)),
        (0.75, (64, 140, 245, 255)),
        (1.0, (90, 210, 250, 255)),
    ])

    # Soft sun glow.
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx, cy, r = OFFSET + TILE * 0.70, OFFSET + TILE * 0.55, TILE * 0.19
    ImageDraw.Draw(glow).ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 214, 150, 255))
    halo = glow.filter(ImageFilter.GaussianBlur(TILE * 0.09))
    tile = Image.alpha_composite(tile, halo)
    tile = Image.alpha_composite(tile, glow.filter(ImageFilter.GaussianBlur(2)))

    # Flowing "aero" waves.
    tile = Image.alpha_composite(tile, wave_layer(OFFSET + TILE * 0.60, TILE * 0.045, 0.6, (110, 90, 230, 170), 6))
    tile = Image.alpha_composite(tile, wave_layer(OFFSET + TILE * 0.70, TILE * 0.050, 2.4, (60, 120, 235, 210), 6))
    tile = Image.alpha_composite(tile, wave_layer(OFFSET + TILE * 0.81, TILE * 0.040, 4.1, (30, 70, 170, 235), 6))

    # Play badge.
    badge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(badge)
    bx, by, br = OFFSET + TILE * 0.36, OFFSET + TILE * 0.33, TILE * 0.17
    bd.ellipse([bx - br, by - br, bx + br, by + br], fill=(255, 255, 255, 70), outline=(255, 255, 255, 200), width=int(S * 0.008))
    tri = br * 0.55
    bd.polygon([
        (bx - tri * 0.55, by - tri),
        (bx - tri * 0.55, by + tri),
        (bx + tri * 1.0, by),
    ], fill=(255, 255, 255, 245))
    tile = Image.alpha_composite(tile, badge)

    # Top highlight for depth.
    highlight = vertical_gradient((S, S), [(0.0, (255, 255, 255, 60)), (0.5, (255, 255, 255, 0)), (1.0, (255, 255, 255, 0))])
    tile = Image.alpha_composite(tile, highlight)

    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(tile, (0, 0), mask)
    canvas = Image.alpha_composite(canvas, clipped)

    master = canvas.resize((1024, 1024), Image.LANCZOS)

    os.makedirs(ICONSET, exist_ok=True)
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            master.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, name))
            images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})

    with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)
    with open(os.path.join(os.path.dirname(ICONSET), "Contents.json"), "w") as f:
        json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)
    print(f"Wrote {len(images)} icons to {ICONSET}")


if __name__ == "__main__":
    main()
