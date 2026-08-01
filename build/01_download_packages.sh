#!/usr/bin/env bash
#
# Standalone Arch Linux package downloader.
# Downloads packages and their dependencies using pacman.
#

set -euo pipefail

# --- Config ---
TEMP_DB="/tmp/blankdb_pacman_download"
SYS_LOCK="/var/lib/pacman/db.lck"

# --- Helpers ---
log() { echo "==> $*"; }
ok()  { echo "  ✓ $*"; }
err() { echo "  ✗ $*"; }

# --- Helper for commands that need root ---
run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# --- Detect project root (parent of builder/) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Args (optional — defaults to project layout) ---
PACKAGE_FILE="${1:-$PROJECT_ROOT/packages.x86_64}"
DOWNLOAD_DIR="${2:-$PROJECT_ROOT/downloads/official_packages}"

if [[ $# -gt 2 ]]; then
    echo "Usage: $0 [packages_file] [download_dir]"
    echo ""
    echo "Defaults:"
    echo "  packages_file  $PROJECT_ROOT/packages.x86_64"
    echo "  download_dir   $PROJECT_ROOT/downloads/official_packages"
    echo ""
    echo "Note: Script will request sudo when needed."
    exit 1
fi

if [[ ! -f "$PACKAGE_FILE" ]]; then
    echo "Error: Package list file not found: $PACKAGE_FILE"
    exit 1
fi

# --- Read packages ---
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

# --- Check which packages are already downloaded (with version match) ---
log "Checking for already downloaded packages..."

# Build a map of locally downloaded packages: name -> version
# Uses pacman -Qp for reliable parsing (handles epochs like 2:8.1.2-11)
declare -A LOCAL_VERSIONS
if [[ -d "$DOWNLOAD_DIR" ]]; then
    while IFS= read -r -d '' pkg_file; do
        read -r pkg_name pkg_version < <(pacman -Qp "$pkg_file" 2>/dev/null | head -1)
        [[ -z "$pkg_name" || -z "$pkg_version" ]] && continue
        # Store the latest version per package name
        if [[ -z "${LOCAL_VERSIONS[$pkg_name]:-}" || "$pkg_version" > "${LOCAL_VERSIONS[$pkg_name]}" ]]; then
            LOCAL_VERSIONS["$pkg_name"]="$pkg_version"
        fi
    done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -name '*.pkg.tar.zst' -print0 2>/dev/null)
fi

# Query repo for available versions and filter
NEED_DOWNLOAD=()
for pkg in "${PACKAGES[@]}"; do
    # Get the available version from the synced repos
    repo_version=$(run_as_root pacman -Si "$pkg" 2>/dev/null | grep '^Version' | awk '{print $2}')
    if [[ -z "$repo_version" ]]; then
        err "Could not find package '$pkg' in repos, forcing download"
        NEED_DOWNLOAD+=("$pkg")
        continue
    fi

    local_ver="${LOCAL_VERSIONS[$pkg]:-}"
    if [[ -n "$local_ver" && "$local_ver" == "$repo_version" ]]; then
        ok "Skipping $pkg (local=$local_ver, repo=$repo_version)"
    else
        if [[ -n "$local_ver" ]]; then
            log "Updating $pkg: $local_ver -> $repo_version"
        else
            log "Downloading $pkg (version $repo_version)"
        fi
        NEED_DOWNLOAD+=("$pkg")
    fi
done

if [[ ${#NEED_DOWNLOAD[@]} -eq 0 ]]; then
    ok "All ${#PACKAGES[@]} packages already downloaded"
    echo ""
    exit 0
fi

echo "Packages to download: ${#NEED_DOWNLOAD[@]}/${#PACKAGES[@]}"
echo ""

# --- Step 1: Remove lock files ---
log "Step 1: Removing lock files..."
for lock_path in "$SYS_LOCK" "$TEMP_DB/db.lck" "$TEMP_DB/sync/db.lock"; do
    if [[ -f "$lock_path" ]]; then
        rm -f "$lock_path" && ok "Removed $lock_path" || err "Permission denied removing $lock_path"
    fi
done
echo ""

# --- Step 2: Create temporary database ---
log "Step 2: Creating temporary database..."
mkdir -p "$TEMP_DB/sync" "$TEMP_DB/local"
ok "Temporary database created at $TEMP_DB"
echo ""

# --- Step 3: Sync system databases first (needed for dependency resolution) ---
log "Step 3: Syncing system package databases..."
run_as_root pacman -Sy --noconfirm --disable-sandbox
ok "System databases synced"

# --- Step 4: Copy synced databases to temp_db ---
log "Step 4: Preparing temporary database..."
cp -a /var/lib/pacman/sync/* "$TEMP_DB/sync/"
ok "Temporary database ready"
echo ""

# --- Step 5: Download packages ---
log "Step 5: Downloading ${#NEED_DOWNLOAD[@]} packages to $DOWNLOAD_DIR..."
mkdir -p "$DOWNLOAD_DIR"
chmod 777 "$DOWNLOAD_DIR"

run_as_root pacman --cachedir="$DOWNLOAD_DIR" --dbpath="$TEMP_DB" -Sw --noconfirm --disable-sandbox "${NEED_DOWNLOAD[@]}"

# --- Cleanup ---
rm -rf "$TEMP_DB"

# Remove old versions — keep only the latest version of each package
downloaded=()
while IFS= read -r -d '' f; do
    downloaded+=("$f")
done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -name '*.pkg.tar.zst' -print0 | sort -z)

log "Cleaning up old package versions..."
declare -A SEEN_VERSIONS  # pkg_name -> newest file path & version
for pkg_file in "${downloaded[@]}"; do
    read -r pkg_name pkg_version < <(pacman -Qp "$pkg_file" 2>/dev/null | head -1)
    [[ -z "$pkg_name" || -z "$pkg_version" ]] && continue

    if [[ -n "${SEEN_VERSIONS[$pkg_name]:-}" ]]; then
        # Compare versions — remove the older one
        older="${SEEN_VERSIONS[$pkg_name]}"
        older_ver="${SEEN_VERSIONS[${pkg_name}__ver]}"
        if [[ "$pkg_version" > "$older_ver" ]]; then
            rm -f "$older" && ok "Removed old: $(basename "$older")"
            SEEN_VERSIONS["$pkg_name"]="$pkg_file"
            SEEN_VERSIONS["${pkg_name}__ver"]="$pkg_version"
        else
            rm -f "$pkg_file" && ok "Removed old: $(basename "$pkg_file")"
        fi
    else
        SEEN_VERSIONS["$pkg_name"]="$pkg_file"
        SEEN_VERSIONS["${pkg_name}__ver"]="$pkg_version"
    fi
done

# --- Report ---
remaining=0
while IFS= read -r -d '' _; do ((remaining++)); done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -name '*.pkg.tar.zst' -print0 2>/dev/null)
echo ""
echo "============================================================"
echo "Done! Packages downloaded to $DOWNLOAD_DIR"
echo "Total packages in $DOWNLOAD_DIR: $remaining"
echo "============================================================"
echo ""




