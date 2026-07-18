#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/archiso-build"

echo "=== ArchISO Builder ==="
echo "Profile: $PROFILE_DIR"
echo "Work dir: $WORK_DIR"

# Clean previous build artifacts (may contain root-owned files from prior runs)
sudo rm -rf "$WORK_DIR"
sudo mkdir -p "$WORK_DIR"

# Run mkarchiso as root
# -w : working directory
# -v : verbose output
# -m : build modes (from profiledef.sh)
# -r : remove working directory after build
# -o : output directory for the ISO
sudo mkarchiso -w "$WORK_DIR" -v -m iso -o "$WORK_DIR" -r "$PROFILE_DIR"

echo ""
echo "=== Build complete ==="
echo "ISO location:"
ls -lh "$WORK_DIR"/*.iso 2>/dev/null || echo "No ISO found in $WORK_DIR"
