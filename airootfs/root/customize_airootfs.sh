#!/usr/bin/env bash
#
# archiso customization hook — runs inside the new root, after every package is
# installed, in a real `arch-chroot` (mkarchiso calls `_make_customize_airootfs`).
# mkarchiso deletes this file again once it has run, so it never ships.
#
# Why this exists
# ---------------
# The live ISO shipped an empty /var/cache/fontconfig (only CACHEDIR.TAG). The
# first GUI process on every boot is the installer; its GTK/Pango init makes
# Fontconfig enumerate every font before the window can be mapped, so it has to
# cold-read all 893 fonts / ~670 MB through the xz-compressed squashfs. Measured
# on the live ISO with a cold page cache:
#
#     no cache            -> 14.0 s to the installer window
#     prebuilt cache      ->  5.8 s to the installer window
#
# i.e. ~8 s of the black screen was just re-building a cache that never changes.
#
# The stock Fontconfig pacman hook (usr/share/libalpm/hooks/fontconfig.hook,
# `fc-cache -s`) does run during pacstrap, but pacstrap runs hooks in a bare
# chroot with no /proc mounted, where Fontconfig cannot build the cache — so
# /var/cache/fontconfig ended up empty. arch-chroot mounts /proc, so it works
# here. (The equivalent glibc hook does not care and succeeds, which is why
# /var/cache/ldconfig/aux-cache *is* present in the ISO.)
set -euo pipefail

echo "[aelum] pre-building the Fontconfig cache"

# -f: rebuild even if a cache looks current; -s: system dirs (/usr/share/fonts)
# only, written to /var/cache/fontconfig for every user of the live session.
fc-cache -f -s

# Fail loudly rather than shipping an ISO that silently pays ~8 s per boot.
shopt -s nullglob
caches=(/var/cache/fontconfig/*.cache-*)
if (( ${#caches[@]} == 0 )); then
    echo "[aelum] ERROR: Fontconfig cache was not generated under /var/cache/fontconfig" >&2
    exit 1
fi

echo "[aelum] Fontconfig cache written: ${#caches[@]} file(s)"
