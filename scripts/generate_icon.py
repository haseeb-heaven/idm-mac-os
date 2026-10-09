#!/usr/bin/env python3
"""Generate the original MacDownloadManager app icon (no third-party artwork).

Design: rounded-square teal-to-blue gradient, white down arrow landing in an
open tray. Everything is drawn in code with PIL, so the icon is fully
owned by this project. Output: resources/MacDownloadManager.icns (+ .iconset).
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'resources' / 'MacDownloadManager.iconset'
TOP = (45, 200, 225)     # teal
BOTTOM = (30, 110, 235)  # blue
INK = (255, 255, 255)


def base(size: int) -> Image.Image:
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    px = img.load()
    radius = int(size * 0.225)
    for y in range(size):
        t = y / max(size - 1, 1)
        fill = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,)
        for x in range(size):
            # Rounded-rectangle mask.
            cx = min(max(x, radius), size - 1 - radius)
            cy = min(max(y, radius), size - 1 - radius)
            if (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2:
                px[x, y] = fill
    return img


def glyph(img: Image.Image) -> None:
    size = img.width
    d = ImageDraw.Draw(img)
    u = size / 1024.0
    # Down arrow shaft + head.
    shaft_w = 150 * u
    cx = size / 2
    top, bottom = 190 * u, 600 * u
    d.rectangle([cx - shaft_w / 2, top, cx + shaft_w / 2, bottom], fill=INK)
    head = [(cx - 190 * u, bottom - 40 * u), (cx + 190 * u, bottom - 40 * u), (cx, bottom + 150 * u)]
    d.polygon(head, fill=INK)
    # Open tray.
    tray_top, tray_h, tray_w = 700 * u, 90 * u, 560 * u
    d.rounded_rectangle([cx - tray_w / 2, tray_top, cx + tray_w / 2, tray_top + tray_h], radius=45 * u, fill=INK)
    wall_h = 150 * u
    d.rounded_rectangle([cx - tray_w / 2, tray_top - wall_h, cx - tray_w / 2 + 90 * u, tray_top + tray_h], radius=40 * u, fill=INK)
    d.rounded_rectangle([cx + tray_w / 2 - 90 * u, tray_top - wall_h, cx + tray_w / 2, tray_top + tray_h], radius=40 * u, fill=INK)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    master = base(1024)
    glyph(master)
    specs = [(16, 'icon_16x16.png'), (32, 'icon_16x16@2x.png'), (32, 'icon_32x32.png'),
             (64, 'icon_32x32@2x.png'), (128, 'icon_128x128.png'), (256, 'icon_128x128@2x.png'),
             (256, 'icon_256x256.png'), (512, 'icon_256x256@2x.png'),
             (512, 'icon_512x512.png'), (1024, 'icon_512x512@2x.png')]
    for px, name in specs:
        master.resize((px, px), Image.LANCZOS).save(OUT / name)
    print('wrote', OUT)


if __name__ == '__main__':
    main()
