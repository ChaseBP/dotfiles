#!/usr/bin/env bash
# Caelestia (Hyprland + Quickshell) personal layer: user config, the Super+K
# shortcut palette, hand-forked shell QML, helper scripts, and the XP-Pen
# tablet fixes. Everything is symlinked from caelestia/ so edits stay tracked.
#
# Expects Caelestia itself to be installed already (`caelestia install`): this
# step only layers personal files on top and never touches ~/.config/hypr,
# which upstream manages.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SRC="$DOTFILES_DIR/caelestia"
info "🎨 Setting up Caelestia..."

# Link every file under $1 to the same relative path under $2. Per-file (not
# per-directory) so untracked neighbours — backups, generated state, upstream
# files — are left alone.
link_tree() { # $1=repo dir $2=target dir
  local rel
  while IFS= read -r rel; do
    link_file "$1/$rel" "$2/$rel"
  done < <(cd "$1" && find . -type f -printf '%P\n' | sort)
}

# ------------------------------
# 1. User config (~/.config/caelestia)
# ------------------------------
# hypr-vars.lua / hypr-user.lua / shell.json / cli.json are Caelestia's
# documented override points; palette/ and scripts/ are the Super+K palette
# and personal workflows (notes, OCR, window finder, project picker).
info "🔗 Linking ~/.config/caelestia..."
link_tree "$SRC/config" "$HOME/.config/caelestia"

# ------------------------------
# 2. Hand-forked shell QML (~/.config/quickshell/caelestia)
# ------------------------------
# That directory is a symlink farm into /etc/xdg/quickshell/caelestia built by
# `caelestia install`; qs resolves it before the system tree, so a partial one
# would hide the rest of the shell. Only overlay the forks onto an existing
# farm. They drift from upstream: re-check after any caelestia-shell upgrade
# that errors in modules/nexus or modules/background.
QS_DIR="$HOME/.config/quickshell/caelestia"
if [ -d "$QS_DIR" ] && [ "$(find "$QS_DIR" -type l | wc -l)" -gt 50 ]; then
  info "🔗 Overlaying forked shell QML..."
  link_tree "$SRC/quickshell" "$QS_DIR"
else
  warn "no Caelestia symlink farm at $QS_DIR — run 'caelestia install', then re-run: ./install.sh --only caelestia"
fi

# ------------------------------
# 3. Helper scripts (~/.local/bin)
# ------------------------------
info "🔗 Linking helper scripts..."
for f in "$SRC"/bin/*; do
  [ -f "$f" ] || continue  # scripts only — never caches or folders
  link_file "$f" "$HOME/.local/bin/$(basename "$f")"
done

# ------------------------------
# 4. XP-Pen tray shim
# ------------------------------
# LD_PRELOAD'd by xppen-tablet so closing PenTablet keeps its tray icon.
TRAY_SO="$HOME/.local/lib/xppen-tray/xppen-tray.so"
link_file "$SRC/xppen-tray/shim.c" "$HOME/.local/lib/xppen-tray/shim.c"
if [ -f "$TRAY_SO" ] && [ "$TRAY_SO" -nt "$SRC/xppen-tray/shim.c" ]; then
  ok "xppen-tray.so up to date"
elif command -v gcc >/dev/null 2>&1; then
  run gcc -shared -fPIC -O2 -o "$TRAY_SO" "$SRC/xppen-tray/shim.c" -ldl
  ok "built xppen-tray.so"
else
  warn "gcc not found — xppen-tablet will run without the close-to-tray shim"
fi

# ------------------------------
# 5. XP-Pen udev rule (system)
# ------------------------------
# Upstream OpenTabletDriver omits LIBINPUT_IGNORE_DEVICE for the Deco 640
# (28bd:2904), so libinput and OTD both grab the pen. Copied, not linked:
# udev reads /etc before $HOME may be mounted.
RULE=99-xppen-libinput-ignore.rules
if cmp -s "$SRC/system/$RULE" "/etc/udev/rules.d/$RULE"; then
  ok "udev rule already installed"
elif can_root; then
  as_root install -m 644 "$SRC/system/$RULE" "/etc/udev/rules.d/$RULE"
  as_root udevadm control --reload-rules || true
  ok "installed udev rule $RULE (replug the tablet)"
else
  warn "no root — install manually: sudo install -m 644 $SRC/system/$RULE /etc/udev/rules.d/"
fi

ok "Caelestia setup complete"
info "👉 Reload Hyprland (hyprctl reload) and restart the shell (caelestia shell -d)"
