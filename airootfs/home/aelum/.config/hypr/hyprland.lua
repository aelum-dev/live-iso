-------------------
--- MY PROGRAMS ---
-------------------

-- Set programs that you use
local terminal    = "kitty"

-------------------
---- AUTOSTART ----
-------------------

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:

hl.on("hyprland.start", function ()
     hl.exec_cmd("hyprpaper")
     -- Keep the live kitty palette in step with the installer's light/dark
     -- toggle by watching the active hyprpaper wallpaper.
     hl.exec_cmd("/usr/local/bin/aelum-theme-watch.sh")
     -- Scale the monitor BEFORE the installer maps its window. The installer is
     -- a floating window that Hyprland centers, so it must be created after the
     -- final scale is in effect: mapping it at scale 1.0 and rescaling the
     -- output afterwards leaves the window at its pre-scale logical position,
     -- pinned near the bottom-right corner (visible on 1440p/4K displays).
     hl.exec_cmd("/bin/sh -c '/usr/local/bin/auto-scale-monitor.sh; exec /usr/local/bin/aelum-installer'")
end)
-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 20,

        border_size = 0,
    },

    decoration = {
        rounding       = 28,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = false,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled   = false,
            size      = 3,
            passes    = 1,
            vibrancy  = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

hl.animation({ leaf = "windowsIn", enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "default" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 3, bezier = "default" })

----------------
----  MISC  ----
----------------

hl.config({
    misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true
	},
    ecosystem = {
		no_update_news = true
	}

})


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us",
        accel_profile = "flat",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = false,
        },
    },
})

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

hl.window_rule({
    name  = "installer",
    match = { class = "aelum-installer" },
    float = true,
})

require("dms.outputs")
