#!/usr/bin/env bash
# Named tmux-resurrect profiles.
#
# tmux-resurrect saves the whole tmux server (all sessions/windows/panes) into
# one snapshot and points `last` at it; restore always reads `last`. This wraps
# resurrect's own save.sh/restore.sh so you can keep several *named* snapshots
# and restore any one of them on demand.
#
# Usage:
#   resurrect-named.sh save    <name>   # snapshot current state as <name>
#   resurrect-named.sh restore <name>   # restore the <name> snapshot
#   resurrect-named.sh list             # list saved profiles
#   resurrect-named.sh delete  <name>   # remove a saved profile
set -euo pipefail

# Resolve the resurrect dir the same way the plugin does, so our copy/restore
# logic always targets the exact files save.sh/restore.sh read and write:
# honor the @resurrect-dir tmux option, else fall back to the XDG default.
resurrect_dir() {
  local opt
  opt="$(tmux show-option -gqv '@resurrect-dir' 2>/dev/null || true)"
  if [ -n "$opt" ]; then
    # Expand a leading ~ and embedded $HOME, mirroring the plugin's helpers.sh.
    opt="${opt/#\~/$HOME}"
    printf '%s' "${opt//\$HOME/$HOME}"
  else
    printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
  fi
}

RESURRECT_DIR="${RESURRECT_DIR:-$(resurrect_dir)}"
NAMED_DIR="$RESURRECT_DIR/named"
PLUGIN_DIR="$HOME/.tmux/plugins/tmux-resurrect/scripts"
SAVE_SH="$PLUGIN_DIR/save.sh"
RESTORE_SH="$PLUGIN_DIR/restore.sh"

msg() { tmux display-message "resurrect: $*" 2>/dev/null || echo "resurrect: $*"; }

# Keep names filesystem-safe: collapse anything that isn't [A-Za-z0-9._-] to '_'.
sanitize() { printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '_'; }

cmd="${1:-}"
raw_name="${2:-}"

case "$cmd" in
  save)
    [ -n "$raw_name" ] || { msg "save needs a name"; exit 1; }
    name="$(sanitize "$raw_name")"
    mkdir -p "$NAMED_DIR"
    # Run resurrect's own save quietly, then copy the fresh snapshot aside.
    SCRIPT_OUTPUT="quiet" "$SAVE_SH"
    cp -L "$RESURRECT_DIR/last" "$NAMED_DIR/$name.txt"
    msg "saved profile '$name'"
    ;;
  restore)
    [ -n "$raw_name" ] || { msg "restore needs a name"; exit 1; }
    name="$(sanitize "$raw_name")"
    [ -f "$NAMED_DIR/$name.txt" ] || { msg "no profile '$name'"; exit 1; }
    # Point `last` at the named snapshot (relative link), then let resurrect restore it.
    ln -sf "named/$name.txt" "$RESURRECT_DIR/last"
    "$RESTORE_SH"
    msg "restored profile '$name'"
    ;;
  list)
    if [ -d "$NAMED_DIR" ] && ls "$NAMED_DIR"/*.txt >/dev/null 2>&1; then
      names="$(for f in "$NAMED_DIR"/*.txt; do basename "$f" .txt; done | paste -sd ', ')"
      msg "profiles: $names"
    else
      msg "no saved profiles"
    fi
    ;;
  delete)
    [ -n "$raw_name" ] || { msg "delete needs a name"; exit 1; }
    name="$(sanitize "$raw_name")"
    if [ -f "$NAMED_DIR/$name.txt" ]; then
      rm -f "$NAMED_DIR/$name.txt"
      msg "deleted profile '$name'"
    else
      msg "no profile '$name'"
    fi
    ;;
  *)
    msg "usage: save|restore|delete <name> | list"
    exit 1
    ;;
esac
