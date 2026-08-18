#!/usr/bin/env bash
#
# auto-scale-monitor.sh — Detect connected monitor resolution and apply
# Hyprland scaling automatically via hyprctl.
#
# Scaling rules (based on native resolution height):
#   1080p (height ≤1080)  → scale 1.0
#   1440p (height ≤1440)  → scale 1.33
#   2160p (height ≤2160)  → scale 2.0
#   anything else         → scale 1.0 (safe default)
#
# Usage: Called from hyprland.lua autostart via hl.exec_cmd().
# No arguments needed — it queries hyprctl for connected monitors.

set -euo pipefail

LOG_FILE="/tmp/auto-scale-monitor.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }

# Function: determine scale factor from resolution height
detect_scale() {
    local height="$1"

    # Normalize: strip any non-numeric characters
    height=$(echo "$height" | grep -oE '[0-9]+')

    if [ -z "$height" ]; then
        echo "1"
        return
    fi

    if [ "$height" -le 1080 ]; then
        echo "1"
    elif [ "$height" -le 1440 ]; then
        echo "1.33"
    elif [ "$height" -le 2160 ]; then
        echo "2"
    else
        # For ultrawide or other resolutions, use 1.0 as safe default
        echo "1"
    fi
}

# We need Hyprland running to query monitors via hyprctl.
if ! command -v hyprctl &>/dev/null; then
    log "hyprctl not found, skipping"
    exit 0
fi

# Small initial delay to ensure Hyprland IPC is fully initialized
sleep 1

# Wait for Hyprland IPC to be ready (max 10 attempts, 0.5s apart)
log "waiting for Hyprland IPC..."
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if hyprctl monitors -j >/dev/null 2>&1; then
        log "IPC ready on attempt ${attempt}"
        break
    fi
    if [ "$attempt" -eq 10 ]; then
        log "IPC not ready after 10 attempts, skipping"
        exit 0
    fi
    sleep 0.5
done

# Get monitor data as JSON
MONITOR_JSON=$(hyprctl monitors -j 2>/dev/null || echo "[]")

# If no monitors detected, nothing to do
if [ "$MONITOR_JSON" = "[]" ] || [ -z "$MONITOR_JSON" ]; then
    log "no monitors detected, skipping"
    exit 0
fi

# Check if jq is available
if ! command -v jq &>/dev/null; then
    log "jq not found, skipping"
    exit 0
fi

MONITOR_COUNT=$(echo "$MONITOR_JSON" | jq 'length')
log "detected ${MONITOR_COUNT} monitor(s)"

# Track if we've set the primary monitor position
primary_set=false

for ((i = 0; i < MONITOR_COUNT; i++)); do
    # Extract monitor properties
    OUTPUT_NAME=$(echo "$MONITOR_JSON" | jq -r ".[$i].name")
    WIDTH=$(echo "$MONITOR_JSON" | jq -r ".[$i].width")
    HEIGHT=$(echo "$MONITOR_JSON" | jq -r ".[$i].height")
    REFRESH=$(echo "$MONITOR_JSON" | jq -r ".[$i].refreshRate // 60")
    IS_PRIMARY=$(echo "$MONITOR_JSON" | jq -r ".[$i].main")
    X_POS=$(echo "$MONITOR_JSON" | jq -r ".[$i].x")
    Y_POS=$(echo "$MONITOR_JSON" | jq -r ".[$i].y")

    # Determine scale based on height
    SCALE=$(detect_scale "$HEIGHT")

    # Build position: primary at 0x0, others at their current position
    if [ "$IS_PRIMARY" = "true" ] || [ "$primary_set" = false ]; then
        POSITION="0x0"
        primary_set=true
    else
        POSITION="${X_POS}x${Y_POS}"
    fi

    # Build the mode string (resolution@refresh)
    MODE="${WIDTH}x${HEIGHT}@${REFRESH}"

    # Apply via hyprctl eval (Hyprland 0.55+ Lua API)
    hyprctl eval "hl.monitor({output='${OUTPUT_NAME}', mode='${MODE}', position='${POSITION}', scale=${SCALE}})" 2>/dev/null && \
        log "${OUTPUT_NAME}: ${MODE} scale=${SCALE} pos=${POSITION}" || \
        log "WARNING: failed to set ${OUTPUT_NAME}"
done

log "done"
