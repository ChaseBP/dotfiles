-- User Hyprland configuration for Caelestia

-- Ensure Ghostty window rules: 100% opaque, zero transparency
hl.window_rule({ match = { class = "com.mitchellh.ghostty" }, opaque = true, opacity = "1.0 override 1.0 override" })
hl.window_rule({ match = { class = "ghostty" }, opaque = true, opacity = "1.0 override 1.0 override" })

-- Wallpaper switcher (sumi-e set) -- see ~/.local/bin/wall
-- SUPER+SHIFT+W opens a thumbnail picker; press again to dismiss (matches the
-- clipboard/emoji picker pattern). SUPER+ALT+W jumps to a random one.
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("pkill fuzzel || /home/raven/.local/bin/wall"))
hl.bind("SUPER + ALT + W", hl.dsp.exec_cmd("/home/raven/.local/bin/wall random"))

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
hl.exec_cmd("udiskie --no-tray --automount --notify --file-manager thunar")

-- ===========================================================================
-- 2-in-1 / tablet mode
-- Hardware: Wacom pen + touchscreen, Intel hinge sensor (INT33D6) exposed as
-- the "Intel Virtual Switches" switch device, full HID accel/gyro/magn stack.
-- ===========================================================================

-- Bind pen + touch to the internal panel, so the digitiser does not stretch
-- across the whole desktop when an external display is attached, and so
-- rotation applies to input as well as the screen.
hl.device({ name = "wcom4841:00-056a:4841",             output = "eDP-1" })
hl.device({ name = "wcom4841:00-056a:4841-touchscreen", output = "eDP-1" })
hl.device({ name = "wcom4841:00-056a:4841-stylus",      output = "eDP-1" })

-- Auto-rotate: iio-hyprland listens to iio-sensor-proxy over D-Bus and rotates
-- eDP-1 together with the mapped input devices.
-- guarded: hl.exec_cmd fires on every config reload, which otherwise stacks copies
hl.exec_cmd("pgrep -x iio-hyprland >/dev/null || iio-hyprland")

-- On-screen keyboard, started hidden. squeekboard was the wrong pick: it is built
-- for Phosh, wants org.gnome.SessionManager, and only surfaces via input-method-v2.
-- wvkbd is a plain wlroots layer-shell keyboard toggled with SIGUSR1/SIGUSR2.
hl.exec_cmd("pgrep -x wvkbd-mobintl >/dev/null || wvkbd-mobintl -L 320 --hidden")

-- Manual OSK toggle, for when you want it without folding the screen.
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("/home/raven/.local/bin/osk toggle"))

-- Folding the screen back flips SW_TABLET_MODE on "Intel Virtual Switches".
-- NOTE: hl.bind takes exactly (key, action, flags) - the switch selector IS the
-- key. Passing an extra leading "" silently registers nothing.
-- Device enable/disable goes through hl.device, not `hyprctl keyword`, which
-- refuses to run against the Lua parser.
hl.bind("switch:on:Intel Virtual Switches", hl.dsp.exec_cmd(
  "hyprctl eval 'hl.device({ name = \"at-translated-set-2-keyboard\", enabled = false })' ; " ..
  "hyprctl eval 'hl.device({ name = \"dell0823:00-044e:120a-touchpad\", enabled = false })' ; " ..
  "/home/raven/.local/bin/osk show"), { locked = true })

hl.bind("switch:off:Intel Virtual Switches", hl.dsp.exec_cmd(
  "hyprctl eval 'hl.device({ name = \"at-translated-set-2-keyboard\", enabled = true })' ; " ..
  "hyprctl eval 'hl.device({ name = \"dell0823:00-044e:120a-touchpad\", enabled = true })' ; " ..
  "/home/raven/.local/bin/osk hide"), { locked = true })


-- Clipboard: keep password-manager entries out of cliphist.
-- execs.lua starts the stock watcher and there is no supported way to suppress it
-- (no cliphist toggle exists in hypr-vars.lua), so replace it here instead of editing
-- ~/.config/hypr/, which the README forbids and which conflicts on every update.
hl.exec_cmd("pkill -f 'wl-paste --type text --watch cliphist store'; "
    .. "wl-paste --type text --watch /home/raven/.local/bin/cliphist-store")

-- Personal daily workflows. All custom logic lives beside these user configs.
local workflows = "python3 " .. string.format("%q", os.getenv("HOME") .. "/.config/caelestia/scripts/workflows.py")
-- The palette and custom bindings share one action catalog.
local action_file = assert(io.open(os.getenv("HOME") .. "/.config/caelestia/actions.json", "r"))
local custom_actions = require("utils.json").decode(action_file:read("*a"))
action_file:close()
for _, action in ipairs(custom_actions) do
    for _, key in ipairs(action.keys) do
        hl.bind(key, hl.dsp.exec_cmd(workflows .. " " .. action.workflow), { description = action.label })
    end
end

-- Reuse Caelestia's former todo workspace as the notes scratchpad.
hl.window_rule({ match = { class = "local.caelestia.typed-notes" }, workspace = "special:todo", opaque = true, opacity = "1.0 override 1.0 override" })
hl.window_rule({ match = { class = "local.caelestia.note-search" }, workspace = "special:todo", opaque = true, opacity = "1.0 override 1.0 override" })
