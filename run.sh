#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO="$PROFILE_DIR/out/archlinux-baseline-2026.07.19-x86_64.iso"

[ -f "$ISO" ] || { echo "ISO not found: $ISO"; exit 1; }

# --- UEFI firmware setup ---
OVMF_CODE=$(find /usr/share/OVMF /usr/share/edk2/x64 -name "OVMF_CODE*" 2>/dev/null | head -1)
[ -n "$OVMF_CODE" ] || { echo "Error: OVMF_CODE not found. Install edk2-ovmf package."; exit 1; }

OVMF_VARS="$PROFILE_DIR/OVMF_VARS.fd"
if [ ! -f "$OVMF_VARS" ]; then
    OVMF_VARS_SRC=$(find /usr/share/OVMF /usr/share/edk2/x64 -name "OVMF_VARS*.fd" ! -name "*secboot*" 2>/dev/null | head -1)
    if [ -n "$OVMF_VARS_SRC" ]; then
        echo "Copying OVMF_VARS.fd from $OVMF_VARS_SRC ..."
        cp "$OVMF_VARS_SRC" "$OVMF_VARS"
    else
        echo "Error: OVMF_VARS.fd not found."
        echo "  Install edk2-ovmf package, or copy one from:"
        echo "    /usr/share/edk2/x64/OVMF_VARS.4m.fd"
        exit 1
    fi
fi

exec qemu-system-x86_64 \
    -cdrom "$ISO" \
    -boot d \
    -m 2G \
    -enable-kvm \
    -machine pc-q35-9.0 \
    -cpu host \
    -smp 4 \
    -display default \
    -device virtio-vga \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS"
