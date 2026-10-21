#!/usr/bin/env python3
"""Generate the Aelum rEFInd theme artwork.

The generated PNGs are committed to the profile (they ship inside the ISO and
the installer copies them onto the ESP), so this script only needs to run when
the brand colours, logo, or layout change:

    python3 scripts/gen-refind-theme.py

Outputs (airootfs/usr/share/aelum/refind/themes/aelum/):
    background.png      3840x2160 branded boot screen (scaled down on 1080p)
    font.png            rEFInd font at 1x: 96 glyphs, 13x28 cells
    font-2x.png         rEFInd font at 2x: 96 glyphs, 26x56 cells
    selection_big.png   288x288 selected-icon highlight
    selection_small.png 128x128 selected-tool highlight
    icons/os_arch.png   256x256 Aelum icon (also os_linux.png)

rEFInd doubles icon sizes at screen widths >= 1921 (HIDPI_MIN), so these
assets are generated at 2x: the icons are native on 2K/4K and downscaled on
1080p. Fonts are not scaled by rEFInd; the installer selects font-2x.png when
the live display's preferred mode is HiDPI, i.e. at least 1921px wide (2K, 4K,
ultrawide; see installer/backend/install/configure).

rEFInd expects a *black* glyph sheet. It inverts the glyph RGB values when
the text sits on a dark background, which renders the labels white; a white
sheet would be inverted to black.

The logo source is the Plymouth theme's mark, so the same A is used by the
boot splash and the boot menu.

Requires: Pillow, numpy, and a bold sans font (Nunito is preferred, matching
the website/installer wordmark).
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
THEME_DIR = ROOT / "airootfs/usr/share/aelum/refind/themes/aelum"
ICON_DIR = THEME_DIR / "icons"
LOGO_PATH = ROOT / "airootfs/usr/share/plymouth/themes/aelum/logo.png"

# Brand palette (shared with website/src/styles/base.css and the Plymouth theme).
ACCENT = (0x83, 0x4C, 0x74)  # #834c74 — Aelum plum
ACCENT_LIGHT = (0xCE, 0x8E, 0xBA)  # #ce8eba — light plum
ACCENT_MUTED = (0xB7, 0x7A, 0xA5)  # #b77aa5 — mid plum
INDIGO = (0x4C, 0x4A, 0x86)  # wallpaper indigo
BG_TOP = (0x19, 0x13, 0x22)
BG_BOTTOM = (0x0B, 0x09, 0x10)
CREAM_TOP = (0xFB, 0xF4, 0xF8)
CREAM_BOTTOM = (0xEA, 0xDC, 0xE5)
CREAM_BORDER = (0xC9, 0xA9, 0xBE)
TEXT = (0xE9, 0xE0, 0xE8)

SCALE = 4  # supersampling for rounded corners


def hex_str(color: tuple[int, int, int]) -> str:
    return "#%02x%02x%02x" % color


def find_font(*names: str) -> Path:
    """Return the first installed font matching one of the Fontconfig queries."""
    for name in names:
        try:
            out = subprocess.run(
                ["fc-match", "-f", "%{file}", name],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
        except (OSError, subprocess.CalledProcessError):
            continue
        if out:
            return Path(out)
    fallback = Path("/usr/share/fonts/TTF/DejaVuSans-Bold.ttf")
    if fallback.exists():
        return fallback
    raise SystemExit("no usable bold sans font found (install Nunito or DejaVu)")


def rounded_mask(size: int, radius: int) -> Image.Image:
    """Anti-aliased rounded-square alpha mask."""
    big = size * SCALE
    mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, big - 1, big - 1), radius=radius * SCALE, fill=255)
    return mask.resize((size, size), Image.Resampling.LANCZOS)


def vertical_gradient(size: int, color_top: tuple[int, ...], color_bottom: tuple[int, ...]) -> Image.Image:
    """Vertical gradient over an RGBA square (3- or 4-tuples accepted)."""
    if len(color_top) == 3:
        color_top = (*color_top, 255)
        color_bottom = (*color_bottom, 255)
    column = np.linspace(color_top, color_bottom, size, dtype=np.float32)
    arr = np.repeat(column[:, None, :], size, axis=1).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def radial_glow(
    width: int,
    height: int,
    center: tuple[float, float],
    radius: float,
    color: tuple[int, int, int],
    peak_alpha: float,
) -> Image.Image:
    """Soft round glow, alpha falling off quadratically to the radius."""
    yy, xx = np.mgrid[0:height, 0:width]
    dist = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2)
    falloff = np.clip(1.0 - dist / radius, 0.0, 1.0) ** 2
    layer = np.zeros((height, width, 4), dtype=np.uint8)
    layer[..., 0], layer[..., 1], layer[..., 2] = color
    layer[..., 3] = (falloff * peak_alpha * 255).astype(np.uint8)
    return Image.fromarray(layer, "RGBA")


def load_mark(width: int) -> Image.Image:
    mark = Image.open(LOGO_PATH).convert("RGBA")
    height = round(mark.height * width / mark.width)
    return mark.resize((width, height), Image.Resampling.LANCZOS)


def make_background(scale: int = 2) -> Image.Image:
    width, height = 1920 * scale, 1080 * scale

    column = np.linspace(BG_TOP, BG_BOTTOM, height, dtype=np.float32)
    base = Image.fromarray(
        np.repeat(column[:, None, :], width, axis=1).astype(np.uint8), "RGB"
    ).convert("RGBA")

    # Ambient light echoing the desktop wallpaper: plum and pink on the right,
    # cool indigo top-left. Kept dim so menu text stays legible.
    base = Image.alpha_composite(base, radial_glow(width, height, (1280 * scale, 760 * scale), 980 * scale, ACCENT, 0.30))
    base = Image.alpha_composite(base, radial_glow(width, height, (1060 * scale, 700 * scale), 560 * scale, ACCENT_LIGHT, 0.12))
    base = Image.alpha_composite(base, radial_glow(width, height, (240 * scale, 200 * scale), 820 * scale, INDIGO, 0.18))

    # Vignette: focus the eye on the centred menu.
    yy, xx = np.mgrid[0:height, 0:width]
    norm = np.sqrt(((xx - width / 2) / (width / 2)) ** 2 + ((yy - height / 2) / (height / 2)) ** 2)
    factor = 1.0 - 0.28 * np.clip(norm / 1.42, 0.0, 1.0) ** 2
    arr = np.asarray(base).astype(np.float32)
    arr[..., :3] *= factor[..., None]
    base = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    # Oversized watermark mark behind the menu (rEFInd draws the icon row at
    # roughly the vertical centre, so keep this faint).
    mark = load_mark(620 * scale)
    watermark = mark.copy()
    alpha = watermark.getchannel("A").point(lambda a: a * 10 // 255)
    watermark.putalpha(alpha)
    base.alpha_composite(watermark, (width // 2 - mark.width // 2, 600 * scale - mark.height // 2))

    draw = ImageDraw.Draw(base)

    # Header lockup: mark + "Aelum" wordmark, centred at the top.
    word_font = ImageFont.truetype(str(find_font("Nunito:style=ExtraBold", "Nunito:style=Bold", "sans-serif:style=Bold")), 46 * scale)
    word = "Aelum"
    word_box = draw.textbbox((0, 0), word, font=word_font)
    word_w = word_box[2] - word_box[0]
    word_h = word_box[3] - word_box[1]

    header_mark = load_mark(64 * scale)
    gap = 18 * scale
    lockup_w = header_mark.width + gap + word_w
    left = width // 2 - lockup_w // 2
    mark_top = 54 * scale
    base.alpha_composite(header_mark, (left, mark_top + (word_h - header_mark.height) // 2))
    draw.text(
        (left + header_mark.width + gap - word_box[0], mark_top - word_box[1]),
        word,
        font=word_font,
        fill=(*TEXT, 235),
    )

    # Corner tag: out of the way of rEFInd's own bottom hint line.
    tag_font = ImageFont.truetype(str(find_font("sans-serif", "DejaVu Sans")), 19 * scale)
    tag = "A E L U M . D E V"
    tag_box = draw.textbbox((0, 0), tag, font=tag_font)
    draw.text(
        (width - 56 * scale - (tag_box[2] - tag_box[0]), height - 42 * scale - (tag_box[3] - tag_box[1])),
        tag,
        font=tag_font,
        fill=(*TEXT, 78),
    )

    # Fine noise hides gradient banding on 8-bit panels; RGB noise only.
    rng = np.random.default_rng(7)
    arr = np.asarray(base).astype(np.int16)
    noise = rng.integers(-2, 3, size=(height, width, 1), dtype=np.int16)
    arr[..., :3] = np.clip(arr[..., :3] + noise, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA").convert("RGB")


def make_selection(base_size: int, scale: int = 1) -> Image.Image:
    """Rounded selection tile, drawn at base_size x scale."""
    size = base_size * scale
    radius = (base_size * 9 // 48) * scale
    rim_width = max(2, base_size // 64) * scale
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Outer glow, built from the same rounded shape and blurred.
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_mask = rounded_mask(size, radius).point(lambda a: a * 120 // 255)
    glow_color = Image.new("RGBA", (size, size), (*ACCENT_LIGHT, 255))
    glow = Image.composite(glow_color, glow, glow_mask)
    glow.putalpha(glow_mask)
    glow = glow.filter(ImageFilter.GaussianBlur(size / 34))
    canvas.alpha_composite(glow)

    inset = max(2, base_size // 32) * scale
    inner = size - inset * 2
    body = vertical_gradient(inner, (0x9C, 0x5A, 0x87, 178), (0x5E, 0x35, 0x52, 178))
    body.putalpha(rounded_mask(inner, radius - inset // 2).point(lambda a: a * 178 // 255))

    # Light-plum rim.
    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rim_draw = ImageDraw.Draw(rim)
    rim_draw.rounded_rectangle(
        (inset, inset, size - inset - 1, size - inset - 1),
        radius=radius - inset // 2,
        outline=(0xEF, 0xC0, 0xDC, 235),
        width=rim_width,
    )
    canvas.alpha_composite(body, (inset, inset))
    canvas.alpha_composite(rim)
    return canvas


def make_icon(base_size: int = 128, scale: int = 1) -> Image.Image:
    """Aelum OS tile, drawn at base_size x scale."""
    size = base_size * scale
    radius = (base_size * 15 // 64) * scale
    border_width = max(2, base_size // 64) * scale
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    body = vertical_gradient(size, CREAM_TOP, CREAM_BOTTOM)
    body.putalpha(rounded_mask(size, radius))
    tile.alpha_composite(body)

    draw = ImageDraw.Draw(tile)
    draw.rounded_rectangle(
        (border_width // 2, border_width // 2, size - 1 - border_width // 2, size - 1 - border_width // 2),
        radius=radius,
        outline=(*CREAM_BORDER, 255),
        width=border_width,
    )

    mark = load_mark(round(size * 0.62))
    x = (size - mark.width) // 2
    y = (size - mark.height) // 2 + scale
    tile.alpha_composite(mark, (x, y))
    return tile


def make_font(scale: int = 1) -> Image.Image:
    """rEFInd font: ASCII 32-126 plus the out-of-range glyph, one line.

    Glyphs are black: rEFInd inverts the RGB channels when the menu text is on
    a dark background, turning black glyphs white. A white sheet would render
    black on the Aelum background.
    """
    size, cell = 20 * scale, 13 * scale
    ascent, descent = 21 * scale, 7 * scale
    height = ascent + descent
    font = ImageFont.truetype(str(find_font("JetBrainsMonoNL:style=Medium", "JetBrains Mono:style=Medium", "monospace")), size)

    width = cell * 96
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    glyphs = [chr(c) for c in range(32, 127)] + ["?"]
    assert len(glyphs) == 96
    for i, ch in enumerate(glyphs):
        if ch == " ":
            continue
        box = draw.textbbox((0, 0), ch, font=font)
        glyph_w = box[2] - box[0]
        if glyph_w > cell:
            raise SystemExit(f"glyph {ch!r} is {glyph_w}px wide, cell is {cell}px")
        x = i * cell + (cell - glyph_w) // 2 - box[0]
        draw.text((x, ascent), ch, font=font, fill=(0, 0, 0, 255), anchor="ls")
    return image


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)

    background = make_background(2)
    background.save(THEME_DIR / "background.png", optimize=True)

    make_selection(144, 2).save(THEME_DIR / "selection_big.png", optimize=True)
    make_selection(64, 2).save(THEME_DIR / "selection_small.png", optimize=True)

    icon = make_icon(128, 2)
    icon.save(ICON_DIR / "os_arch.png", optimize=True)
    icon.save(ICON_DIR / "os_linux.png", optimize=True)

    make_font(1).save(THEME_DIR / "font.png", optimize=True)
    make_font(2).save(THEME_DIR / "font-2x.png", optimize=True)

    for path in sorted(THEME_DIR.rglob("*.png")):
        with Image.open(path) as img:
            print(f"{path.relative_to(ROOT)}  {img.width}x{img.height}  {img.mode}")


if __name__ == "__main__":
    main()
