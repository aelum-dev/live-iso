#!/usr/bin/env bash
#
# Build-time only. Enable the kernel's parallel squashfs decompressor for the
# live ISO by patching mkinitcpio-archiso's runtime hook.
#
# Why
# ---
# squashfs has a `threads=` mount option (single|multi|percpu|N); the default is
# `single`, which decompresses one block at a time on one core. Arch's kernel is
# built with CONFIG_SQUASHFS_CHOICE_DECOMP_BY_MOUNT and
# CONFIG_SQUASHFS_MOUNT_DECOMP_THREADS, so the option is available to us.
#
# A single xz block cannot be parallelised - it is one LZMA2 stream for one
# core. But mksquashfs compresses every block independently (no shared
# dictionary across blocks), so independent blocks *can* be decoded
# concurrently. `threads=percpu` runs one decompressor per core (capped at
# 2*num_online_cpus); when readahead issues several block reads at once, or
# several files are read at once, more than one core is used.
#
# Why a patch
# -----------
# The archiso hook mounts the image with a hardcoded `-o defaults`, and archiso
# exposes no profile knob for squashfs mount options. We add `threads=percpu`
# to the one call that mounts the airootfs image. mkinitcpio runs after pacstrap
# and this runs as a PostTransaction hook, so the live initramfs picks it up.
#
# runs from: etc/pacman.d/hooks/50-aelum-squashfs-threads.hook, which sorts
# before mkinitcpio's 90-mkinitcpio-install.hook so the initramfs is built from
# this patched hook.
set -uo pipefail

hook=/usr/lib/initcpio/hooks/archiso
threads=percpu

if [[ ! -f "$hook" ]]; then
    echo "[aelum] ERROR: ${hook} not found; cannot enable squashfs threads" >&2
    exit 1
fi

if grep -qF "defaults,threads=${threads}" "$hook"; then
    echo "[aelum] squashfs mount already uses threads=${threads}"
    exit 0
fi

# Only the _mnt_fs() call - the one that mounts the airootfs image - references
# ${img_loopdev}. Anchoring on it keeps the patch off every other mount (the ISO
# device, the cow space, ...), which would reject a squashfs-only option.
if ! grep -qF '${img_loopdev}' "$hook"; then
    echo "[aelum] ERROR: no squashfs mount call found in ${hook}; upstream archiso changed" >&2
    grep -n '_mnt_dev' "$hook" >&2
    exit 1
fi

sed -i "/img_loopdev}/ s/\"-r\" \"defaults\"/\"-r\" \"defaults,threads=${threads}\"/" "$hook"

if ! grep -qF "defaults,threads=${threads}" "$hook"; then
    echo "[aelum] ERROR: failed to patch ${hook}" >&2
    grep -n 'img_loopdev}\|_mnt_dev' "$hook" >&2
    exit 1
fi

echo "[aelum] patched ${hook}: airootfs squashfs now mounts with threads=${threads}"
