#!/usr/bin/env bash
#
# Standalone Arch Linux package downloader.
# Downloads packages and ALL their dependencies (recursively) from the remote repo.
# Redownloads any package in the download dir whose version no longer matches the repo.
#

set -euo pipefail

# --- Config ---
TEMP_DB="/tmp/blankdb_pacman_download"
SYS_LOCK="/var/lib/pacman/db.lck"

# --- Helpers ---
log() { echo "==> $*"; }
ok()  { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }
err() { echo "  ✗ $*"; }

run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# --- Detect project root ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PACKAGE_FILE="${1:-$PROJECT_ROOT/packages.x86_64}"
DOWNLOAD_DIR="${2:-$PROJECT_ROOT/downloads/official_packages}"

if [[ $# -gt 2 ]]; then
    echo "Usage: $0 [packages_file] [download_dir]"
    echo ""
    echo "Defaults:"
    echo "  packages_file  $PROJECT_ROOT/packages.x86_64"
    echo "  download_dir   $PROJECT_ROOT/downloads/official_packages"
    exit 1
fi

if [[ ! -f "$PACKAGE_FILE" ]]; then
    echo "Error: Package list file not found: $PACKAGE_FILE"
    exit 1
fi

# --- Read packages (skip comments and blank lines) ---
mapfile -t PACKAGES < <(grep -vE '^\s*#|^\s*$' "$PACKAGE_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "Error: No packages found in $PACKAGE_FILE"
    exit 1
fi

echo "============================================================"
echo "Arch Linux Package Downloader"
echo "============================================================"
echo ""
echo "Packages file:  $PACKAGE_FILE"
echo "Download dir:   $DOWNLOAD_DIR"
echo ""

# --- Sync system databases ---
log "Syncing system package databases..."
run_as_root pacman -Sy --noconfirm --disable-sandbox 2>/dev/null
ok "System databases synced"
echo ""

# --- Prepare temp database for download ---
mkdir -p "$TEMP_DB/sync" "$TEMP_DB/local"

# Remove lock files
for lock_path in "$SYS_LOCK" "$TEMP_DB/db.lck" "$TEMP_DB/sync/db.lock"; do
    [[ -f "$lock_path" ]] && rm -f "$lock_path"
done

# Copy synced databases to temp db
cp -a /var/lib/pacman/sync/* "$TEMP_DB/sync/"
ok "Temporary database ready"
echo ""

# --- Resolve full dependency tree using pacman itself ---
# pacman -Sp resolves all deps natively and prints package names
# We use --print-format to get just the names
log "Resolving full dependency tree (delegating to pacman)..."

RESOLVED_FILE=$(mktemp)
trap "rm -f '$RESOLVED_FILE'" EXIT

for pkg in "${PACKAGES[@]}"; do
    # Use pacman -Sp to simulate sync and print package names
    # This resolves the complete dependency tree automatically
    run_as_root pacman --dbpath="$TEMP_DB" -Sp --print-format "%n" "$pkg" 2>/dev/null >> "$RESOLVED_FILE"
done

sort -u "$RESOLVED_FILE" -o "$RESOLVED_FILE"

if [[ ! -s "$RESOLVED_FILE" ]]; then
    err "No packages resolved. Aborting."
    exit 1
fi

mapfile -t ALL_PKGS < "$RESOLVED_FILE"
log "Resolved ${#ALL_PKGS[@]} packages (${#PACKAGES[@]} main + $(( ${#ALL_PKGS[@]} - ${#PACKAGES[@]} )) dependencies)"
echo ""

# --- Get expected versions from repo for all resolved packages ---
log "Checking package versions against repository..."

VERSION_FILE=$(mktemp)
trap "rm -f '$RESOLVED_FILE' '$VERSION_FILE'" EXIT

# Get name-version pairs from repo for all packages
run_as_root pacman --dbpath="$TEMP_DB" -Sp --print-format "%n-%v" "${ALL_PKGS[@]}" 2>/dev/null > "$VERSION_FILE"

# Build associative array: pkg_name -> expected_version
# Uses pacman's own parsing to avoid regex issues with version strings
declare -A EXPECTED_VERSIONS
while IFS= read -r line; do
    # Format: name-version (where version may contain dashes, e.g., 20260810-1 or 6.18.43-3)
    # Split on the LAST dash that is followed by a digit (pkgrel boundary)
    # Use pacman -Qi style: we know the format is name-version
    # Extract version: everything after the first dash that starts a version-like pattern
    if [[ "$line" =~ ^([a-zA-Z0-9._+-]+)-([0-9][^-]*-[0-9]+)$ ]]; then
        pkg_name="${BASH_REMATCH[1]}"
        expected_ver="${BASH_REMATCH[2]}"
        EXPECTED_VERSIONS["$pkg_name"]="$expected_ver"
    fi
done < "$VERSION_FILE"

# --- Clean up outdated packages in download directory ---
log "Checking for outdated packages in $DOWNLOAD_DIR..."
removed_count=0
orphan_count=0

for existing_pkg in "$DOWNLOAD_DIR"/*.pkg.tar.zst; do
    [[ -f "$existing_pkg" ]] || continue
    
    # Use pacman -Qp to reliably extract name and version from the package file
    read -r pkg_name pkg_ver < <(pacman -Qp "$existing_pkg" 2>/dev/null) || continue
    
    # Check if this package is in our current resolved list
    if [[ -z "${EXPECTED_VERSIONS[$pkg_name]+x}" ]]; then
        # Not in current list - orphan from previous run, remove it
        warn "Orphan: $(basename "$existing_pkg") (not in current package list)"
        rm -f "$existing_pkg" "$existing_pkg.sig"
        orphan_count=$((orphan_count + 1))
        continue
    fi
    
    expected_ver="${EXPECTED_VERSIONS[$pkg_name]}"
    
    # Compare versions - if they differ, remove the outdated package
    if [[ "$pkg_ver" != "$expected_ver" ]]; then
        warn "Outdated: $(basename "$existing_pkg") (repo has $expected_ver)"
        rm -f "$existing_pkg" "$existing_pkg.sig"
        removed_count=$((removed_count + 1))
    fi
done

if (( removed_count > 0 || orphan_count > 0 )); then
    msg="Removed $removed_count outdated package(s)"
    (( orphan_count > 0 )) && msg+=" + $orphan_count orphan(s)"
    ok "$msg"
else
    ok "No outdated packages found"
fi
echo ""

# --- Download all resolved packages ---
mkdir -p "$DOWNLOAD_DIR"
chmod 777 "$DOWNLOAD_DIR"

log "Downloading ${#ALL_PKGS[@]} packages to $DOWNLOAD_DIR..."
run_as_root pacman --cachedir="$DOWNLOAD_DIR" --dbpath="$TEMP_DB" -Sw --noconfirm --disable-sandbox "${ALL_PKGS[@]}"
ok "Download complete"
echo ""

# --- Cleanup temp database ---
rm -rf "$TEMP_DB"

# --- Final report ---
remaining=0
while IFS= read -r -d '' _; do ((remaining++)); done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -name '*.pkg.tar.zst' -print0 2>/dev/null)
echo ""
echo "============================================================"
echo "Done! Packages in $DOWNLOAD_DIR: $remaining"
echo "  Main packages:       ${#PACKAGES[@]}"
echo "  Total (incl. deps):  ${#ALL_PKGS[@]}"
echo "============================================================"
echo ""
