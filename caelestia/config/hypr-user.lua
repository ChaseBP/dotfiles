-- User Hyprland configuration for Caelestia

local bin = os.getenv("HOME") .. "/.local/bin/"

-- Background daemons start when the session is up, never while this file is first
-- parsed: at that point the Wayland socket isn't accepting clients yet, and Qt and
-- D-Bus clients abort on the spot. Until 2026-10-19 that killed iio-hyprland, wvkbd
-- and the resident palette at every login; they came back only at the next config
-- reload. A reload re-runs the guarded command, so a daemon that died comes back
-- then too. Every command must be idempotent (pgrep guard, or `start` semantics).
local function daemon(cmd)
    hl.on("hyprland.start", function() hl.exec_cmd(cmd) end)
    hl.on("config.reloaded", function() hl.exec_cmd(cmd) end)
end

-- Machine-specific facts (internal panel, 2-in-1 hinge, GPU) live in host.lua beside
-- this file. The dotfiles installer generates it from the hardware it finds; it is
-- NOT tracked, so edit it freely. No host.lua = plain desktop: the hardware blocks
-- below all stay off.
local host = {}
do
    local ok, h = pcall(require, "host")
    if ok and type(h) == "table" then host = h end
end

-- Apps that honour $TERMINAL (and the xdg terminal fallbacks) open Ghostty.
hl.env("TERMINAL", "ghostty")

-- NVIDIA as the only GPU: Hyprland's documented env. Drivers come from the CachyOS
-- installer (chwd); hybrid laptops render on the iGPU and need none of this.
if host.nvidia then
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
end

-- XWayland apps (Steam, every Proton game) render at native pixels. Without this,
-- at scale 1.25 XWayland advertises a 1536x864 screen: games render at that and get
-- stretched (blurry), and the in-game cursor drifts off what it is pointing at.
hl.config({ xwayland = { force_zero_scaling = true } })
-- ...which leaves Steam's own client UI at 1x (tiny); have it scale itself instead.
hl.env("STEAM_FORCE_DESKTOPUI_SCALING", "1.25")
-- Windowed games float at the size they asked for. Tiled, Hyprland squeezes a fixed-size
-- X11 game window into the tile: the picture is cut off and the cursor no longer lines up
-- with what the game thinks it is pointing at. (Upstream only tags them opaque/tearing.)
hl.window_rule({ match = { class = "steam_app_[0-9]+|steam_app_default" }, float = true, center = true })

-- Ensure Ghostty window rules: 100% opaque, zero transparency
hl.window_rule({ match = { class = "com.mitchellh.ghostty" }, opaque = true, opacity = "1.0 override 1.0 override" })
hl.window_rule({ match = { class = "ghostty" }, opaque = true, opacity = "1.0 override 1.0 override" })

-- Wallpaper switcher (sumi-e set) -- see ~/.local/bin/wall
-- SUPER+SHIFT+W opens a thumbnail picker; press again to dismiss (matches the
-- clipboard/emoji picker pattern). SUPER+ALT+W jumps to a random one.
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("pkill fuzzel || " .. bin .. "wall"))
hl.bind("SUPER + ALT + W", hl.dsp.exec_cmd(bin .. "wall random"))

-- XP-Pen's driver window (XWayland) floats, centred. Qt moves it back to its saved
-- position right after it maps (overriding a `center` rule), and that position can be
-- half off-screen, so re-centre it a moment after it opens.
hl.window_rule({ match = { class = "PenTablet" }, float = true, center = true })
hl.on("window.open", function(win)
    if win and win.class == "PenTablet" then
        hl.exec_cmd("sleep 0.6; hyprctl dispatch 'hl.dsp.window.center({ window = \"address:"
            .. win.address .. "\" })'")
    end
end)

-- Pen / note-taking apps: strip every compositor effect that adds frame latency.
-- Window opacity (0.95 by default) is the important one -- a translucent window
-- can never be "solitary", so Hyprland is forced into a full blur+composite pass
-- every frame instead of handing the buffer straight to the display.
-- Check with: hyprctl monitors | grep -E "solitary|directScanout|tearing"
local pen_apps = "xournalpp|com.github.flxzt.rnote|rnote|krita"

hl.window_rule({
    match        = { class = pen_apps },
    opaque       = true,
    opacity      = "1.0 override 1.0 override",
    no_blur      = true,
    no_shadow    = true,
    no_dim       = true,
    no_anim      = true,
    immediate    = true,  -- allow tearing: shaves up to one 16.7ms frame
    idle_inhibit = "always",
})

-- Required for the `immediate` rule above to do anything.
hl.config({ general = { allow_tearing = true } })

-- Auto-mount removable media. udiskie talks to udisks2 over D-Bus and relies on
-- the polkit agent (started in execs.lua) to mount without prompting for a password.
-- --no-tray because caelestia's bar owns the tray; notifications come from the shell.
-- pgrep-guarded: reloads re-run it (Hyprland auto-reloads on each save), and the
-- unguarded version had stacked up 29 copies.
daemon("pgrep -x udiskie >/dev/null || udiskie --no-tray --automount --notify --file-manager thunar")

-- ===========================================================================
-- 2-in-1 / tablet mode -- every block is gated on host.lua, so a desktop or a
-- plain laptop gets none of it. On the Latitude 7390 2-in-1: Wacom pen + touch
-- on eDP-1, Intel hinge sensor (INT33D6) as the "Intel Virtual Switches" device.
-- ===========================================================================

-- Pin the built-in digitisers to the internal panel, so the pen does not stretch
-- across an external display and rotation applies to input as well as the screen.
-- Per device on purpose: a global input:tablet:output would also capture an
-- external drawing tablet (the XP-Pen registers as a tablet too).
if host.panel then
    for _, name in ipairs(host.screen_inputs or {}) do
        hl.device({ name = name, output = host.panel })
    end
end

-- Auto-rotate: iio-hyprland listens to iio-sensor-proxy over D-Bus and rotates
-- the panel together with the mapped input devices.
if host.auto_rotate then
    daemon("pgrep -x iio-hyprland >/dev/null || iio-hyprland")
end

-- On-screen keyboard, started hidden. squeekboard was the wrong pick: it is built
-- for Phosh, wants org.gnome.SessionManager, and only surfaces via input-method-v2.
-- wvkbd is a plain wlroots layer-shell keyboard toggled with SIGUSR1/SIGUSR2.
if host.osk then
    daemon("pgrep -x wvkbd-mobintl >/dev/null || wvkbd-mobintl -L 320 --hidden")
    -- Manual OSK toggle, for when you want it without folding the screen.
    hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd(bin .. "osk toggle"))
end

-- Folding the screen back flips SW_TABLET_MODE on the hinge switch: disable the
-- internal keyboard + touchpad and show the OSK; unfolding reverses it.
-- NOTE: hl.bind takes exactly (key, action, flags) - the switch selector IS the
-- key. Passing an extra leading "" silently registers nothing.
-- Device enable/disable goes through hl.device, not `hyprctl keyword`, which
-- refuses to run against the Lua parser.
if host.tablet_switch then
    local function tablet_mode(on)
        local cmds = {}
        for _, name in ipairs(host.tablet_off or {}) do
            cmds[#cmds + 1] = "hyprctl eval 'hl.device({ name = \"" .. name .. "\", enabled = "
                .. tostring(not on) .. " })'"
        end
        if host.osk then cmds[#cmds + 1] = bin .. "osk " .. (on and "show" or "hide") end
        return table.concat(cmds, " ; ")
    end
    hl.bind("switch:on:" .. host.tablet_switch, hl.dsp.exec_cmd(tablet_mode(true)), { locked = true })
    hl.bind("switch:off:" .. host.tablet_switch, hl.dsp.exec_cmd(tablet_mode(false)), { locked = true })
end


-- Clipboard: keep password-manager entries out of cliphist.
-- execs.lua starts the stock watcher and there is no supported way to suppress it
-- (no cliphist toggle exists in hypr-vars.lua), so replace it here instead of editing
-- ~/.config/hypr/, which the README forbids and which conflicts on every update.
-- Patterns are ^-anchored: unanchored, `pkill -f` matched this very sh -c command line
-- (it contains the pattern) and killed it before wl-paste started, so text never
-- reached the history. The pgrep guard keeps config reloads from stacking watchers.
hl.exec_cmd("pkill -f '^wl-paste --type text --watch cliphist store'; "
    .. "pgrep -f '^wl-paste --type text --watch .*cliphist-store' >/dev/null || "
    .. "wl-paste --type text --watch " .. bin .. "cliphist-store")

-- Personal daily workflows. All custom logic lives beside these user configs.
local workflows = "python3 " .. string.format("%q", os.getenv("HOME") .. "/.config/caelestia/scripts/workflows.py")
-- The palette and custom bindings share one action catalog.
local action_file = assert(io.open(os.getenv("HOME") .. "/.config/caelestia/actions.json", "r"))
local custom_actions = require("utils.json").decode(action_file:read("*a"))
action_file:close()
-- An action's "exec" (a ~/.local/bin command line) skips Python: the palette's
-- launcher is one IPC call, so Super+K stays instant.
for _, action in ipairs(custom_actions) do
    local command = action.exec and (bin .. action.exec) or (workflows .. " " .. action.workflow)
    for _, key in ipairs(action.keys) do
        hl.bind(key, hl.dsp.exec_cmd(command), { description = action.label })
    end
end
-- Keep the palette resident (hidden) so the first Super+K is instant too. `start`
-- does nothing when it is already running.
daemon(bin .. "caelestia-palette start")

-- Swipe up to open or hide notes, mirroring swipe down for the scratchpad: the same
-- workflow as Super+R. Upstream's gestures.lua gives this swipe to "show scratchpad",
-- which swipe down already toggles; hl.gesture refuses a gesture another one already
-- covers ("will be overshadowed"), so unset upstream's first.
do
    local fingers = require("variables").gestureFingers
    hl.gesture({ fingers = fingers, direction = "up", action = "unset" })
    hl.gesture({ fingers = fingers, direction = "up", action = function()
        hl.exec_cmd(workflows .. " notes")
    end })
end

-- Session start, two checks:
--  * caelestia-shell-guard: if the hand-forked shell QML stops loading after an upgrade
--    (or on a fresh machine with a newer caelestia-shell), swap the forks back to stock
--    and restart the shell, so a broken fork costs a toast instead of a desktop.
--  * caelestia-doctor --login: silent unless Caelestia/Hyprland/Quickshell/Qt versions
--    changed since the last healthy run, then one toast only if something needs
--    attention. The delay lets the shell finish starting. Details: caelestia-doctor.
hl.on("hyprland.start", function()
    hl.exec_cmd(bin .. "caelestia-shell-guard login")
    hl.exec_cmd("sleep 45; " .. bin .. "caelestia-doctor --login")
end)

-- Reuse Caelestia's former todo workspace as the notes scratchpad.
hl.window_rule({ match = { class = "local.caelestia.typed-notes" }, workspace = "special:todo", opaque = true, opacity = "1.0 override 1.0 override" })
hl.window_rule({ match = { class = "local.caelestia.note-search" }, workspace = "special:todo", opaque = true, opacity = "1.0 override 1.0 override" })
hl.window_rule({ match = { class = "local.caelestia.note" }, workspace = "special:todo", opaque = true, opacity = "1.0 override 1.0 override" })

-- HyprMod's look/monitor settings. Upstream hyprland.lua only requires this file once
-- HyprMod has patched it in; requiring it here too means a fresh install picks up the
-- seeded settings straight away (require caches, so it never runs twice).
pcall(require, "hyprland-gui")
