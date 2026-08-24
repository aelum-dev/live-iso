#!/usr/bin/env bash
#
# Step 3: Build AUR packages with makepkg
# Usage: bash step-3.sh /project/root
#

set -euo pipefail

PROJECT_ROOT="${1:?Usage: $0 <project_root>}"
BUILD_DIR="${PROJECT_ROOT}/downloads/aur_build"
DOWNLOAD_DIR="${PROJECT_ROOT}/downloads/aur_packages"

log() { echo "==> $*"; }
ok()  { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }
err() { echo "  ✗ $*"; }

# Check for PKGBUILDs
pkg_count=0
for pkg_dir in "$BUILD_DIR"/*/; do
    [[ ! -d "$pkg_dir" ]] && continue
    [[ -f "$pkg_dir/PKGBUILD" ]] && ((pkg_count++)) || true
done

if [[ $pkg_count -eq 0 ]]; then
    echo "Error: No PKGBUILDs found in $BUILD_DIR"
    echo "Run step-2.sh first to download AUR sources."
    exit 1
fi

log "Found $pkg_count packages to build"

# Build packages
log "Building packages..."
mkdir -p "$DOWNLOAD_DIR"

built=()
failed=()

for pkg_dir in "$BUILD_DIR"/*/; do
    [[ ! -d "$pkg_dir" ]] && continue
    pkg_name=$(basename "$pkg_dir")
    [[ ! -f "$pkg_dir/PKGBUILD" ]] && continue

    log "Building $pkg_name..."
    cd "$pkg_dir"

    if makepkg --noconfirm --nocheck --skipinteg 2>&1; then
        for pkg_file in *.pkg.tar.zst; do
            [[ -f "$pkg_file" ]] && mv "$pkg_file" "$DOWNLOAD_DIR/"
        done
        find . -maxdepth 1 -name '*.sig' -delete 2>/dev/null || true
        ok "Built: $pkg_name"
        built+=("$pkg_name")
    else
        err "Failed: $pkg_name"
        failed+=("$pkg_name")
    fi

    cd - > /dev/null
done

echo ""
log "Build complete: ${#built[@]} built, ${#failed[@]} failed"

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "Failed packages:"
    for pkg in "${failed[@]}"; do
        echo "  ✗ $pkg"
    done
fi

total=$(find "$DOWNLOAD_DIR" -maxdepth 1 -name '*.pkg.tar.*' | wc -l)
log "Total AUR packages: $total"
