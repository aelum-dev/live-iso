#!/usr/bin/env bash
#
# Build AestheticOS ISO using mkarchiso.
#

set -euo pipefail

# --- Config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Helpers ---
log() { echo "==> $*"; }
ok()  { echo "  ✓ $*"; }
err() { echo "  ✗ $*"; }

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script requires root privileges."
    echo "Please run with sudo."
    exit 1
fi

# --- Check mkarchiso ---
if ! command -v mkarchiso &> /dev/null; then
    echo "Error: mkarchiso not found. Install with: pacman -S archiso"
    exit 1
fi

echo "============================================================"
echo "Build AestheticOS ISO"
echo "============================================================"
echo ""

# --- Check airootfs ---
if [[ ! -d "$PROJECT_ROOT/airootfs" ]]; then
    echo "Error: airootfs directory not found"
    exit 1
fi

# --- Check profiledef.sh ---
if [[ ! -f "$PROJECT_ROOT/profiledef.sh" ]]; then
    echo "Error: profiledef.sh not found"
    exit 1
fi

# --- Clean work directory ---
if [[ -d "$PROJECT_ROOT/work" ]]; then
    log "Removing old work directory..."
    rm -rf "$PROJECT_ROOT/work"
    ok "Work directory cleaned"
    echo ""
fi

# --- Prepare offline pacman.conf ---
# Use a dedicated offline config (no network mirrors) for ISO build
OFFLINE_MIRROR_PATH="$PROJECT_ROOT/airootfs/var/cache/aestheticos/offline-mirror"
PACMAN_OFFLINE_CONF="$PROJECT_ROOT/pacman-offline.conf"

if [[ -f "$PACMAN_OFFLINE_CONF" ]]; then
    # Replace placeholder with actual path
    sed -i "s|/OFFLINE_MIRROR_PATH|$OFFLINE_MIRROR_PATH|" "$PACMAN_OFFLINE_CONF"
    log "Prepared offline pacman.conf: Server = file://$OFFLINE_MIRROR_PATH"
fi

log "Starting ISO build..."
echo ""

# --- Build ISO ---
cd "$PROJECT_ROOT"

mkarchiso -v -w work -o output \
    -C pacman-offline.conf \
    -m iso \
    .

echo ""

# --- Check result ---
iso_file=$(ls -t output/*.iso 2>/dev/null | head -1)

if [[ -n "$iso_file" ]]; then
    iso_size=$(du -h "$iso_file" | cut -f1)
    ok "ISO built successfully: $iso_file"
    ok "ISO size: $iso_size"
    echo ""
    echo "============================================================"
    echo "ISO Build Complete"
    echo "============================================================"
    echo ""
    echo "Output: $iso_file"
    echo "Size: $iso_size"
    echo ""
else
    err "ISO build failed"
    exit 1
fi
