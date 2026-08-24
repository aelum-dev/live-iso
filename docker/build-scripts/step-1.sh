#!/usr/bin/env bash
#
# Step 1: Download official Arch packages + dependencies
# Usage: bash step-1.sh /project/root
#

set -euo pipefail

PROJECT_ROOT="${1:?Usage: $0 <project_root>}"

TEMP_DB="/tmp/blankdb_pacman_download"
SYS_LOCK="/var/lib/pacman/db.lck"

log() { echo "==> $*"; }
ok()  { echo "  ✓ $*"; }

# Sync system databases
log "Syncing system package databases..."
pacman -Sy --noconfirm --disable-sandbox 2>/dev/null || true
ok "System databases synced"

# Prepare temp database
mkdir -p "$TEMP_DB/sync" "$TEMP_DB/local"
for lock_path in "$SYS_LOCK" "$TEMP_DB/db.lck" "$TEMP_DB/sync/db.lock"; do
    [[ -f "$lock_path" ]] && rm -f "$lock_path"
done
cp -a /var/lib/pacman/sync/* "$TEMP_DB/sync/" 2>/dev/null || true
ok "Temporary database ready"

# Read packages
PACKAGE_FILE="${PROJECT_ROOT}/packages.x86_64"
DOWNLOAD_DIR="${PROJECT_ROOT}/downloads/official_packages"

if [[ ! -f "$PACKAGE_FILE" ]]; then
    echo "Error: Package list not found: $PACKAGE_FILE"
    exit 1
fi

mapfile -t PACKAGES < <(grep -vE '^\s*#|^\s*$' "$PACKAGE_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "Error: No packages in $PACKAGE_FILE"
    exit 1
fi

log "Resolved ${#PACKAGES[@]} main packages"

# Resolve full dependency tree
RESOLVED_FILE=$(mktemp)
trap 'rm -f "$RESOLVED_FILE"' EXIT

for pkg in "${PACKAGES[@]}"; do
    pacman --dbpath="$TEMP_DB" -Sp --print-format "%n" "$pkg" 2>/dev/null >> "$RESOLVED_FILE" || true
done

sort -u "$RESOLVED_FILE" -o "$RESOLVED_FILE"
mapfile -t ALL_PKGS < "$RESOLVED_FILE"

log "Resolved ${#ALL_PKGS[@]} total packages (${#PACKAGES[@]} main + $(( ${#ALL_PKGS[@]} - ${#PACKAGES[@]} )) deps)"

# Download packages
mkdir -p "$DOWNLOAD_DIR"
chmod 777 "$DOWNLOAD_DIR"

log "Downloading ${#ALL_PKGS[@]} packages..."
pacman --cachedir="$DOWNLOAD_DIR" --dbpath="$TEMP_DB" -Sw --noconfirm --disable-sandbox "${ALL_PKGS[@]}"
ok "Download complete"

# Cleanup
rm -rf "$TEMP_DB"

# Remove .sig files
find "$DOWNLOAD_DIR" -maxdepth 1 -name '*.sig' -delete 2>/dev/null || true
ok "Cleaned up .sig files"

remaining=$(find "$DOWNLOAD_DIR" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)
echo ""
log "Done! Packages in $DOWNLOAD_DIR: $remaining"
