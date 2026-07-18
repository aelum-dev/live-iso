#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/archiso-build"
ISO_DIR="out"
REPO_DIR="$PROFILE_DIR/airootfs/repo"
BLANK_DB="/tmp/blankdb"
DOWNLOAD_DIR="/tmp/archiso-download"

echo "=== Offline ArchISO Builder ==="
echo "Profile: $PROFILE_DIR"
echo "Work dir: $WORK_DIR"
echo "Iso dir: $ISO_DIR"
echo "Local repo: $REPO_DIR"

# ── Step 1: Clean previous build artifacts ──────────────────────────────────
sudo rm -rf "$WORK_DIR"
sudo mkdir -p "$WORK_DIR"
sudo mkdir -p "$ISO_DIR"
sudo rm -rf "$BLANK_DB"
sudo rm -rf "$DOWNLOAD_DIR"

# ── Step 2: Download packages ───────────────────────────────────────────────
echo ""
echo "=== Downloading packages ==="
mkdir -p "$REPO_DIR"
mkdir -p "$DOWNLOAD_DIR"
mkdir -p "$BLANK_DB"

# Use existing repo packages as cache to avoid re-downloading
sudo cp "$REPO_DIR"/*.pkg.tar.zst "$DOWNLOAD_DIR/" 2>/dev/null || true

# Read ISO packages from packages.x86_64 (skip blank lines and comments)
ISO_PACKAGES=()
while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] && ISO_PACKAGES+=("$line")
done < "$PROFILE_DIR/packages.x86_64"

echo "ISO packages: ${ISO_PACKAGES[*]}"

# Read repo packages from repo_packages.x86_64 (skip blank lines and comments)
REPO_PACKAGES=()
while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] && REPO_PACKAGES+=("$line")
done < "$PROFILE_DIR/repo_packages.x86_64"

echo "Repo packages: ${REPO_PACKAGES[*]}"

# Download ALL packages using blank dbpath and temp cachedir (bypasses pacman 7 alpm-user isolation)
sudo pacman -Syw --noconfirm \
    --cachedir "$DOWNLOAD_DIR" \
    --dbpath "$BLANK_DB" \
    "${ISO_PACKAGES[@]}" "${REPO_PACKAGES[@]}"

# Copy downloaded packages to repo directory
sudo cp "$DOWNLOAD_DIR"/*.pkg.tar.zst "$REPO_DIR/"
sudo rm -rf "$DOWNLOAD_DIR"

# Create the repo database
sudo repo-add -q "$REPO_DIR/custom.db.tar.zst" "$REPO_DIR"/*.pkg.tar.zst

echo "Local repo built: $(ls "$REPO_DIR"/*.pkg.tar.zst 2>/dev/null | wc -l) packages"

# ── Step 3: Run mkarchiso ───────────────────────────────────────────────────
# Note: mkarchiso uses the profile's pacman.conf for pacstrap.
# The profile pacman.conf has [custom] pointing to file://FILE_REPO_PATH,
# but we don't use it during build (pacstrap uses core/extra from mirrorlist).
# The local repo in airootfs/repo is only for the final ISO.
echo ""
echo "=== Running mkarchiso ==="
sudo mkarchiso -w "$WORK_DIR" -v -m iso -o "$ISO_DIR" -r "$PROFILE_DIR"

echo ""
echo "=== Build complete ==="
echo "ISO location:"
ls -lh "$ISO_DIR"/*.iso 2>/dev/null || echo "No ISO found in $ISO_DIR"
