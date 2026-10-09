#!/usr/bin/env python3
"""Generate the modern, high-fidelity MacDownloadManager app icon.

Design:
- Modern macOS squircle with ambient drop shadow and inner glass rim
- Deep sapphire-to-electric-blue luminous gradient background
- 3-tier multi-connection accelerator stream (energetic emerald -> cyan -> white)
- High-velocity downward arrow descending into a sleek landing dock
- 100% procedurally drawn with PIL vector operations. Completely original artwork.
Output: resources/MacDownloadManager.iconset and resources/MacDownloadManager.icns
"""
import math
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / 'resources' / 'MacDownloadManager.iconset'
ICNS = ROOT / 'resources' / 'MacDownloadManager.icns'


def create_master_icon(size: int = 1024) -> Image.Image:
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Margin & Squircle size (macOS icons standard: ~824px in 1024px canvas)
    pad = int(size * 0.09)
    sq_size = size - 2 * pad
    radius = int(sq_size * 0.224)
    
    # Soft drop shadow
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    s_box = [pad, pad + int(size * 0.035), pad + sq_size, pad + sq_size + int(size * 0.035)]
    s_draw.rounded_rectangle(s_box, radius=radius, fill=(0, 10, 35, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=int(size * 0.035)))
    canvas.alpha_composite(shadow)
    
    # Base squircle with multi-stop vertical gradient & radial highlight
    base_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gradient_img = Image.new('RGBA', (sq_size, sq_size), (0, 0, 0, 0))
    g_px = gradient_img.load()
    
    c_top = (18, 145, 255)
    c_mid = (10, 65, 215)
    c_bot = (6, 20, 110)
    
    for y in range(sq_size):
        ty = y / max(sq_size - 1, 1)
        if ty < 0.5:
            t = ty * 2.0
            r = int(c_top[0] + (c_mid[0] - c_top[0]) * t)
            g = int(c_top[1] + (c_mid[1] - c_top[1]) * t)
            b = int(c_top[2] + (c_mid[2] - c_top[2]) * t)
        else:
            t = (ty - 0.5) * 2.0
            r = int(c_mid[0] + (c_bot[0] - c_mid[0]) * t)
            g = int(c_mid[1] + (c_bot[1] - c_mid[1]) * t)
            b = int(c_mid[2] + (c_bot[2] - c_mid[2]) * t)
            
        for x in range(sq_size):
            dx = (x - sq_size * 0.5) / (sq_size * 0.5)
            dy = (y - sq_size * 0.2) / (sq_size * 0.8)
            dist = math.sqrt(dx * dx + dy * dy)
            hl = max(0.0, 1.0 - dist * 0.85) * 45
            
            nr = min(255, int(r + hl * 0.7))
            ng = min(255, int(g + hl * 0.9))
            nb = min(255, int(b + hl * 1.0))
            g_px[x, y] = (nr, ng, nb, 255)
            
    mask = Image.new('L', (sq_size, sq_size), 0)
    m_draw = ImageDraw.Draw(mask)
    m_draw.rounded_rectangle([0, 0, sq_size, sq_size], radius=radius, fill=255)
    base_layer.paste(gradient_img, (pad, pad), mask)
    
    # Glossy top reflection curve & subtle inner border
    b_box = [pad, pad, pad + sq_size, pad + sq_size]
    overlay = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    o_draw = ImageDraw.Draw(overlay)
    o_draw.rounded_rectangle(b_box, radius=radius, outline=(255, 255, 255, 65), width=max(1, int(size * 0.003)))
    o_draw.chord([pad - 100, pad - 300, pad + sq_size + 100, pad + int(sq_size * 0.55)], 0, 180, fill=(255, 255, 255, 25))
    
    full_mask = Image.new('L', (size, size), 0)
    fm_draw = ImageDraw.Draw(full_mask)
    fm_draw.rounded_rectangle(b_box, radius=radius, fill=255)
    
    canvas.alpha_composite(base_layer)
    canvas.paste(overlay, (0, 0), full_mask)
    
    # Multi-Stream Speed Booster + Velocity Arrow + Landing Dock
    g_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(g_layer)
    cx = size / 2.0
    u = size / 1024.0
    
    # Subtle background stream glow
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gld = ImageDraw.Draw(glow)
    gld.ellipse([cx - 240 * u, 220 * u, cx + 240 * u, 720 * u], fill=(0, 230, 255, 50))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=int(40 * u)))
    canvas.alpha_composite(glow)
    
    # Top chevron 1: Energetic IDM Emerald Green
    c1_y = 230 * u
    c1_w = 180 * u
    c1_h = 38 * u
    c1_pts = [
        (cx - c1_w, c1_y),
        (cx, c1_y + 36 * u),
        (cx + c1_w, c1_y),
        (cx + c1_w, c1_y + c1_h),
        (cx, c1_y + c1_h + 36 * u),
        (cx - c1_w, c1_y + c1_h)
    ]
    gd.polygon(c1_pts, fill=(50, 245, 150, 240))
    
    # Middle chevron 2: Electric Cyan
    c2_y = 300 * u
    c2_w = 200 * u
    c2_h = 40 * u
    c2_pts = [
        (cx - c2_w, c2_y),
        (cx, c2_y + 40 * u),
        (cx + c2_w, c2_y),
        (cx + c2_w, c2_y + c2_h),
        (cx, c2_y + c2_h + 40 * u),
        (cx - c2_w, c2_y + c2_h)
    ]
    gd.polygon(c2_pts, fill=(0, 215, 255, 245))
    
    # Main Velocity Arrow: Pure White with subtle shadow
    arrow_shaft_w = 115 * u
    arrow_top = 375 * u
    arrow_neck = 525 * u
    arrow_head_bottom = 645 * u
    arrow_head_w = 215 * u
    
    arrow_pts = [
        (cx - arrow_shaft_w / 2, arrow_top),
        (cx + arrow_shaft_w / 2, arrow_top),
        (cx + arrow_shaft_w / 2, arrow_neck),
        (cx + arrow_head_w, arrow_neck),
        (cx, arrow_head_bottom),
        (cx - arrow_head_w, arrow_neck),
        (cx - arrow_shaft_w / 2, arrow_neck)
    ]
    
    # Arrow shadow
    arrow_shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    asd = ImageDraw.Draw(arrow_shadow)
    sh_pts = [(x, y + 15 * u) for (x, y) in arrow_pts]
    asd.polygon(sh_pts, fill=(0, 20, 60, 110))
    arrow_shadow = arrow_shadow.filter(ImageFilter.GaussianBlur(radius=int(12 * u)))
    canvas.alpha_composite(arrow_shadow)
    
    # Arrow body
    gd.polygon(arrow_pts, fill=(255, 255, 255, 255))
    
    # Landing Receptacle / Dock (Tray)
    dock_top = 695 * u
    dock_h = 75 * u
    dock_w = 460 * u
    dock_lip_w = 70 * u
    dock_lip_h = 100 * u
    
    # Dock shadow
    dock_shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    dsd = ImageDraw.Draw(dock_shadow)
    dsd.rounded_rectangle([cx - dock_w / 2, dock_top + 10 * u, cx + dock_w / 2, dock_top + dock_h + 10 * u], radius=28 * u, fill=(0, 20, 60, 95))
    dock_shadow = dock_shadow.filter(ImageFilter.GaussianBlur(radius=int(10 * u)))
    canvas.alpha_composite(dock_shadow)
    
    # Dock base and lip walls
    gd.rounded_rectangle([cx - dock_w / 2, dock_top, cx + dock_w / 2, dock_top + dock_h], radius=28 * u, fill=(245, 250, 255, 250))
    gd.rounded_rectangle([cx - dock_w / 2, dock_top - dock_lip_h + dock_h, cx - dock_w / 2 + dock_lip_w, dock_top + dock_h], radius=24 * u, fill=(245, 250, 255, 250))
    gd.rounded_rectangle([cx + dock_w / 2 - dock_lip_w, dock_top - dock_lip_h + dock_h, cx + dock_w / 2, dock_top + dock_h], radius=24 * u, fill=(245, 250, 255, 250))
    
    # Dock status light indicator pill (Green high-speed status)
    pill_w = 110 * u
    pill_h = 24 * u
    pill_y = dock_top + (dock_h - pill_h) / 2
    gd.rounded_rectangle([cx - pill_w / 2, pill_y, cx + pill_w / 2, pill_y + pill_h], radius=12 * u, fill=(35, 225, 130, 255))
    
    canvas.alpha_composite(g_layer)
    return canvas


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    master = create_master_icon(1024)
    specs = [
        (16, 'icon_16x16.png'), (32, 'icon_16x16@2x.png'),
        (32, 'icon_32x32.png'), (64, 'icon_32x32@2x.png'),
        (128, 'icon_128x128.png'), (256, 'icon_128x128@2x.png'),
        (256, 'icon_256x256.png'), (512, 'icon_256x256@2x.png'),
        (512, 'icon_512x512.png'), (1024, 'icon_512x512@2x.png')
    ]
    for px, name in specs:
        master.resize((px, px), Image.LANCZOS).save(ICONSET / name)
    print('Wrote iconset to:', ICONSET)
    
    # Compile to ICNS using macOS iconutil
    res = subprocess.run(['iconutil', '-c', 'icns', str(ICONSET), '-o', str(ICNS)], capture_output=True, text=True)
    if res.returncode == 0:
        print('Successfully compiled ICNS:', ICNS)
    else:
        print('iconutil error:', res.stderr)


if __name__ == '__main__':
    main()
