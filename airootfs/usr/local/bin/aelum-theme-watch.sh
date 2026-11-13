#!/bin/bash
# Mirror the installer's light/dark toggle onto the live terminal palette.
#
# The installer switches hyprpaper between bg-light.png and bg-dark.png via
# `hyprctl hyprpaper wallpaper`. hyprpaper exposes the active wallpaper per
# output, so watching that is the same signal the toggle sends — no installer
# changes and no coupling to the GUI. When it changes, ask running foot
# instances to switch palette: foot keeps both themes in its config
# ([colors-dark] / [colors-light]) and selects one on SIGUSR1 (dark) or
# SIGUSR2 (light). Signalling the server instance also makes every window
# opened afterwards use the selected theme.
#
# Live ISO only: the installed system gets its colors from Dux Shell.
set -u

theme=""
applied=""

while :; do
    active="$(hyprctl hyprpaper listactive 2>/dev/null || true)"

    case "$active" in
        *bg-dark.png*) theme="dark" ;;
        *bg-light.png*) theme="light" ;;
        *) theme="" ;;
    esac

    if [[ -n "$theme" && "$theme" != "$applied" ]]; then
        case "$theme" in
            dark) pkill -USR1 -x foot 2>/dev/null || true ;;
            light) pkill -USR2 -x foot 2>/dev/null || true ;;
        esac
        applied="$theme"
    fi

    sleep 0.5
done
