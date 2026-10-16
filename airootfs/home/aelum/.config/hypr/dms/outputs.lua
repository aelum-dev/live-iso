-- outputs.lua — Auto-resolution detection with Hyprland scaling.
--
-- Detects connected monitor resolution and applies the appropriate scale via
-- hyprctl:
--
--   1080p (height ≤1080)  → scale 1.0
--   1440p (height ≤1440)  → scale 1.33
--   2160p (height ≤2160)  → scale 2.0
--   anything else         → scale 1.0 (safe default)
--
-- There is deliberately no hyprland.start handler here. The startup case is
-- handled by hyprland.lua, which runs the script to completion before it
-- starts the installer, so the installer's window is created at the final
-- scale. Firing the script here as well would race that gate.
--
-- Re-apply scaling when a new monitor is connected (hot-plug)
-- Event: monitor.added (Hyprland 0.55+ Lua API)
hl.on("monitor.added", function()
    hl.exec_cmd("bash /usr/local/bin/auto-scale-monitor.sh")
end)
