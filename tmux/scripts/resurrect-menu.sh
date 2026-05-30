#!/usr/bin/env bash
# Centered fzf popup for browsing saved tmux-resurrect named profiles.
#
# Meant to be launched from a tmux `display-popup` (see tmux.conf, prefix + G).
# Lists every saved profile with a live preview of its sessions/windows, and
# lets you restore/save/rename/delete/describe/pin. The actual work is
# delegated to resurrect-named.sh, which this also queries for the profiles dir.
#
# Keys inside the popup:
#   type           filter
#   tab            toggle multi-select
#   enter          restore
#   ctrl-s         save current state under a new name
#   ctrl-r         rename selected profile
#   ctrl-x         delete selected (or all selected if multi)
#   ctrl-e         set/clear description for selected
#   ctrl-t         cycle sort (mtime <-> name)
#   ctrl-p         toggle pin on selected
#   ctrl-/         cycle preview pane position
#   esc            close
#
# Subcommands:
#   (none)                 interactive picker (the popup itself)
#   rows                   tab-separated rows for fzf (also used by fzf reload)
#   preview NAME           render NAME's contents into the fzf preview pane
#   save-interactive       prompt + save (used by ctrl-s)
#   rename-interactive N   prompt + rename (used by ctrl-r)
#   delete-interactive N…  prompt + delete (used by ctrl-x; supports multi)
#   describe-interactive N prompt + describe (used by ctrl-e)
#   pin-toggle N           toggle pin on N (used by ctrl-p)
#   cycle-sort             advance the persistent sort mode (used by ctrl-t)
set -euo pipefail

# A display-popup shell may not have ~/.local/bin on PATH (zsh adds it only in
# .zshrc, which non-interactive shells skip), so fzf installed there wouldn't
# be found. Make sure it's reachable.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac

NAMED_BIN="$HOME/.tmux/scripts/resurrect-named.sh"
SELF="$HOME/.tmux/scripts/resurrect-menu.sh"
NAMED_DIR="$("$NAMED_BIN" dir)"
PINS_FILE="$NAMED_DIR/.pins"
SORT_FILE="${TMPDIR:-/tmp}/resurrect-menu-sort.${USER:-$(id -u)}"

sort_mode() { cat "$SORT_FILE" 2>/dev/null || echo mtime; }
set_sort()  { printf '%s' "$1" > "$SORT_FILE"; }

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
# COLOR=1 in the environment enables ANSI escapes (fzf renders them).
# Field map (tab-separated) from resurrect save.sh:
#   pane   : f[1]=session f[2]=window_index f[7]=:current_path f[8]=pane_active f[9]=command
#   window : f[1]=session f[2]=window_index f[3]=:window_name
parse_profile() { # $1=file  $2=mode
  python3 - "$1" "$2" <<'PY'
import sys, os, signal
# Restore default SIGPIPE so piping to `head` doesn't dump a BrokenPipeError.
signal.signal(signal.SIGPIPE, signal.SIG_DFL)
path, mode = sys.argv[1], sys.argv[2]
home = os.environ.get("HOME", "")
USE_COLOR = os.environ.get("COLOR", "0") == "1"
def c(s, code):
    return f"\x1b[{code}m{s}\x1b[0m" if USE_COLOR else s
CYAN, GREEN, DIM, BOLD = "36", "32", "2", "1"
sessions, win_order, win_name, pane_info = [], {}, {}, {}
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
        print(f"{c('●', CYAN)} {c(s, BOLD)}")
        for w in sorted(win_order[s], key=lambda x: int(x) if x.isdigit() else 0):
            cmd, cwd = pane_info.get((s, w), ("", ""))
            label = win_name.get((s, w)) or cmd or "?"
            if home and cwd.startswith(home):
                cwd = "~" + cwd[len(home):]
            print(f"   {w:>2} {c(f'{label:<14}', GREEN)} {c(cwd, DIM)}")
PY
}

# Cache the current profile name and pin set once per `rows` invocation
# (fzf reloads call `rows` afresh, so this stays fresh enough).
load_pins_into() { # $1=array name
  local -n _set="$1"
  _set=()
  [ -f "$PINS_FILE" ] || return 0
  while IFS= read -r p; do [ -n "$p" ] && _set["$p"]=1; done < "$PINS_FILE"
}

# Emit "<rank>\t<sortkey>\t<file>" lines for every profile, then sort and trim.
# Rank: 0 for pinned, 1 for not — guarantees pinned profiles bubble to the top
# regardless of the secondary sort.
sorted_files() {
  local mode="${1:-mtime}"
  [ -d "$NAMED_DIR" ] || return 0
  declare -A pins=()
  load_pins_into pins
  shopt -s nullglob
  local f name pin_rank key m
  local rows=()
  for f in "$NAMED_DIR"/*.txt; do
    name="${f##*/}"; name="${name%.txt}"
    pin_rank=1
    [ -n "${pins[$name]:-}" ] && pin_rank=0
    case "$mode" in
      name)
        key="$name"
        ;;
      *)
        # mtime descending: invert so a single ascending sort works for both keys.
        m="$(stat -c '%Y' "$f" 2>/dev/null || echo 0)"
        key="$(printf '%010d' $((9999999999 - m)))"
        ;;
    esac
    rows+=("$pin_rank	$key	$f")
  done
  [ ${#rows[@]} -eq 0 ] && return 0
  printf '%s\n' "${rows[@]}" | sort | cut -f3-
}

# Get the description for a profile, if any (single line, may be empty).
desc_of() { # $1=name
  [ -f "$NAMED_DIR/$1.desc" ] && cat "$NAMED_DIR/$1.desc" || true
}

# Truncate a string to N columns, appending an ellipsis if it was cut.
trunc() { # $1=string $2=max
  local s="$1" n="$2"
  if [ "${#s}" -gt "$n" ]; then printf '%s…' "${s:0:$((n-1))}"; else printf '%s' "$s"; fi
}

case "${1:-menu}" in
  rows)
    # One row per profile: field 1 = bare name (for actions), field 2 = display.
    # COLOR=1 wraps the markers, description and time in ANSI escapes — fzf is
    # launched with --ansi, so they render in the picker pane.
    mode="$(sort_mode)"
    current="$($NAMED_BIN current 2>/dev/null || true)"
    declare -A pins=()
    load_pins_into pins
    if [ "${COLOR:-0}" = "1" ]; then
      y=$'\x1b[33m'; c=$'\x1b[36m'; d=$'\x1b[2m'; r=$'\x1b[0m'
    else
      y=; c=; d=; r=
    fi
    while IFS= read -r f; do
      [ -e "$f" ] || continue
      name="${f##*/}"; name="${name%.txt}"
      if [ -n "${pins[$name]:-}" ]; then pin_mark="${y}*${r}"; else pin_mark=' '; fi
      if [ "$name" = "$current" ];   then cur_mark="${c}>${r}";  else cur_mark=' '; fi
      read -r ns nw < <(parse_profile "$f" counts)
      # Pad the visible description text BEFORE wrapping in ANSI so the time
      # column stays aligned (printf pads by byte count, not visible width).
      desc_padded="$(printf '%-26s' "$(trunc "$(desc_of "$name")" 26)")"
      desc_col="${d}${desc_padded}${r}"
      printf '%s\t %b%b %-18s %2ss/%2sw  %b  %s%s%s\n' \
        "$name" \
        "$pin_mark" "$cur_mark" \
        "$(trunc "$name" 18)" \
        "$ns" "$nw" \
        "$desc_col" \
        "$d" "$(rel_time "$f")" "$r"
    done < <(sorted_files "$mode")
    ;;

  preview)
    name="${2:-}"
    file="$NAMED_DIR/$name.txt"
    [ -f "$file" ] || { echo "(no such profile)"; exit 0; }
    if [ "${COLOR:-0}" = "1" ]; then
      b=$'\x1b[1m'; r=$'\x1b[0m'; d=$'\x1b[2m'; y=$'\x1b[33m'
    else
      b=; r=; d=; y=
    fi
    abs_time="$(date -r "$file" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')"
    rel="$(rel_time "$file")"
    is_pin=""
    [ -f "$PINS_FILE" ] && grep -qxF "$name" "$PINS_FILE" 2>/dev/null && is_pin="yes"
    cur="$($NAMED_BIN current 2>/dev/null || true)"
    badges_parts=()
    [ -n "$is_pin" ]     && badges_parts+=("${y}pinned${r}")
    [ "$name" = "$cur" ] && badges_parts+=("${y}current${r}")
    badges="${badges_parts[*]:-}"
    if [ -n "$badges" ]; then
      printf '%s%s%s    %ssaved %s (%s)%s   %s\n' \
        "$b" "$name" "$r" "$d" "$abs_time" "$rel" "$r" "$badges"
    else
      printf '%s%s%s    %ssaved %s (%s)%s\n' \
        "$b" "$name" "$r" "$d" "$abs_time" "$rel" "$r"
    fi
    desc="$(desc_of "$name")"
    if [ -n "$desc" ]; then
      printf '%s%s%s\n' "$d" "$desc" "$r"
    fi
    printf '\n'
    parse_profile "$file" detail
    ;;

  save-interactive)
    printf 'Save current state as: '
    read -r n
    [ -n "$n" ] || exit 0
    if "$NAMED_BIN" exists "$n"; then
      printf '"%s" exists. Overwrite? [y/N] ' "$n"
      read -r a
      [ "$a" = y ] || [ "$a" = Y ] || exit 0
      "$NAMED_BIN" save --force "$n"
    else
      "$NAMED_BIN" save "$n"
    fi
    ;;

  rename-interactive)
    old="${2:-}"
    [ -n "$old" ] || exit 0
    printf 'Rename "%s" to: ' "$old"
    read -r n
    [ -n "$n" ] || exit 0
    "$NAMED_BIN" rename "$old" "$n"
    ;;

  delete-interactive)
    shift
    # fzf passes one name per arg when multi-select is on; just one in single mode.
    [ $# -gt 0 ] || exit 0
    if [ $# -eq 1 ]; then
      printf 'Delete profile "%s"? [y/N] ' "$1"
    else
      printf 'Delete %d profiles (%s)? [y/N] ' "$#" "$*"
    fi
    read -r a
    [ "$a" = y ] || [ "$a" = Y ] || exit 0
    for n in "$@"; do "$NAMED_BIN" delete "$n"; done
    ;;

  describe-interactive)
    name="${2:-}"
    [ -n "$name" ] || exit 0
    current_desc="$(desc_of "$name")"
    if [ -n "$current_desc" ]; then
      printf 'Description for "%s" (empty to clear)\ncurrent: %s\nnew: ' "$name" "$current_desc"
    else
      printf 'Description for "%s" (empty to skip): ' "$name"
    fi
    read -r text
    if [ -z "$text" ] && [ -z "$current_desc" ]; then exit 0; fi
    "$NAMED_BIN" describe "$name" "$text"
    ;;

  pin-toggle)
    name="${2:-}"
    [ -n "$name" ] || exit 0
    if [ -f "$PINS_FILE" ] && grep -qxF "$name" "$PINS_FILE" 2>/dev/null; then
      "$NAMED_BIN" unpin "$name"
    else
      "$NAMED_BIN" pin "$name"
    fi
    ;;

  cycle-sort)
    case "$(sort_mode)" in
      name) set_sort mtime ;;
      *)    set_sort name  ;;
    esac
    ;;

  menu|*)
    if ! command -v fzf >/dev/null 2>&1; then
      printf '\n  fzf is not installed.\n  Install it (sudo apt install -y fzf), then reopen.\n\n'
      read -rsn1 -p "  press any key to close…"
      exit 0
    fi
    if [ -z "$("$SELF" rows)" ]; then
      printf '\n  No saved profiles yet.\n\n'
      printf '  Save the current tmux state with  prefix + S  (named save),\n'
      printf '  or reopen this popup and press  ctrl-s  to name + save.\n\n'
      read -rsn1 -p "  press any key to close…"
      exit 0
    fi
    header=$'type to filter   tab select   enter restore   esc close'
    header+=$'\nctrl-s save  ctrl-r rename  ctrl-x delete  ctrl-e describe  ctrl-t sort  ctrl-p pin  ctrl-/ flip'
    COLOR=1 "$SELF" rows | COLOR=1 fzf \
      --delimiter='\t' \
      --with-nth=2.. \
      --no-sort \
      --reverse \
      --ansi \
      --multi \
      --marker='+' \
      --header="$header" \
      --preview="COLOR=1 $SELF preview {1}" \
      --preview-window='down,55%,wrap' \
      --bind="enter:become($NAMED_BIN restore {1})" \
      --bind="ctrl-s:execute($SELF save-interactive)+reload(COLOR=1 $SELF rows)" \
      --bind="ctrl-r:execute($SELF rename-interactive {1})+reload(COLOR=1 $SELF rows)" \
      --bind="ctrl-x:execute($SELF delete-interactive {+1})+reload(COLOR=1 $SELF rows)" \
      --bind="ctrl-e:execute($SELF describe-interactive {1})+reload(COLOR=1 $SELF rows)" \
      --bind="ctrl-p:execute-silent($SELF pin-toggle {1})+reload(COLOR=1 $SELF rows)" \
      --bind="ctrl-t:execute-silent($SELF cycle-sort)+reload(COLOR=1 $SELF rows)" \
      --bind="ctrl-/:change-preview-window(right,60%|down,40%|hidden|down,55%)"
    ;;
esac
