#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ── Config ──────────────────────────────────────────────────────────────────
WORK_DIR="${SCRIPT_DIR}/work"
OUT_DIR="${SCRIPT_DIR}/out"
PROFILE="profiledef.sh"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log()    { echo -e "${GREEN}[build]${NC} $*"; }
warn()   { echo -e "${YELLOW}[warn]${NC} $*"; }
err()    { echo -e "${RED}[error]${NC} $*" >&2; }

# ── Cleanup old work dir ────────────────────────────────────────────────────
if [ -d "$WORK_DIR" ]; then
    log "Cleaning old work directory..."
    sudo rm -rf "$WORK_DIR"
fi

# ── Step 1: Build local repo ────────────────────────────────────────────────
log "Step 1/2: Building local repository..."
sudo python3 "$SCRIPT_DIR/build_repo.py"

# ── Step 2: Build ISO with mkarchiso ────────────────────────────────────────
log "Step 2/2: Building ISO with mkarchiso..."
sudo mkarchiso -w "$WORK_DIR" -o "$OUT_DIR" "$SCRIPT_DIR"

# ── Done ────────────────────────────────────────────────────────────────────
ISO_FILE=$(ls -t "$OUT_DIR"/*.iso 2>/dev/null | head -1)
if [ -n "$ISO_FILE" ] && [ -f "$ISO_FILE" ]; then
    log "ISO built successfully: $ISO_FILE"
    log "Size: $(du -h "$ISO_FILE" | cut -f1)"
else
    err "ISO file not found in $OUT_DIR"
    exit 1
fi
