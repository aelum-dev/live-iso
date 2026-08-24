#!/usr/bin/env bash
#
# Step 4: Create local Arch Linux repository from downloaded packages
# Usage: bash step-4.sh /project/root
#

set -euo pipefail

PROJECT_ROOT="${1:?Usage: $0 <project_root>}"

OFFICIAL_DIR="${PROJECT_ROOT}/downloads/official_packages"
AUR_DIR="${PROJECT_ROOT}/downloads/aur_packages"
REPO_DIR="${PROJECT_ROOT}/airootfs/var/cache/aestheticos/offline-mirror"

log() { echo "==> $*"; }
ok()  { echo "  ✓ $*"; }

# Check source directories
if [[ ! -d "$OFFICIAL_DIR" ]] || [[ -z "$(ls -A "$OFFICIAL_DIR" 2>/dev/null)" ]]; then
    echo "Error: official_packages is empty or not found: $OFFICIAL_DIR"
    exit 1
fi

if [[ ! -d "$AUR_DIR" ]] || [[ -z "$(ls -A "$AUR_DIR" 2>/dev/null)" ]]; then
    echo "Error: aur_packages is empty or not found: $AUR_DIR"
    exit 1
fi

official_count=$(find "$OFFICIAL_DIR" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)
aur_count=$(find "$AUR_DIR" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)
total_count=$((official_count + aur_count))

log "Found $official_count official + $aur_count AUR packages"

# Clean and create repository directory
if [[ -d "$REPO_DIR" ]]; then
    rm -rf "$REPO_DIR"
fi
mkdir -p "$REPO_DIR"

# Copy packages
log "Copying packages to repository..."
cp "$OFFICIAL_DIR"/*.pkg.tar.zst "$REPO_DIR/" 2>/dev/null || true
cp "$AUR_DIR"/*.pkg.tar.zst "$REPO_DIR/" 2>/dev/null || true
ok "Copied $total_count packages"

# Remove .sig files
find "$REPO_DIR" -maxdepth 1 -name '*.sig' -delete 2>/dev/null || true

# Create repository database
log "Creating repository database..."
final_count=$(find "$REPO_DIR" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)

if [[ $final_count -eq 0 ]]; then
    echo "Error: No packages in repository"
    exit 1
fi

repo-add "$REPO_DIR/aestheticos-offline.db.tar.zst" "$REPO_DIR"/*.pkg.tar.zst 2>&1 | tail -3
ok "Repository database created"

# Remove any .sig files from repo-add
find "$REPO_DIR" -maxdepth 1 -name '*.sig' -delete 2>/dev/null || true

echo ""
log "Repository created: $REPO_DIR ($final_count packages)"
