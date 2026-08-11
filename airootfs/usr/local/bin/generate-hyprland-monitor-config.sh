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

set -euo pipefail

# Output config directory
HYPR_CONFIG_DIR="${HOME}/.config/hypr"
MONITORS_LUA="${HYPR_CONFIG_DIR}/monitors.lua"

# Create config directory if it doesn't exist
mkdir -p "${HYPR_CONFIG_DIR}"

# Function to calculate scale based on resolution
# Rounds to nearest standard resolution before calculating scale
calculate_scale() {
    local width=$1
    local height=$2

    # Round to nearest standard resolution for scaling calculation
    # This handles non-standard resolutions (like VM adaptations)
    local rounded_height=${height}
    
    # Round to nearest standard height
    if [ "${height}" -ge 2100 ]; then
        rounded_height=2160  # 4K
    elif [ "${height}" -ge 1350 ]; then
        rounded_height=1440  # 2K
    elif [ "${height}" -ge 1000 ]; then
        rounded_height=1080  # 1080p
    elif [ "${height}" -ge 700 ]; then
        rounded_height=720   # 720p
    fi

    # Calculate scale based on rounded resolution height
    if [ "${rounded_height}" -ge 2160 ]; then
        echo "2"
    elif [ "${rounded_height}" -ge 1440 ]; then
        echo "1.25"
    else
        echo "1"
    fi
}

# Function to get preferred resolution (first mode is usually preferred)
# Rounds to nearest standard resolution for compatibility
get_preferred_resolution() {
    local modes_file=$1
    local raw_mode
    raw_mode=$(head -n 1 "${modes_file}")
    
    local width height
    width=$(echo "${raw_mode}" | cut -d'x' -f1)
    height=$(echo "${raw_mode}" | cut -d'x' -f2)
    
    # Round to nearest standard resolution
    # This ensures scale factors divide cleanly
    local std_width=${width}
    local std_height=${height}
    
    # Round height to standard values
    if [ "${height}" -ge 2100 ]; then
        std_height=2160
    elif [ "${height}" -ge 1350 ]; then
        std_height=1440
    elif [ "${height}" -ge 1000 ]; then
        std_height=1080
    elif [ "${height}" -ge 700 ]; then
        std_height=720
    fi
    
    # Round width proportionally (keep aspect ratio ~16:9)
    case "${std_height}" in
        2160) std_width=3840 ;;
        1440) std_width=2560 ;;
        1080) std_width=1920 ;;
        720)  std_width=1280 ;;
    esac
    
    echo "${std_width}x${std_height}"
}

# Function to get monitor name from connector path
get_monitor_name() {
    local connector_dir=$1
    basename "${connector_dir}" | sed 's/^[^-]*-//'
}

# Generate monitors.lua configuration
generate_config() {
    local position_x=0
    local position_y=0
    local first=true
    local found=false

    # Scan all DRM connectors
    for connector in /sys/class/drm/card*-*/; do
        # Skip non-connector directories (e.g., card1, renderD128)
        [[ -d "${connector}" ]] || continue

        local status_file="${connector}status"
        local modes_file="${connector}modes"

        # Check if files exist
        [[ -f "${status_file}" ]] || continue
        [[ -f "${modes_file}" ]] || continue

        # Check if monitor is connected
        local status
        status=$(cat "${status_file}" 2>/dev/null) || continue
        [[ "${status}" == "connected" ]] || continue

        local monitor_name
        monitor_name=$(get_monitor_name "${connector}")
        local resolution
        resolution=$(get_preferred_resolution "${modes_file}")

        # Parse resolution into width and height
        local width height
        width=$(echo "${resolution}" | cut -d'x' -f1)
        height=$(echo "${resolution}" | cut -d'x' -f2)

        local scale
        scale=$(calculate_scale "${width}" "${height}")

        # Calculate position (stack monitors horizontally)
        local position="${position_x}x${position_y}"

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

# Write to file with header and generated config
{
    echo "-- Auto-generated monitor configuration"
    echo "-- Generated by generate-hyprland-monitor-config.sh"
    echo "-- Generated on: $(date)"
    echo ""
    generate_config
} > "${MONITORS_LUA}"

echo "✓ Monitor configuration generated: ${MONITORS_LUA}"
echo ""
echo "Detected monitors:"
grep -E "^\s+(output|mode|scale)" "${MONITORS_LUA}" | sed 's/^/  /'
