#!/usr/bin/env bash
#
# Step 2: Download AUR packages and their dependencies
# Usage: bash step-2.sh /project/root
#

set -euo pipefail

PROJECT_ROOT="${1:?Usage: $0 <project_root>}"
AUR_API="https://aur.archlinux.org/rpc/v5"
BUILD_DIR="${PROJECT_ROOT}/downloads/aur_build"
OFFICIAL_DL_DIR="${PROJECT_ROOT}/downloads/official_packages"

log() { echo "==> $*"; }
ok()  { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }

aur_info() {
    curl -s "${AUR_API}/info?arg[]=$1" 2>/dev/null
}

# Read AUR packages
PACKAGE_FILE="${PROJECT_ROOT}/packages.aur.x86_64"
if [[ ! -f "$PACKAGE_FILE" ]]; then
    echo "Error: AUR package list not found: $PACKAGE_FILE"
    exit 1
fi

mapfile -t INPUT_PACKAGES < <(grep -vE '^\s*#|^\s*$' "$PACKAGE_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Resolve AUR dependencies
declare -A ALL_AUR_PKGS
declare -A AUR_PACKAGE_BASES
declare -A ALL_OFFICIAL_DEPS
declare -A VISITED
QUEUE=("${INPUT_PACKAGES[@]}")

while [[ ${#QUEUE[@]} -gt 0 ]]; do
    current="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")
    
    [[ -n "${VISITED[$current]:-}" ]] && continue
    VISITED["$current"]=1
    
    result=$(aur_info "$current")
    type=$(echo "$result" | jq -r '.type' 2>/dev/null)
    resultcount=$(echo "$result" | jq '.resultcount // 0' 2>/dev/null)
    
    if [[ "$type" != "multiinfo" ]] || [[ "$resultcount" -eq 0 ]]; then
        warn "Not in AUR: $current"
        continue
    fi
    
    ALL_AUR_PKGS["$current"]=1
    pkgbase=$(echo "$result" | jq -r '.results[0].PackageBase // empty' 2>/dev/null)
    [[ -n "$pkgbase" ]] && AUR_PACKAGE_BASES["$current"]="$pkgbase"
    
    get_deps() {
        echo "$result" | jq -r ".results[0].$1[]? // empty" 2>/dev/null | sed 's/>.*//;s/=.*//;s/|.*$//'
    }
    
    process_dep() {
        local dep="$1"
        [[ -z "$dep" ]] && return
        [[ -n "${VISITED[$dep]:-}" ]] && return

        
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

ok "AUR packages: ${#ALL_AUR_PKGS[@]}"
ok "Official deps to download: ${#ALL_OFFICIAL_DEPS[@]}"

# Download official deps
if [[ ${#ALL_OFFICIAL_DEPS[@]} -gt 0 ]]; then
    log "Downloading official dependencies..."
    mkdir -p "$OFFICIAL_DL_DIR"
    
    pacman -Sw --cachedir="$OFFICIAL_DL_DIR" --noconfirm --disable-sandbox "${!ALL_OFFICIAL_DEPS[@]}" 2>/dev/null || true
    ok "Official dependencies downloaded"
fi

# Download AUR PKGBUILDs
log "Downloading AUR PKGBUILDs to $BUILD_DIR..."
mkdir -p "$BUILD_DIR"

aur_new=0
for pkg in "${!ALL_AUR_PKGS[@]}"; do
    pkgbase="${AUR_PACKAGE_BASES[$pkg]:-$pkg}"
    pkg_dir="$BUILD_DIR/$pkg"
    
    snapshot_url="https://aur.archlinux.org/cgit/aur.git/snapshot/${pkgbase}.tar.gz"
    if curl -sL "$snapshot_url" -o "/tmp/${pkgbase}.tar.gz" 2>/dev/null; then
        mkdir -p "$pkg_dir"
        tar xzf "/tmp/${pkgbase}.tar.gz" -C "$pkg_dir" --strip-components=1 2>/dev/null || true
        rm -f "/tmp/${pkgbase}.tar.gz"
        ok "Downloaded: $pkg"
        ((aur_new++)) || true
    else
        warn "Failed: $pkg"
    fi
done

echo ""
log "AUR sources ready: ${#ALL_AUR_PKGS[@]} packages"
