#!/bin/bash
#
# generate-hyprland-monitor-config.sh
# Detects monitor resolution before Hyprland starts and generates
# a monitors.lua config file with appropriate scaling.
#
# This script reads /sys/class/drm/ to detect connected monitors
# and their preferred resolutions, then generates a Lua config
# compatible with Hyprland 0.55+ (Lua configuration format).
#
# Usage: Run as root before greetd/Hyprland starts.
#        HOME must be set to /home/aestheticos.
#

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

# Output config directory
HYPR_CONFIG_DIR="${HOME}/.config/hypr"
MONITORS_LUA="${HYPR_CONFIG_DIR}/monitors.lua"
TEMP_LUA="${MONITORS_LUA}.tmp.$$"

# Owner for the generated config file
CONFIG_OWNER="aestheticos"
CONFIG_GROUP="aestheticos"

# ─── Validation ──────────────────────────────────────────────────────────────

if [[ -z "${HOME:-}" ]]; then
    echo "✗ ERROR: HOME environment variable is not set." >&2
    echo "  This script must run with HOME=/home/aestheticos" >&2
    exit 1
fi

# Validate HOME points to a real user directory
if [[ ! -d "${HOME}" ]]; then
    echo "✗ ERROR: HOME directory '${HOME}' does not exist." >&2
    exit 1
fi

# ─── Helper Functions ────────────────────────────────────────────────────────

# Calculate scale factor based on resolution height
calculate_scale() {
    local width=$1
    local height=$2

    # Validate inputs are numeric
    if ! [[ "${width}" =~ ^[0-9]+$ ]] || ! [[ "${height}" =~ ^[0-9]+$ ]]; then
        echo "1"
        return
    fi

    # Scale based on resolution height
    if [ "${height}" -ge 2160 ]; then
        echo "2"
    elif [ "${height}" -ge 1440 ]; then
        echo "1.33"
    else
        echo "1"
    fi
}

# Get the preferred resolution from a DRM modes file
# Returns the first (preferred) mode as-is without rounding
get_preferred_resolution() {
    local modes_file=$1
    local raw_mode

    # Ensure file is non-empty
    if [[ ! -s "${modes_file}" ]]; then
        echo ""
        return 1
    fi

    raw_mode=$(head -n 1 "${modes_file}" | tr -d '[:space:]')

    # Validate format: WIDTHxHEIGHT
    if [[ ! "${raw_mode}" =~ ^[0-9]+x[0-9]+$ ]]; then
        echo ""
        return 1
    fi

    echo "${raw_mode}"
}

# Get monitor output name from DRM connector path
# Extracts the connector name (e.g., "HDMI-A-1", "eDP-1")
get_monitor_name() {
    local connector_dir=$1
    # The directory name is like "card1-HDMI-A-1" or "card0-eDP-1"
    # We want everything after the last dash
    local dir_name
    dir_name=$(basename "${connector_dir}")
    echo "${dir_name#*-}"
}

# ─── Config Generation ──────────────────────────────────────────────────────

generate_config() {
    local position_x=0
    local first=true
    local found=false

    # Scan all DRM connectors
    for connector in /sys/class/drm/card*-*/; do
        # Skip if glob didn't match (no connectors)
        [[ -d "${connector}" ]] || continue

        local status_file="${connector}status"
        local modes_file="${connector}modes"

        # Check if status file exists and is readable
        [[ -f "${status_file}" ]] || continue

        # Check if monitor is connected
        local status
        status=$(cat "${status_file}" 2>/dev/null) || continue
        # Trim whitespace
        status=$(echo "${status}" | tr -d '[:space:]')
        [[ "${status}" == "connected" ]] || continue

        # Modes file may or may not exist (some drivers omit it)
        if [[ ! -f "${modes_file}" ]]; then
            echo "  [WARN] No modes file for ${connector}, skipping" >&2
            continue
        fi

        local monitor_name
        monitor_name=$(get_monitor_name "${connector}")

        local resolution
        resolution=$(get_preferred_resolution "${modes_file}") || continue

        # Skip if we couldn't parse a valid resolution
        if [[ -z "${resolution}" ]]; then
            echo "  [WARN] Could not parse resolution for ${monitor_name}, skipping" >&2
            continue
        fi

        # Parse resolution into width and height
        local width height
        width="${resolution%%x*}"
        height="${resolution##*x}"

        # Validate parsed values
        if ! [[ "${width}" =~ ^[0-9]+$ ]] || ! [[ "${height}" =~ ^[0-9]+$ ]]; then
            echo "  [WARN] Invalid resolution '${resolution}' for ${monitor_name}, skipping" >&2
            continue
        fi

        local scale
        scale=$(calculate_scale "${width}" "${height}")

        # Calculate position (stack monitors horizontally)
        local position="${position_x}x0"

        # Update position for next monitor
        position_x=$((position_x + width))

        # Add comma separator between monitors
        if [[ "${first}" == true ]]; then
            first=false
        else
            printf ',\n'
        fi

        printf 'hl.monitor({\n'
        printf '  output = "%s",\n' "${monitor_name}"
        printf '  mode = "%s",\n' "${resolution}"
        printf '  position = "%s",\n' "${position}"
        printf '  scale = %s,\n' "${scale}"
        printf '})'

        found=true
    done

    # If no monitors found, use a fallback with auto-detection
    if [[ "${found}" == false ]]; then
        printf 'hl.monitor({\n'
        printf '  output = "",\n'
        printf '  mode = "preferred",\n'
        printf '  position = "auto",\n'
        printf '  scale = 1,\n'
        printf '})'
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

# Create config directory if it doesn't exist
mkdir -p "${HYPR_CONFIG_DIR}"

# Use flock to prevent concurrent execution (lock file in same directory)
exec 200>"${MONITORS_LUA}.lock"
if ! flock -n 200; then
    echo "✗ ERROR: Another instance of this script is already running." >&2
    exit 1
fi

echo "Generating Hyprland monitor configuration..."

# Write to temp file first (atomic write)
{
    echo "-- Auto-generated monitor configuration"
    echo "-- Generated by generate-hyprland-monitor-config.sh"
    echo "-- Generated on: $(date)"
    echo ""
    generate_config
} > "${TEMP_LUA}"

# Move temp file to final location (atomic on same filesystem)
mv "${TEMP_LUA}" "${MONITORS_LUA}"

# Set correct ownership and permissions
# This ensures the aestheticos user can read the config
if id "${CONFIG_OWNER}" &>/dev/null; then
    chown "${CONFIG_OWNER}:${CONFIG_GROUP}" "${MONITORS_LUA}" 2>/dev/null || true
fi
chmod 644 "${MONITORS_LUA}"

# Print summary
echo "✓ Monitor configuration generated: ${MONITORS_LUA}"
echo ""

# Count detected monitors
monitor_count=$(grep -c 'output = "' "${MONITORS_LUA}" 2>/dev/null || echo "0")
if [[ "${monitor_count}" -gt 0 ]]; then
    echo "Detected ${monitor_count} monitor(s):"
    grep -E '^\s+output = "' "${MONITORS_LUA}" | sed 's/^/  /'
    echo ""
    echo "Configuration:"
    cat "${MONITORS_LUA}" | sed 's/^/  /'
else
    echo "⚠ No monitors detected. Fallback auto-detection config written."
    echo ""
    echo "Configuration:"
    cat "${MONITORS_LUA}" | sed 's/^/  /'
fi

# Cleanup lock file (flock releases it on fd close)
rm -f "${MONITORS_LUA}.lock"
