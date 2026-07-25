#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Автопоиск ISO в папке out/ (или передача пути первым аргументом: ./run.sh path/to.iso)
ISO="${1:-$(find "$PROFILE_DIR/out" -maxdepth 1 -name "*.iso" 2>/dev/null | head -1)}"

if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
    echo "Error: ISO file not found in $PROFILE_DIR/out/"
    exit 1
fi

echo "Using ISO: $ISO"

# --- Shared Directory ---
SHARED_DIR="$HOME/Projects/shared"
mkdir -p "$SHARED_DIR"

# --- UEFI firmware setup ---
# Приоритет отдаем парным 4M файлам edk2
OVMF_CODE=$(find /usr/share/edk2/x64 /usr/share/OVMF -name "OVMF_CODE.4m.fd" 2>/dev/null | head -1)
[ -n "$OVMF_CODE" ] || OVMF_CODE=$(find /usr/share/edk2/x64 /usr/share/OVMF -name "OVMF_CODE*.fd" 2>/dev/null | head -1)

[ -n "$OVMF_CODE" ] || { echo "Error: OVMF_CODE not found. Install edk2-ovmf package."; exit 1; }

OVMF_VARS="$PROFILE_DIR/OVMF_VARS.fd"
if [ ! -f "$OVMF_VARS" ]; then
    OVMF_VARS_SRC=$(find /usr/share/edk2/x64 /usr/share/OVMF -name "OVMF_VARS.4m.fd" ! -name "*secboot*" 2>/dev/null | head -1)
    [ -n "$OVMF_VARS_SRC" ] || OVMF_VARS_SRC=$(find /usr/share/edk2/x64 /usr/share/OVMF -name "OVMF_VARS*.fd" ! -name "*secboot*" 2>/dev/null | head -1)
    
    if [ -n "$OVMF_VARS_SRC" ]; then
        echo "Copying OVMF_VARS.fd from $OVMF_VARS_SRC ..."
        cp "$OVMF_VARS_SRC" "$OVMF_VARS"
    else
        echo "Error: OVMF_VARS.fd source not found."
        exit 1
    fi
fi

# --- Virtual disk ---
VDISK="$PROFILE_DIR/vdisk.qcow2"
if [ ! -f "$VDISK" ]; then
    echo "Creating virtual disk: $VDISK (10G) ..."
    qemu-img create -f qcow2 "$VDISK" 10G
fi

# --- Run QEMU ---
exec qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp 4,sockets=1,cores=4,threads=1 \
    -m 4G \
    -machine q35 \
    -cdrom "$ISO" \
    -boot d \
    -display sdl,gl=on \
    -device virtio-vga-gl \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -drive id=vdisk,file="$VDISK",if=none,format=qcow2,cache=writeback,aio=io_uring \
    -device virtio-blk-pci,drive=vdisk \
    -virtfs local,path="$SHARED_DIR",mount_tag=shared,security_model=mapped,id=hostshared