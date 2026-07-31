#!/usr/bin/env bash
#
# Create local Arch Linux repository from downloaded packages.
# - Copies packages from official_packages and aur_packages
# - Creates repository database using repo-add
#

set -euo pipefail

# --- Config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

OFFICIAL_DIR="$PROJECT_ROOT/downloads/official_packages"
AUR_DIR="$PROJECT_ROOT/downloads/aur_packages"
REPO_DIR="$PROJECT_ROOT/airootfs/var/cache/aestheticos/offline-mirror"

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

echo "============================================================"
echo "Create Local Repository"
echo "============================================================"
echo ""

# --- Check source directories ---
if [[ ! -d "$OFFICIAL_DIR" ]] || [[ -z "$(ls -A "$OFFICIAL_DIR" 2>/dev/null)" ]]; then
    echo "Error: official_packages directory is empty or not found: $OFFICIAL_DIR"
    exit 1
fi

if [[ ! -d "$AUR_DIR" ]] || [[ -z "$(ls -A "$AUR_DIR" 2>/dev/null)" ]]; then
    echo "Error: aur_packages directory is empty or not found: $AUR_DIR"
    exit 1
fi

# --- Count packages (only .pkg.tar.zst, not .sig) ---
official_count=$(find "$OFFICIAL_DIR" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)
aur_count=$(find "$AUR_DIR" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)
total_count=$((official_count + aur_count))

log "Found $official_count official + $aur_count AUR packages"
echo ""

# --- Create repository directory ---
log "Creating repository directory..."
mkdir -p "$REPO_DIR"
ok "Repository directory: $REPO_DIR"
echo ""

# --- Copy packages ---
log "Copying packages to repository..."

# Copy official packages (only .pkg.tar.zst, not .sig)
if [[ $official_count -gt 0 ]]; then
    cp "$OFFICIAL_DIR"/*.pkg.tar.zst "$REPO_DIR/" 2>/dev/null || true
    ok "Copied $official_count official packages"
fi

# Copy AUR packages (only .pkg.tar.zst, not .sig)
if [[ $aur_count -gt 0 ]]; then
    cp "$AUR_DIR"/*.pkg.tar.zst "$REPO_DIR/" 2>/dev/null || true
    ok "Copied $aur_count AUR packages"
fi

# --- Create repository database ---
log "Creating repository database..."

# Count final packages
final_count=$(find "$REPO_DIR" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)

if [[ $final_count -eq 0 ]]; then
    echo "Error: No packages found in repository"
    exit 1
fi

# Create aestheticos-offline.db.tar.zst using repo-add
# repo-add automatically creates .db.tar.zst, .files.tar.zst and symlinks .db, .files
repo-add "$REPO_DIR/aestheticos-offline.db.tar.zst" "$REPO_DIR"/*.pkg.tar.* 2>&1 | tail -5

ok "Repository database created"
echo ""

# --- Report ---
echo "================================="
echo "Repository Created Successfully"
echo "================================="
echo ""
echo "Repository location: $REPO_DIR"
echo "Total packages: $final_count"
echo ""
echo "Database file: $REPO_DIR/aestheticos-offline.db.tar.zst"
