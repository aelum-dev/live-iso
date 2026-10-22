#!/usr/bin/env python3
"""Generate the Aelum rEFInd theme artwork.

The generated PNGs are committed to the profile (they ship inside the ISO and
the installer copies them onto the ESP), so this script only needs to run when
the brand colours, logo, or layout change:

    python3 scripts/gen-refind-theme.py

Outputs (airootfs/usr/share/aelum/refind/themes/aelum/):
    background.png      3840x2160 live-ISO dark colour + Aelum lockup
                        (scaled down on 1080p)
    font.png            rEFInd font at 1x: 96 glyphs, 13x28 cells
    font-2x.png         rEFInd font at 2x: 96 glyphs, 26x56 cells
    selection_big.png   288x288 selected-icon highlight
    selection_small.png 128x128 selected-tool highlight
    icons/os_*.png      256x256 cream-tile OS icons; os_arch.png is the Aelum mark
    icons/func_*.png,   96x96 light glyphs for the tools row
    icons/tool_*.png
    icons/vol_*.png     64x64 plum badges
    icons/arrow_*.png,  light glyphs for menu arrows, mouse, and boot logos
    icons/mouse.png
    icons/boot_*.png
    icons/transparent.png
                        fully transparent spacer icon

Every icon in rEFInd's stock icons/ directory is overridden here, so the boot
menu never falls back to the stock artwork. OS icons use a Nerd Font glyph
(looked up with website/scripts/icons.py) on the same cream tile as the Aelum
mark; small tools/functions and the arrow/mouse/boot logos are light glyphs on
transparency; volume badges are cream glyphs in a plum circle.

The Nerd Font Symbols source is shared with the website. If the two repos are
not checked out side by side, point AELUM_NERD_FONT at the TTF:

    AELUM_NERD_FONT=/path/to/SymbolsNerdFont-Regular.ttf \
        python3 scripts/gen-refind-theme.py --icons-only

rEFInd doubles icon sizes at screen widths >= 1921 (HIDPI_MIN), so these
assets are generated at 2x: the icons are native on 2K/4K and downscaled on
1080p. Fonts are not scaled by rEFInd; the installer selects font-2x.png when
the live display's preferred mode is HiDPI, i.e. at least 1921px wide (2K, 4K,
ultrawide; see installer/backend/install/configure).

rEFInd expects a *black* glyph sheet. It inverts the glyph RGB values when
the text sits on a dark background, which renders the labels white; a white
sheet would be inverted to black.

The logo source is the Plymouth theme's mark, so the same A is used by the
boot splash and the boot menu. The background is the live ISO's dark-mode
hyprpaper colour from airootfs/usr/share/DankMaterialShell/bg-dark.png
(solid #141218) with the Aelum lockup at the top, so the boot menu matches the
live desktop behind the installer.

Requires: Pillow, numpy, and a bold sans font (Nunito is preferred, matching
the website/installer wordmark).
"""

from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
THEME_DIR = ROOT / "airootfs/usr/share/aelum/refind/themes/aelum"
ICON_DIR = THEME_DIR / "icons"
LOGO_PATH = ROOT / "airootfs/usr/share/plymouth/themes/aelum/logo.png"
BG_DARK_PATH = ROOT / "airootfs/usr/share/DankMaterialShell/bg-dark.png"
# Shared with website/scripts/icons.py. The generated PNGs are committed, so
# only developers regenerating the theme need the full source font.
NERD_FONT_DEFAULT = ROOT.parent / "website/scripts/SymbolsNerdFont-Regular.ttf"

# Nerd Font Symbols codepoints. Look glyphs up with:
#     python3 website/scripts/icons.py find <keyword>
GLYPHS = {
    # OS / distro logos
    "arch": 0xF303,          # linux-archlinux
    "ubuntu": 0xF31B,        # linux-ubuntu
    "debian": 0xF306,        # linux-debian
    "fedora": 0xF30A,        # linux-fedora
    "centos": 0xF304,        # linux-centos
    "gentoo": 0xF30D,        # linux-gentoo
    "manjaro": 0xF312,       # linux-manjaro
    "opensuse": 0xF314,      # linux-opensuse
    "redhat": 0xF316,        # linux-redhat
    "slackware": 0xF318,     # linux-slackware
    "void": 0xF32E,          # linux-void
    "linuxmint": 0xF30E,     # linux-linuxmint
    "elementary": 0xF309,    # linux-elementary
    "endeavour": 0xF322,     # linux-endeavour
    "freebsd": 0xF30C,       # linux-freebsd
    "apple": 0xF179,         # fa-apple
    "chrome": 0xF02AF,       # md-google_chrome
    "clover": 0xF0816,       # md-clover
    "leaf": 0xF032A,         # md-leaf (Haiku)
    "flag": 0xF023B,         # md-flag (NetBSD)
    "linux": 0xF31A,         # linux-tux
    "windows": 0xF05B3,      # md-microsoft_windows
    "usb": 0xF129E,          # md-usb_flash_drive
    # UI / tools
    "info": 0xF02FC,         # md-information
    "list_numbered": 0xF027B,  # md-format_list_numbered
    "lock_reset": 0xF0773,   # md-lock_reset
    "exit": 0xF0206,         # md-exit_to_app
    "chip": 0xF061A,         # md-chip
    "eye_off": 0xF0209,      # md-eye_off
    "download": 0xF01DA,     # md-download
    "restart": 0xF0709,      # md-restart
    "power": 0xF0425,        # md-power
    "terminal": 0xF018D,     # md-console
    "harddisk": 0xF02CA,     # md-harddisk
    "harddisk_plus": 0xF104B,  # md-harddisk_plus
    "lifebuoy": 0xF087E,     # md-lifebuoy
    "memory": 0xF035B,       # md-memory
    "key": 0xF0306,          # md-key
    "network": 0xF06F3,      # md-network
    "shield": 0xF0498,       # md-shield
    "disc": 0xF05EE,         # md-disc
    "earth": 0xF01E7,        # md-earth
    "compass": 0xF018B,      # md-compass
    "help": 0xF02D6,         # md-help
    "floppy": 0xF0249,       # md-floppy
    "arrow_left": 0xF004D,   # md-arrow_left
    "arrow_right": 0xF0054,  # md-arrow_right
    "cursor": 0xF01C0,       # md-cursor_default
}

# rEFInd's stock OS icon names. os_arch is handled separately because it keeps
# the Aelum mark; every other stock name gets a themed glyph.
OS_ICONS = {
    "os_artful": "ubuntu",
    "os_bionic": "ubuntu",
    "os_centos": "centos",
    "os_chakra": "arch",
    "os_chrome": "chrome",
    "os_clover": "clover",
    "os_crunchbang": "terminal",
    "os_debian": "debian",
    "os_devuan": "debian",
    "os_elementary": "elementary",
    "os_endeavouros": "endeavour",
    "os_fedora": "fedora",
    "os_freebsd": "freebsd",
    "os_frugalware": "linux",
    "os_gentoo": "gentoo",
    "os_gummiboot": "arch",
    "os_haiku": "leaf",
    "os_hwtest": "memory",
    "os_kubuntu": "ubuntu",
    "os_legacy": "floppy",
    "os_linux": "linux",
    "os_linuxmint": "linuxmint",
    "os_lubuntu": "ubuntu",
    "os_mac": "apple",
    "os_mageia": "linux",
    "os_mandriva": "linux",
    "os_manjaro": "manjaro",
    "os_netbsd": "flag",
    "os_network": "earth",
    "os_opensuse": "opensuse",
    "os_redhat": "redhat",
    "os_refind": "compass",
    "os_refit": "compass",
    "os_slackware": "slackware",
    "os_suse": "opensuse",
    "os_systemd": "arch",
    "os_trusty": "ubuntu",
    "os_ubuntu": "ubuntu",
    "os_uefi": "chip",
    "os_unknown": "help",
    "os_void": "void",
    "os_win": "windows",
    "os_win8": "windows",
    "os_xenial": "ubuntu",
    "os_xubuntu": "ubuntu",
    "os_zesty": "ubuntu",
    # Theme-only names for Ventoy volumes (not in rEFInd's stock set).
    "os_ventoy": "usb",
    "os_vtoyefi": "usb",
}

# Small tools-row icons, drawn as light glyphs on transparency.
SMALL_ICONS = {
    "func_about": "info",
    "func_bootorder": "list_numbered",
    "func_csr_rotate": "lock_reset",
    "func_exit": "exit",
    "func_firmware": "chip",
    "func_hidden": "eye_off",
    "func_install": "download",
    "func_reset": "restart",
    "func_shutdown": "power",
    "tool_apple_rescue": "apple",
    "tool_fwupdate": "chip",
    "tool_memtest": "memory",
    "tool_mok_tool": "key",
    "tool_netboot": "network",
    "tool_part": "harddisk_plus",
    "tool_rescue": "lifebuoy",
    "tool_shell": "terminal",
    "tool_windows_rescue": "windows",
}

# Volume badges, drawn as cream glyphs in a plum circle.
VOLUME_ICONS = {
    "vol_efi": "shield",
    "vol_external": "usb",
    "vol_internal": "harddisk",
    "vol_net": "network",
    "vol_optical": "disc",
}

# (glyph key, base size, scale): arrows and mouse match rEFInd's native sizes;
# boot logos are drawn at the big-icon size.
PLAIN_ICONS = {
    "arrow_left": ("arrow_left", 48, 2),
    "arrow_right": ("arrow_right", 48, 2),
    "mouse": ("cursor", 16, 2),
    "boot_linux": ("linux", 128, 2),
    "boot_win": ("windows", 128, 2),
}

# Brand palette (shared with website/src/styles/base.css and the Plymouth theme).
ACCENT = (0x83, 0x4C, 0x74)  # #834c74 — Aelum plum
ACCENT_LIGHT = (0xCE, 0x8E, 0xBA)  # #ce8eba — light plum
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


def nerd_font_path() -> Path:
    """Return the Nerd Font Symbols TTF used for the OS glyph icons."""
    override = os.environ.get("AELUM_NERD_FONT")
    path = Path(override).expanduser() if override else NERD_FONT_DEFAULT
    if not path.is_file():
        raise SystemExit(
            f"Nerd Font Symbols not found at {path}; "
            "set AELUM_NERD_FONT to SymbolsNerdFont-Regular.ttf"
        )
    return path


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


def load_mark(width: int) -> Image.Image:
    mark = Image.open(LOGO_PATH).convert("RGBA")
    height = round(mark.height * width / mark.width)
    return mark.resize((width, height), Image.Resampling.LANCZOS)


def make_background(scale: int = 2) -> Image.Image:
    width, height = 1920 * scale, 1080 * scale
    if not BG_DARK_PATH.is_file():
        raise SystemExit(f"live ISO dark background not found at {BG_DARK_PATH}")

    # The live ISO's hyprpaper background is a single dark colour; reproduce it
    # exactly so the boot menu matches the live desktop behind the installer.
    base = Image.open(BG_DARK_PATH).convert("RGB")
    if base.size != (width, height):
        base = base.resize((width, height), Image.Resampling.LANCZOS)
    base = base.convert("RGBA")

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

    return base.convert("RGB")


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


def make_tile(base_size: int = 128, scale: int = 1) -> Image.Image:
    """Cream rounded tile shared by the Aelum mark and the OS glyph icons."""
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
    return tile


def make_icon(base_size: int = 128, scale: int = 1) -> Image.Image:
    """Aelum OS tile, drawn at base_size x scale."""
    size = base_size * scale
    tile = make_tile(base_size, scale)
    mark = load_mark(round(size * 0.62))
    x = (size - mark.width) // 2
    y = (size - mark.height) // 2 + scale
    tile.alpha_composite(mark, (x, y))
    return tile


def glyph_layer(
    codepoint: int,
    size: int,
    color: tuple[int, int, int],
    box_ratio: float,
) -> Image.Image:
    """Render a centred Nerd Font glyph on a transparent canvas.

    The glyph is fitted to size * box_ratio in both axes. Logo glyphs with
    generous side bearings are shrunk to fit rather than clipped.
    """
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    glyph = chr(codepoint)
    font_path = str(nerd_font_path())
    box = max(1, round(size * box_ratio))
    font = ImageFont.truetype(font_path, box)
    bbox = draw.textbbox((0, 0), glyph, font=font)
    glyph_w, glyph_h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    if glyph_w > box or glyph_h > box:
        ratio = min(box / glyph_w, box / glyph_h)
        font = ImageFont.truetype(font_path, max(1, round(box * ratio)))
        bbox = draw.textbbox((0, 0), glyph, font=font)
        glyph_w, glyph_h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (size - glyph_w) // 2 - bbox[0]
    y = (size - glyph_h) // 2 - bbox[1]
    draw.text((x, y), glyph, font=font, fill=(*color, 255))
    return layer


def make_glyph_icon(codepoint: int, base_size: int = 128, scale: int = 1) -> Image.Image:
    """Nerd Font glyph on the shared cream tile, centred and fitted."""
    size = base_size * scale
    tile = make_tile(base_size, scale)
    tile.alpha_composite(glyph_layer(codepoint, size, ACCENT, 0.58))
    return tile


def make_plain_glyph(
    codepoint: int,
    base_size: int = 48,
    scale: int = 2,
    color: tuple[int, int, int] = TEXT,
    box_ratio: float = 0.78,
) -> Image.Image:
    """Light glyph on transparency for the tools row, arrows, mouse, and boot logos."""
    return glyph_layer(codepoint, base_size * scale, color, box_ratio)


def make_badge(codepoint: int, base_size: int = 32, scale: int = 2) -> Image.Image:
    """Plum circular volume badge with a cream glyph."""
    size = base_size * scale
    badge = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    big = size * SCALE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, big - 1, big - 1), fill=255)
    mask = mask.resize((size, size), Image.Resampling.LANCZOS)
    disk = Image.new("RGBA", (size, size), (*ACCENT, 255))
    disk.putalpha(mask)
    badge.alpha_composite(disk)
    badge.alpha_composite(glyph_layer(codepoint, size, CREAM_TOP, 0.58))
    return badge


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
    parser = argparse.ArgumentParser(description="Generate the Aelum rEFInd theme artwork.")
    parser.add_argument(
        "--icons-only",
        action="store_true",
        help="Regenerate only the theme icons (skip background, fonts, and selections).",
    )
    args = parser.parse_args()
    ICON_DIR.mkdir(parents=True, exist_ok=True)

    if not args.icons_only:
        background = make_background(2)
        background.save(THEME_DIR / "background.png", optimize=True)

        make_selection(144, 2).save(THEME_DIR / "selection_big.png", optimize=True)
        make_selection(64, 2).save(THEME_DIR / "selection_small.png", optimize=True)

        make_font(1).save(THEME_DIR / "font.png", optimize=True)
        make_font(2).save(THEME_DIR / "font-2x.png", optimize=True)

    # Aelum's own menu fragments point at os_arch.png, so it keeps the brand
    # mark. Every other stock rEFInd icon name gets a themed replacement, so
    # the menu never falls back to rEFInd's stock artwork.
    make_icon(128, 2).save(ICON_DIR / "os_arch.png", optimize=True)
    for name, key in OS_ICONS.items():
        make_glyph_icon(GLYPHS[key], 128, 2).save(ICON_DIR / f"{name}.png", optimize=True)
    for name, key in SMALL_ICONS.items():
        make_plain_glyph(GLYPHS[key], 48, 2).save(ICON_DIR / f"{name}.png", optimize=True)
    for name, key in VOLUME_ICONS.items():
        make_badge(GLYPHS[key], 32, 2).save(ICON_DIR / f"{name}.png", optimize=True)
    for name, (key, base_size, scale) in PLAIN_ICONS.items():
        make_plain_glyph(GLYPHS[key], base_size, scale).save(ICON_DIR / f"{name}.png", optimize=True)
    Image.new("RGBA", (32, 32), (0, 0, 0, 0)).save(ICON_DIR / "transparent.png", optimize=True)

    for path in sorted(THEME_DIR.rglob("*.png")):
        with Image.open(path) as img:
            print(f"{path.relative_to(ROOT)}  {img.width}x{img.height}  {img.mode}")


if __name__ == "__main__":
    main()
