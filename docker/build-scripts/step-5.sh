#!/usr/bin/env bash
#
# Step 5: Build AestheticOS ISO using mkarchiso
# Usage: bash step-5.sh /project/root
#

set -euo pipefail

PROJECT_ROOT="${1:?Usage: $0 <project_root>}"

log() { echo "==> $*"; }
ok()  { echo "  ✓ $*"; }
err() { echo "  ✗ $*"; }

# Check mkarchiso
if ! command -v mkarchiso &> /dev/null; then
    echo "Error: mkarchiso not found"
    exit 1
fi

# Check airootfs
if [[ ! -d "$PROJECT_ROOT/airootfs" ]]; then
    echo "Error: airootfs directory not found"
    exit 1
fi

# Check profiledef.sh
if [[ ! -f "$PROJECT_ROOT/profiledef.sh" ]]; then
    echo "Error: profiledef.sh not found"
    exit 1
fi

# Clean work directory
if [[ -d "$PROJECT_ROOT/work" ]]; then
    rm -rf "$PROJECT_ROOT/work"
fi

# Prepare offline pacman.conf
OFFLINE_MIRROR_PATH="$PROJECT_ROOT/airootfs/var/cache/aestheticos/offline-mirror"
PACMAN_OFFLINE_CONF="$PROJECT_ROOT/pacman-offline.conf"

if [[ -f "$PACMAN_OFFLINE_CONF" ]]; then
    sed -i "s|/OFFLINE_MIRROR_PATH|$OFFLINE_MIRROR_PATH|" "$PACMAN_OFFLINE_CONF"
    log "Prepared offline pacman.conf"
fi

# Build ISO
log "Starting ISO build..."
cd "$PROJECT_ROOT"

mkarchiso -v -w work -o output \
    -C pacman-offline.conf \
    -m iso \
    .

# Check result
iso_file=$(ls -t output/*.iso 2>/dev/null | head -1)

if [[ -n "$iso_file" ]]; then
    iso_size=$(du -h "$iso_file" | cut -f1)
    echo ""
    ok "ISO built successfully: $iso_file"
    ok "ISO size: $iso_size"
else
    err "ISO build failed"
    exit 1
fi
