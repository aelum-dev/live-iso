-- outputs.lua — Auto-resolution detection with Hyprland scaling.
--
-- Detects connected monitor resolution at startup (and on hot-plug) and
-- applies the appropriate scale via hyprctl:
--
--   1080p (height ≤1080)  → scale 1.0
--   1440p (height ≤1440)  → scale 1.33
--   2160p (height ≤2160)  → scale 2.0
--   anything else         → scale 1.0 (safe default)

-- Run detection at Hyprland startup
hl.on("hyprland.start", function()
    hl.exec_cmd("bash /usr/local/bin/auto-scale-monitor.sh")
end)

-- Re-apply scaling when a new monitor is connected (hot-plug)
-- Event: monitor.added (Hyprland 0.55+ Lua API)
hl.on("monitor.added", function()
    hl.exec_cmd("bash /usr/local/bin/auto-scale-monitor.sh")
end)
