#!/usr/bin/env python3
"""Generate Aelum Plymouth (LUKS unlock) theme assets.
Uses only PIL. Supersamples for anti-aliased edges on transparent PNGs."""
import sys
from PIL import Image, ImageDraw

OUT = sys.argv[1]

# Aelum brand palette (extracted from logo.png)
LIGHT = (191, 126, 143)   # #bf7e8f
DARK = (153, 91, 111)     # #995b6f
BG = (14, 11, 13)         # #0e0b0d  (matches the boot background)


def render(size, draw_fn):
    W, H = size
    s = 4
    big = Image.new("RGBA", (W * s, H * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    draw_fn(d, s)
    return big.resize((W, H), Image.LANCZOS)


def rounded_box(d, xy, radius, fill=None, outline=None, width=1):
    d.rounded_rectangle(xy, radius=radius * 4, fill=fill,
                        outline=outline, width=width * 4)


def make_lock():
    def fn(d, s):
        # shackle
        d.line([(22 * s, 28 * s), (22 * s, 19 * s)], fill=LIGHT, width=7 * s)
        d.line([(42 * s, 28 * s), (42 * s, 19 * s)], fill=LIGHT, width=7 * s)
        d.arc([22 * s, 10 * s, 42 * s, 30 * s], 180, 360, fill=LIGHT, width=7 * s)
        # body
        rounded_box(d, (20 * s, 28 * s, 44 * s, 52 * s), 5, fill=LIGHT)
        # keyhole
        d.ellipse([30 * s, 35 * s, 34 * s, 39 * s], fill=DARK)
    return render((64, 64), fn)


def make_entry():
    def fn(d, s):
        # translucent fill
        d.rounded_rectangle([0, 0, 250 * s, 46 * s], radius=9,
                            fill=(18, 15, 17, 150))
        # mauve border
        d.rounded_rectangle([1 * s, 1 * s, (250 - 1) * s, (46 - 1) * s], radius=9,
                            outline=LIGHT, width=2)
    return render((250, 46), fn)


def make_bullet():
    def fn(d, s):
        d.ellipse([1 * s, 1 * s, 11 * s, 11 * s], fill=LIGHT)
    return render((12, 12), fn)


def make_progress_box():
    def fn(d, s):
        d.rounded_rectangle([0, 0, 250 * s, 8 * s], radius=4,
                            fill=(34, 28, 30, 220))
    return render((250, 8), fn)


def make_progress_bar():
    def fn(d, s):
        # solid rounded bar with a subtle top highlight
        d.rounded_rectangle([0, 0, 250 * s, 8 * s], radius=4, fill=LIGHT)
        d.line([(2 * s, 2 * s), (248 * s, 2 * s)], fill=(255, 255, 255, 160),
               width=1)
    return render((250, 8), fn)


def make_logo():
    src = Image.open("/home/power007/Pictures/logo.png").convert("RGBA")
    target_h = 200
    target_w = max(1, int(src.width * (target_h / src.height)))
    return src.resize((target_w, target_h), Image.LANCZOS)


import os
os.makedirs(OUT, exist_ok=True)
make_logo().save(os.path.join(OUT, "logo.png"))
make_lock().save(os.path.join(OUT, "lock.png"))
make_entry().save(os.path.join(OUT, "entry.png"))
make_bullet().save(os.path.join(OUT, "bullet.png"))
make_progress_box().save(os.path.join(OUT, "progress_box.png"))
make_progress_bar().save(os.path.join(OUT, "progress_bar.png"))
print("wrote assets to", OUT)
