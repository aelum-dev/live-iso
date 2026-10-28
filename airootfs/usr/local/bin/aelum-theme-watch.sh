#!/bin/bash
# Mirror the installer's light/dark toggle onto the live kitty palette.
#
# The installer switches hyprpaper between bg-light.png and bg-dark.png via
# `hyprctl hyprpaper wallpaper`. hyprpaper exposes the active wallpaper per
# output, so watching that is the same signal the toggle sends — no installer
# changes and no coupling to the GUI. When it changes, copy the matching palette
# over kitty's theme include and ask running kitty instances to reload their
# config (SIGUSR1).
#
# Live ISO only: the installed system gets its colors from Dux Shell.
set -u

kitty_dir="${HOME}/.config/kitty"
active_theme="${kitty_dir}/theme.conf"
applied=""

apply() {
    local theme="$1"
    local source="${kitty_dir}/theme-${theme}.conf"

    [[ -d "$kitty_dir" && -r "$source" ]] || return 0
    cp -f "$source" "$active_theme" || return 0
    pkill -USR1 -x kitty 2>/dev/null || true
}

while :; do
    active="$(hyprctl hyprpaper listactive 2>/dev/null || true)"

    case "$active" in
        *bg-dark.png*) theme="dark" ;;
        *bg-light.png*) theme="light" ;;
        *) theme="" ;;
    esac

    if [[ -n "$theme" && "$theme" != "$applied" ]]; then
        apply "$theme"
        applied="$theme"
    fi

    sleep 0.5
done
