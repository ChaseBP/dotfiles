-- Overrides for ~/.config/hypr/variables.lua.
-- Applied by hyprland.lua after variables.lua loads, so nothing in ~/.config/hypr
-- needs editing -- upstream explicitly says never to modify files in there.
return {
	terminal = "ghostty",
	editor = "ghostty -e " .. string.format("%q", os.getenv("HOME") .. "/.local/bin/nvim"),
	windowOpacity = 1.0,
	kbTodoWs = {}, -- replaced by the notes chooser in hypr-user.lua
	kbMusicWs = {}, -- unused; keep media controls available
	kbShowPanels = "SUPER + CTRL + K", -- Super+K opens the shortcut palette
	cursorTheme = "Bibata-Modern-Ice", -- upstream sweet-cursors is not installed
	-- sleepGestureCmd stays upstream's suspend-then-hibernate: /swap/swapfile + resume= since 2026-10-19
	gestureFingersMore = 5, -- 4 collided with workspaceSwipeFingers -> accidental suspend
	touchpadScrollFactor = 0.9, -- upstream 0.3 made every app need twice the swiping
}
