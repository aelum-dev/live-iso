#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/archiso-build"
ISO_DIR="out"

echo "=== ArchISO Builder ==="
echo "Profile: $PROFILE_DIR"
echo "Work dir: $WORK_DIR"
echo "Iso dir: $ISO_DIR"

# Clean previous build artifacts (may contain root-owned files from prior runs)
sudo rm -rf "$WORK_DIR"
sudo mkdir -p "$WORK_DIR"
sudo mkdir -p "$ISO_DIR"

# Run mkarchiso as root
# -w : working directory
# -v : verbose output
# -m : build modes (from profiledef.sh)
# -r : remove working directory after build
# -o : output directory for the ISO
sudo mkarchiso -w "$WORK_DIR" -v -m iso -o "$ISO_DIR" -r "$PROFILE_DIR"

echo ""
echo "=== Build complete ==="
echo "ISO location:"
ls -lh "$ISO_DIR"/*.iso 2>/dev/null || echo "No ISO found in $WORK_DIR"
