#!/usr/bin/env bash
#
# Download AUR packages and their dependencies.
# - Resolves dependencies via AUR API
# - Downloads official dependencies to downloads/official_packages
# - Downloads AUR PKGBUILDs to downloads/aur_build
#

set -euo pipefail

# --- Config ---
AUR_API="https://aur.archlinux.org/rpc/v5"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/downloads/aur_build"
DOWNLOAD_SCRIPT="$SCRIPT_DIR/01_download_packages.sh"

# --- Helpers ---
log() { echo "==> $*"; }
ok()  { echo "  ✓ $*"; }
err() { echo "  ✗ $*"; }
warn() { echo "  ⚠ $*"; }

# --- Args (optional) ---
PACKAGE_FILE="${1:-$PROJECT_ROOT/packages.aur.x86_64}"

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [packages_file]"
    echo ""
    echo "Defaults:"
    echo "  packages_file  $PROJECT_ROOT/packages.aur.x86_64"
    echo ""
    echo "Note: Script will request sudo when needed."
    exit 1
fi

if [[ ! -f "$PACKAGE_FILE" ]]; then
    echo "Error: Package list file not found: $PACKAGE_FILE"
    exit 1
fi

# --- Read packages ---
mapfile -t INPUT_PACKAGES < <(grep -vE '^\s*#|^\s*$' "$PACKAGE_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ ${#INPUT_PACKAGES[@]} -eq 0 ]]; then
    echo "Error: No packages found in $PACKAGE_FILE"
    exit 1
fi

# --- AUR API function ---
aur_info() {
    local pkg="$1"
    curl -s "${AUR_API}/info?arg[]=$pkg" 2>/dev/null
}

# --- Get list of already downloaded packages ---
log "Scanning for already downloaded packages..."
declare -A DOWNLOADED_PKGS

# Check official packages directory
if [[ -d "$PROJECT_ROOT/downloads/official_packages" ]]; then
    while IFS= read -r -d '' pkg_file; do
        pkg_full=$(basename "$pkg_file" .pkg.tar.zst)
        pkg_name="${pkg_full%%-*}"
        DOWNLOADED_PKGS["$pkg_name"]=1
    done < <(find "$PROJECT_ROOT/downloads/official_packages" -maxdepth 1 -name '*.pkg.tar.zst' -print0 2>/dev/null)
fi

# Check AUR packages directory
if [[ -d "$PROJECT_ROOT/downloads/aur_packages" ]]; then
    while IFS= read -r -d '' pkg_file; do
        pkg_full=$(basename "$pkg_file" .pkg.tar.zst)
        pkg_name="${pkg_full%%-*}"
        DOWNLOADED_PKGS["$pkg_name"]=1
    done < <(find "$PROJECT_ROOT/downloads/aur_packages" -maxdepth 1 -name '*.pkg.tar.zst' -print0 2>/dev/null)
fi

ok "Found ${#DOWNLOADED_PKGS[@]} already downloaded packages"
echo ""

# --- Resolve dependencies recursively ---
log "Resolving dependencies..."

declare -A ALL_AUR_PKGS
declare -A AUR_PACKAGE_BASES
declare -A ALL_OFFICIAL_DEPS
declare -A VISITED
QUEUE=("${INPUT_PACKAGES[@]}")

while [[ ${#QUEUE[@]} -gt 0 ]]; do
    current="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")

    if [[ -n "${VISITED[$current]:-}" ]]; then
        continue
    fi
    VISITED["$current"]=1

    result=$(aur_info "$current")
    type=$(echo "$result" | jq -r '.type' 2>/dev/null)
    resultcount=$(echo "$result" | jq '.resultcount // 0' 2>/dev/null)

    if [[ "$type" != "multiinfo" ]] || [[ "$resultcount" -eq 0 ]]; then
        warn "Package '$current' not found in AUR, skipping"
        continue
    fi

    ALL_AUR_PKGS["$current"]=1
    pkgbase=$(echo "$result" | jq -r '.results[0].PackageBase // empty' 2>/dev/null)
    if [[ -n "$pkgbase" ]]; then
        AUR_PACKAGE_BASES["$current"]="$pkgbase"
    fi

    get_deps() {
        echo "$result" | jq -r ".results[0].$1[]? // empty" 2>/dev/null | sed 's/>.*//' | sed 's/=.*//' | sed 's/|.*$//'
    }

    process_dep() {
        local dep="$1"
        [[ -z "$dep" ]] && return
        [[ -n "${VISITED[$dep]:-}" ]] && return
        
        if [[ -n "${DOWNLOADED_PKGS[$dep]:-}" ]]; then
            VISITED["$dep"]=1
            return
        fi
        
        local dep_result dep_type dep_count
        dep_result=$(aur_info "$dep" 2>/dev/null)
        dep_type=$(echo "$dep_result" | jq -r '.type' 2>/dev/null)
        dep_count=$(echo "$dep_result" | jq '.resultcount // 0' 2>/dev/null)
        
        if [[ "$dep_type" == "multiinfo" ]] && [[ "$dep_count" -gt 0 ]]; then
            QUEUE+=("$dep")
        else
            ALL_OFFICIAL_DEPS["$dep"]=1
        fi
    }

    while IFS= read -r dep; do
        process_dep "$dep"
    done <<< "$(get_deps Depends)"
done

ok "Found ${#ALL_AUR_PKGS[@]} AUR packages"
ok "Found ${#ALL_OFFICIAL_DEPS[@]} official dependencies to download"
echo ""

# --- Download official dependencies ---
if [[ ${#ALL_OFFICIAL_DEPS[@]} -gt 0 ]]; then
    log "Downloading official dependencies..."
    
    OFFICIAL_DL_DIR="$PROJECT_ROOT/downloads/official_packages"
    mkdir -p "$OFFICIAL_DL_DIR"
    
    declare -A DOWNLOADED_PKGS
    if [[ -d "$OFFICIAL_DL_DIR" ]]; then
        while IFS= read -r -d '' pkg_file; do
            pkg_full=$(basename "$pkg_file" .pkg.tar.zst)
            pkg_name="${pkg_full%%-*}"
            DOWNLOADED_PKGS["$pkg_name"]=1
        done < <(find "$OFFICIAL_DL_DIR" -maxdepth 1 -name '*.pkg.tar.zst' -print0 2>/dev/null)
    fi
    
    NEED_DOWNLOAD=()
    for dep in "${!ALL_OFFICIAL_DEPS[@]}"; do
        if [[ -z "${DOWNLOADED_PKGS[$dep]:-}" ]]; then
            NEED_DOWNLOAD+=("$dep")
        fi
    done
    
    if [[ ${#NEED_DOWNLOAD[@]} -eq 0 ]]; then
        ok "All official dependencies already downloaded"
    else
        echo ""
        
        OFFICIAL_DEPS_FILE=$(mktemp)
        for dep in "${NEED_DOWNLOAD[@]}"; do
            echo "$dep"
        done > "$OFFICIAL_DEPS_FILE"
        
        if [[ -x "$DOWNLOAD_SCRIPT" ]]; then
            # download_packages.sh handles sudo and sync internally
            bash "$DOWNLOAD_SCRIPT" "$OFFICIAL_DEPS_FILE" "$OFFICIAL_DL_DIR"
        else
            warn "01_download_packages.sh not found, trying pacman directly..."
            pacman -Sw --cachedir="$OFFICIAL_DL_DIR" --noconfirm "${NEED_DOWNLOAD[@]}" 2>&1 || true
        fi
        
        rm -f "$OFFICIAL_DEPS_FILE"
        ok "Official dependencies downloaded to $OFFICIAL_DL_DIR"
    fi
    echo ""
fi

# --- Download PKGBUILDs for AUR packages ---
log "Downloading PKGBUILDs to $BUILD_DIR..."
mkdir -p "$BUILD_DIR"

aur_downloaded=0
aur_new=0
all_cached=true
for pkg in "${!ALL_AUR_PKGS[@]}"; do
    pkgbase="${AUR_PACKAGE_BASES[$pkg]:-$pkg}"
    pkg_dir="$BUILD_DIR/$pkg"
    
    if [[ -d "$pkg_dir" ]] && [[ -f "$pkg_dir/PKGBUILD" ]]; then
        ok "Already downloaded: $pkg"
        ((aur_downloaded++)) || true
    else
        all_cached=false
        snapshot_url="https://aur.archlinux.org/cgit/aur.git/snapshot/${pkgbase}.tar.gz"
        if curl -sL "$snapshot_url" -o "/tmp/${pkgbase}.tar.gz" 2>/dev/null; then
            mkdir -p "$pkg_dir"
            tar xzf "/tmp/${pkgbase}.tar.gz" -C "$pkg_dir" --strip-components=1 2>/dev/null || true
            rm -f "/tmp/${pkgbase}.tar.gz"
            ok "Downloaded: $pkg (base: $pkgbase)"
            ((aur_new++)) || true
        else
            warn "Failed to download: $pkg (may not exist in AUR)"
        fi
    fi
done
echo ""
ok "AUR sources: $aur_new new, $aur_downloaded already present"

if $all_cached; then
    log "All AUR sources already cached"
fi

# --- Report ---
echo ""
echo "============================================================"
echo "AUR Package Download Report"
echo "============================================================"
echo ""
echo "AUR packages ready to build: ${#ALL_AUR_PKGS[@]}"
echo "Official dependencies: ${#ALL_OFFICIAL_DEPS[@]}"
echo ""
echo "Next step: run 03_build_aur.sh to compile AUR packages"
echo ""
echo "AUR sources in: $BUILD_DIR"
echo "Official packages in: $PROJECT_ROOT/downloads/official_packages"
