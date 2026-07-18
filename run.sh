#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO="$PROFILE_DIR/out/archlinux-baseline-2026.07.19-x86_64.iso"

[ -f "$ISO" ] || { echo "ISO not found: $ISO"; exit 1; }

OVMF_CODE=$(find /usr/share/OVMF /usr/share/edk2/x64 -name "OVMF_CODE*" 2>/dev/null | head -1)
OVMF_VARS="$PROFILE_DIR/OVMF_VARS.fd"

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
