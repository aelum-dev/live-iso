#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/archiso-build"
ISO_DIR="out"
REPO_DIR="$PROFILE_DIR/repo"
AIROOTFS_REPO="$PROFILE_DIR/airootfs/repo"
BLANK_DB="/tmp/blankdb"

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

# ── Step 2: Build local pacman repository ───────────────────────────────────
echo ""
echo "=== Building local repository ==="
mkdir -p "$REPO_DIR"
mkdir -p "$BLANK_DB"

# Read curated packages from packages.x86_64 (skip blank lines and comments)
PACKAGES=()
while IFS= read -r line; do
    line="${line%%#*}"        # strip inline comments
    line="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace
    line="${line%"${line##*[![:space:]]}"}"  # trim trailing whitespace
    [[ -n "$line" ]] && PACKAGES+=("$line")
done < "$PROFILE_DIR/packages.x86_64"

echo "Packages to fetch: ${PACKAGES[*]}"

# Download ALL packages (including dependencies) into a temp dir first,
# then copy into repo/. This bypasses pacman 7+ alpm-user download isolation
# which cannot write to the project directory.
DOWNLOAD_DIR="/tmp/archiso-download"
sudo rm -rf "$DOWNLOAD_DIR"
sudo mkdir -p "$DOWNLOAD_DIR"

sudo pacman -Syw --noconfirm \
    --cachedir "$DOWNLOAD_DIR" \
    --dbpath "$BLANK_DB" \
    "${PACKAGES[@]}"

# Move downloaded packages into the repo directory
sudo cp "$DOWNLOAD_DIR"/*.pkg.tar.zst "$REPO_DIR/"
sudo rm -rf "$DOWNLOAD_DIR"

# Create the repo database from the downloaded packages
repo-add "$REPO_DIR/custom.db.tar.zst" "$REPO_DIR"/*.pkg.tar.zst

echo "Local repo built: $(ls "$REPO_DIR"/*.pkg.tar.zst 2>/dev/null | wc -l) packages"

# ── Step 3: Copy repo into airootfs ─────────────────────────────────────────
echo ""
echo "=== Packing repo into airootfs ==="
sudo rm -rf "$AIROOTFS_REPO"
sudo mkdir -p "$AIROOTFS_REPO"
sudo cp "$REPO_DIR"/*.pkg.tar.zst "$AIROOTFS_REPO/"
sudo cp "$REPO_DIR/custom.db.tar.zst" "$AIROOTFS_REPO/"
sudo cp "$REPO_DIR/custom.files.tar.zst" "$AIROOTFS_REPO/" 2>/dev/null || true

echo "Repo copied to $AIROOTFS_REPO"

# ── Step 4: Run mkarchiso ───────────────────────────────────────────────────
echo ""
echo "=== Running mkarchiso ==="
sudo mkarchiso -w "$WORK_DIR" -v -m iso -o "$ISO_DIR" -r "$PROFILE_DIR"

echo ""
echo "=== Build complete ==="
echo "ISO location:"
ls -lh "$ISO_DIR"/*.iso 2>/dev/null || echo "No ISO found in $ISO_DIR"
