#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/archiso-build"

echo "=== ArchISO Builder ==="
echo "Profile: $PROFILE_DIR"
echo "Work dir: $WORK_DIR"

# Clean previous build artifacts
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Run mkarchiso as root
sudo mkarchiso -w "$WORK_DIR" -L "$WORK_DIR/build.log" "$PROFILE_DIR"

echo ""
echo "=== Build complete ==="
echo "ISO location:"
ls -lh "$WORK_DIR"/*.iso 2>/dev/null || echo "No ISO found in $WORK_DIR"
