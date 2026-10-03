#!/usr/bin/env bash
# Run by the pacman hook 90-aelum-boot-logo.hook after packages are installed
# during the ISO build (mkarchiso always points HookDir at
# airootfs/etc/pacman.d/hooks/).
#
# Overrides the stock plymouth "Arch Linux" watermark (a file owned by the
# `plymouth` package at /usr/share/plymouth/themes/spinner/watermark.png) with
# Aelum's branded logo.
#
# The logo is staged at a non-package path (/usr/local/...), so there is no
# "conflicting files" error during pacstrap; we copy it into place here, after
# install, when overwriting the package-owned path is safe.
set -eu

SRC="/usr/share/aelum/boot/watermark.png"
DST="/usr/share/plymouth/themes/spinner/watermark.png"

if [[ ! -f "$SRC" ]]; then
	echo "[aelum] warning: branded boot logo not found at $SRC, keeping stock plymouth watermark" >&2
	exit 0
fi

install -Dm644 "$SRC" "$DST"
echo "[aelum] installed branded plymouth boot logo"
