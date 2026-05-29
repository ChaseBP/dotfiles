#!/usr/bin/env bash
# Centered fzf popup for browsing saved tmux-resurrect named profiles.
#
# Meant to be launched from a tmux `display-popup` (see tmux.conf, prefix + G).
# Lists every saved profile with a live preview of its sessions/windows, and
# lets you restore/save/rename/delete. The actual work is delegated to
# resurrect-named.sh, which this also queries for the profiles dir.
#
# In-popup keys: enter=restore  ctrl-s=save  ctrl-r=rename  ctrl-x=delete  esc=close
#
# Subcommands:
#   (none)        interactive picker (the popup itself)
#   rows          tab-separated rows for fzf (also used by fzf reload)
#   preview NAME  render NAME's contents into the fzf preview pane
set -euo pipefail

# A display-popup shell may not have ~/.local/bin on PATH (zsh adds it only in
# .zshrc, which non-interactive shells skip), so fzf installed there wouldn't be
# found. Make sure it's reachable.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac

NAMED_BIN="$HOME/.tmux/scripts/resurrect-named.sh"
SELF="$HOME/.tmux/scripts/resurrect-menu.sh"
NAMED_DIR="$("$NAMED_BIN" dir)"

# Human-friendly age of a file from its mtime.
rel_time() { # $1=file
  local now mtime d
  now="$(date +%s)"
  mtime="$(date -r "$1" +%s 2>/dev/null || echo "$now")"
  d=$(( now - mtime ))
  if   [ "$d" -lt 60 ];    then echo "just now"
  elif [ "$d" -lt 3600 ];  then echo "$(( d / 60 ))m ago"
  elif [ "$d" -lt 86400 ]; then echo "$(( d / 3600 ))h ago"
  else echo "$(( d / 86400 ))d ago"
  fi
}

# Parse a resurrect snapshot. mode=counts -> "<sessions> <windows>";
# mode=detail -> a per-session, per-window breakdown (program + cwd).
# Field map (tab-separated) from resurrect save.sh:
#   pane   : 1=session 2=window_index 7=:current_path 8=pane_active 9=command
#   window : 1=session 2=window_index 3=:window_name
parse_profile() { # $1=file  $2=mode
  python3 - "$1" "$2" <<'PY'
import sys, os
path, mode = sys.argv[1], sys.argv[2]
home = os.environ.get("HOME", "")
sessions = []          # session names, first-seen order
win_order = {}         # session -> [window_index, ...]
win_name = {}          # (session, window) -> name
pane_info = {}         # (session, window) -> (command, cwd); active pane wins
def see(s, w=None):
    if s not in win_order:
        win_order[s] = []; sessions.append(s)
    if w is not None and w not in win_order[s]:
        win_order[s].append(w)
try:
    with open(path) as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if not f:
                continue
            if f[0] == "window" and len(f) > 3:
                see(f[1], f[2]); win_name[(f[1], f[2])] = f[3].lstrip(":")
            elif f[0] == "pane" and len(f) > 9:
                see(f[1], f[2]); key = (f[1], f[2])
                if key not in pane_info or f[8] == "1":
                    pane_info[key] = (f[9], f[7].lstrip(":"))
except OSError:
    pass

if mode == "counts":
    nwin = sum(len(v) for v in win_order.values())
    print(f"{len(sessions)} {nwin}")
else:
    for s in sessions:
        print(f"● {s}")
        for w in sorted(win_order[s], key=lambda x: int(x) if x.isdigit() else 0):
            cmd, cwd = pane_info.get((s, w), ("", ""))
            label = win_name.get((s, w)) or cmd or "?"
            if home and cwd.startswith(home):
                cwd = "~" + cwd[len(home):]
            print(f"   {w:>2} {label:<12} {cwd}")
PY
}

case "${1:-menu}" in
  rows)
    # One row per profile: field1 = bare name (for actions), rest = pretty cols.
    shopt -s nullglob
    files=("$NAMED_DIR"/*.txt)
    [ ${#files[@]} -gt 0 ] || exit 0
    for f in "${files[@]}"; do
      name="$(basename "$f" .txt)"
      read -r ns nw < <(parse_profile "$f" counts)
      printf '%s\t  %-18s %2s session%s  %2s window%s   %s\n' \
        "$name" "$name" \
        "$ns" "$([ "$ns" = 1 ] && echo '' || echo s)" \
        "$nw" "$([ "$nw" = 1 ] && echo '' || echo s)" \
        "$(rel_time "$f")"
    done
    ;;

  preview)
    name="${2:-}"
    file="$NAMED_DIR/$name.txt"
    [ -f "$file" ] || { echo "(no such profile)"; exit 0; }
    printf '%s    saved %s\n\n' "$name" "$(rel_time "$file")"
    parse_profile "$file" detail
    ;;

  menu|*)
    if ! command -v fzf >/dev/null 2>&1; then
      printf '\n  fzf is not installed.\n  Install it (sudo apt install -y fzf), then reopen.\n\n'
      read -rsn1 -p "  press any key to close…"
      exit 0
    fi
    # Empty state: no profiles yet.
    if [ -z "$("$SELF" rows)" ]; then
      printf '\n  No saved profiles yet.\n  Save the current tmux state with  prefix + S  (or ctrl-s here).\n\n'
      read -rsn1 -p "  press any key to close…"
      exit 0
    fi
    "$SELF" rows | fzf \
      --delimiter='\t' \
      --with-nth=2.. \
      --no-sort \
      --reverse \
      --header=$'enter: restore   ctrl-s: save   ctrl-r: rename   ctrl-x: delete   esc: close' \
      --preview="$SELF preview {1}" \
      --preview-window='down,55%,wrap' \
      --bind="enter:become($NAMED_BIN restore {1})" \
      --bind="ctrl-s:execute(printf 'Save current state as: '; read -r n; [ -n \"\$n\" ] && { if $NAMED_BIN exists \"\$n\"; then printf '\"%s\" exists. Overwrite? [y/N] ' \"\$n\"; read -r a; [ \"\$a\" = y ] && $NAMED_BIN save --force \"\$n\"; else $NAMED_BIN save \"\$n\"; fi; })+reload($SELF rows)" \
      --bind="ctrl-r:execute(printf 'Rename \"%s\" to: ' {1}; read -r n; [ -n \"\$n\" ] && $NAMED_BIN rename {1} \"\$n\")+reload($SELF rows)" \
      --bind="ctrl-x:execute(printf 'Delete profile \"%s\"? [y/N] ' {1}; read -r a; [ \"\$a\" = y ] && $NAMED_BIN delete {1})+reload($SELF rows)"
    ;;
esac
