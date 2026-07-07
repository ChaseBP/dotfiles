#!/usr/bin/env bash
# Centered fzf popup for browsing saved tmux-resurrect named profiles.
#
# Meant to be launched from a tmux `display-popup` (see tmux.conf, prefix + G).
# Lists every saved profile with a live preview of its sessions/windows, and
# lets you restore/save/rename/delete/describe/pin/copy/diff. The actual work
# is delegated to resurrect-named.sh, which this also queries for the dir.
#
# Keys inside the popup:
#   type           filter the list
#   tab            toggle multi-select
#   enter          restore (asks to confirm first)
#   ctrl-s         save the current session (or all sessions) as a new profile
#   ctrl-w         write-back the current (▶) profile from the live state
#   ctrl-o         overwrite the highlighted profile from the live state
#   ctrl-r         rename selected profile
#   ctrl-x         delete selected → trash (or all selected if multi)
#   ctrl-e         set/clear description (applies to all selected)
#   ctrl-y         copy / duplicate selected profile
#   ctrl-p         toggle pin on selected (multi ok)
#   ctrl-g         search inside snapshots (filters the list)
#   alt-d          diff two tab-selected profiles
#   ctrl-t         cycle sort (mtime <-> name)
#   ctrl-l         reopen the popup (re-fit after a terminal resize)
#   alt-v          cycle preview view (active/collapsed/full)
#   ctrl-/         cycle preview pane (right/down/hidden)
#   ?              full keyboard help
#   esc            close
#
# Subcommands:
#   (none)                 interactive picker (the popup itself)
#   rows                   tab-separated rows for fzf (also used by fzf reload)
#   header                 fzf header text (key hints + profile count + sort)
#   preview NAME           render NAME's contents into the fzf preview pane
#   dump NAME              color-free structural render (used by `diff`)
#   save-interactive       prompt + save (used by ctrl-s)
#   rename-interactive N   prompt + rename (used by ctrl-r)
#   delete-interactive N…  prompt + delete (used by ctrl-x; supports multi)
#   describe-interactive N prompt + describe (used by ctrl-e; supports multi)
#   restore-interactive N  confirm + restore (used by enter)
#   copy-interactive N     prompt + copy (used by ctrl-y)
#   diff-interactive A B   show a diff of two profiles (used by alt-d)
#   find-interactive       prompt + set/clear the content filter (used by ctrl-g)
#   write-back-interactive confirm + re-save the current profile (used by ctrl-w)
#   overwrite-interactive N confirm + overwrite N from the live state (ctrl-o)
#   reopen [query]         close + reopen the popup at the current client size
#   pin-toggle N…          toggle pin on N (used by ctrl-p; supports multi)
#   cycle-sort             advance the persistent sort mode (used by ctrl-t)
#   cycle-view             advance the persistent preview mode (used by alt-v)
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
VIEW_FILE="${TMPDIR:-/tmp}/resurrect-menu-view.${USER:-$(id -u)}"
# Transient content filter (set by ctrl-g). Cleared each time the popup opens.
FILTER_FILE="${TMPDIR:-/tmp}/resurrect-menu-filter.${USER:-$(id -u)}"
# One-shot fzf query handoff for ctrl-l (reopen): its presence also marks the
# next popup open as a reopen bounce, so the ctrl-g filter survives it.
QUERY_FILE="${TMPDIR:-/tmp}/resurrect-menu-query.${USER:-$(id -u)}"

sort_mode() { cat "$SORT_FILE" 2>/dev/null || echo mtime; }
set_sort()  { printf '%s' "$1" > "$SORT_FILE"; }

# Preview view mode — persisted so the chosen preference sticks. Cycled by alt-v.
view_mode() { cat "$VIEW_FILE" 2>/dev/null || echo active; }
set_view()  { printf '%s' "$1" > "$VIEW_FILE"; }

content_filter() { cat "$FILTER_FILE" 2>/dev/null || true; }

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

# Count sessions/windows in one snapshot with awk (no python3 startup cost).
# Mirrors resurrect-named.sh's counts(). Prints "<sessions> <windows>".
counts_awk() { # $1=file
  awk -F'\t' '
    $1=="pane" || $1=="window" { s[$2]=1; w[$2 SUBSEP $3]=1 }
    END { ns=0; for (k in s) ns++; nw=0; for (k in w) nw++; print ns, nw }
  ' "$1" 2>/dev/null || echo "0 0"
}

# Count every snapshot in ONE awk pass, keyed by filename. Replaces a per-row
# python3 spawn in `rows` (which cost ~30-50ms each → seconds for 50 profiles).
# Emits: "<file>\t<sessions>\t<windows>"; files with no records are omitted
# (callers default those to "0 0").
counts_all() { # $@=files
  [ "$#" -gt 0 ] || return 0
  awk -F'\t' '
    ($1=="pane" || $1=="window") {
      sk = FILENAME SUBSEP $2;          if (!(sk in S)) { S[sk]=1; ns[FILENAME]++ }
      wk = FILENAME SUBSEP $2 SUBSEP $3; if (!(wk in W)) { W[wk]=1; nw[FILENAME]++ }
    }
    END { for (f in ns) printf "%s\t%d\t%d\n", f, ns[f], nw[f] }
  ' "$@" 2>/dev/null || true
}

# Degraded preview when python3 is unavailable: a basic awk listing plus a hint,
# so the pane is informative instead of blank. The rich renderer below is used
# whenever python3 is present.
parse_profile_nopy() { # $1=file $2=mode
  case "$2" in
    counts) counts_awk "$1" ;;
    *)
      printf '(python3 not found — basic view; install python3 for the full preview)\n\n'
      awk -F'\t' '
        $1=="window" && NF>=4 { s=$2; if (!(s in seen)) { seen[s]=1; ord[++n]=s }
                                lines[s]=lines[s] sprintf("   %s %s\n", $3, substr($4,2)) }
        $1=="pane"   && NF>=3 { s=$2; if (!(s in seen)) { seen[s]=1; ord[++n]=s } }
        END { for (i=1;i<=n;i++) { printf "* %s\n", ord[i]; printf "%s", lines[ord[i]] } }
      ' "$1" 2>/dev/null || printf '(unreadable snapshot)\n'
      ;;
  esac
}

# Parse a resurrect snapshot. Modes:
#   counts     -> "<sessions> <windows>" (one line, for the picker rows)
#   full       -> every session, every window (program + cwd)
#   active     -> only the active session's windows, + "N more" footer
#   collapsed  -> one summary line per session (window count + cwd)
# COLOR=1 in the environment enables ANSI escapes (fzf renders them).
# Field map (tab-separated) from resurrect save.sh:
#   pane   : f[1]=session f[2]=window_index f[7]=:current_path f[8]=pane_active f[9]=command
#   window : f[1]=session f[2]=window_index f[3]=:window_name
#   state  : f[1]=active (client) session  — used to pick the "active" session
parse_profile() { # $1=file  $2=mode
  # Rich rendering needs python3; degrade gracefully if it's missing.
  if ! command -v python3 >/dev/null 2>&1; then
    parse_profile_nopy "$1" "$2"
    return
  fi
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
active = None          # active session, from the `state` record
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
            if f[0] == "state" and len(f) > 1:
                active = f[1]
            elif f[0] == "window" and len(f) > 3:
                see(f[1], f[2]); win_name[(f[1], f[2])] = f[3].lstrip(":")
            elif f[0] == "pane" and len(f) > 9:
                see(f[1], f[2]); key = (f[1], f[2])
                if key not in pane_info or f[8] == "1":
                    pane_info[key] = (f[9], f[7].lstrip(":"))
except OSError:
    pass

def shorten(cwd):
    return "~" + cwd[len(home):] if home and cwd.startswith(home) else cwd
def wins(s):
    return sorted(win_order[s], key=lambda x: int(x) if x.isdigit() else 0)
def win_line(s, w):
    cmd, cwd = pane_info.get((s, w), ("", ""))
    label = win_name.get((s, w)) or cmd or "?"
    return f"   {w:>2} {c(f'{label:<14}', GREEN)} {c(shorten(cwd), DIM)}"

if mode == "counts":
    nwin = sum(len(v) for v in win_order.values())
    print(f"{len(sessions)} {nwin}")

elif mode == "collapsed":
    for s in sessions:
        ws = wins(s); n = len(ws)
        cwd = shorten(pane_info.get((s, ws[0]), ("", ""))[1]) if ws else ""
        tag = c(" ·active", DIM) if s == active else ""
        unit = "window" if n == 1 else "windows"
        print(f"{c('●', CYAN)} {c(s, BOLD)}{tag}   {n} {unit}   {c(cwd, DIM)}")

elif mode == "active":
    target = active if active in win_order else (sessions[0] if sessions else None)
    if target is None:
        print("(empty snapshot)")
    else:
        print(f"{c('●', CYAN)} {c(target, BOLD)}   {c('(active session)', DIM)}")
        for w in wins(target):
            print(win_line(target, w))
        others = [s for s in sessions if s != target]
        if others:
            print()
            label = "session" if len(others) == 1 else "sessions"
            print(c(f"+ {len(others)} more {label}: {', '.join(others)}", DIM))

else:  # full
    for s in sessions:
        tag = c(" ·active", DIM) if s == active else ""
        print(f"{c('●', CYAN)} {c(s, BOLD)}{tag}")
        for w in wins(s):
            print(win_line(s, w))
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

# Pad to N columns by character count (printf %-Ns pads by bytes, which
# misaligns columns when names/descriptions contain multibyte characters).
pad() { # $1=string $2=width
  local s="$1" n
  n=$(( $2 - ${#s} ))
  if [ "$n" -gt 0 ]; then printf '%s%*s' "$s" "$n" ''; else printf '%s' "$s"; fi
}

# Dialog chrome shared by keys-help and the *-interactive prompts. These only
# ever run on the popup tty (via fzf execute()), so colors are on unless the
# user opted out via NO_COLOR.
if [ -n "${NO_COLOR:-}" ]; then
  DB=; DC=; DY=; DD=; DR=
else
  DB=$'\x1b[1m'; DC=$'\x1b[36m'; DY=$'\x1b[33m'; DD=$'\x1b[2m'; DR=$'\x1b[0m'
fi
DRULE='────────────────────────────────────────────'
dlg() { # $1=title — clear the popup screen and draw a framed dialog header
  clear 2>/dev/null || printf '\033c'
  printf '\n  %s┌─ %s%s%s %s%s%s\n' "$DD" "$DB" "$1" "$DR" "$DD" "${DRULE:$(( ${#1} + 4 ))}" "$DR"
}
dlg_hint() { printf '  %s%s%s\n' "$DD" "$1" "$DR"; }

# Prompt + read a line with readline editing and an editable pre-filled value.
# The prompt MUST be passed through `read -p` (not printf'd separately) so
# readline can measure its width — otherwise moving the cursor back over the
# pre-filled text corrupts the line / sticks the cursor under the label. Color
# escapes are wrapped in \001..\002 so readline counts them as zero-width.
ask_prefill() { # $1=dest var  $2=label  $3=initial value
  local _p
  _p="$(printf '\n  \001%s\002%s\001%s\002 ' "$DC" "$2" "$DR")"
  IFS= read -e -r -p "$_p" -i "$3" "$1"
}

# Profile/live session helpers for the restore collision warning + drift hints.
live_sessions()    { tmux list-sessions -F '#{session_name}' 2>/dev/null | LC_ALL=C sort || true; }
profile_sessions() { awk -F'\t' '$1=="window"||$1=="pane"{print $2}' "$1" 2>/dev/null | LC_ALL=C sort -u || true; }

case "${1:-menu}" in
  rows)
    # One row per profile: field 1 = bare name (for actions), field 2 = display.
    # COLOR=1 wraps the markers, description and time in ANSI escapes — fzf is
    # launched with --ansi, so they render in the picker pane.
    mode="$(sort_mode)"
    current="$($NAMED_BIN current 2>/dev/null || true)"
    # Responsive columns: widen name/desc on a roomy popup, but keep the
    # original 18/26 on narrow popups so the layout there is unchanged. COLS is
    # threaded in from the launcher (the popup width at open time).
    cols="${COLS:-80}"
    name_w=18; desc_w=26
    avail=$(( cols - 30 ))
    if [ "$avail" -gt 44 ]; then
      extra=$(( (avail - 44) / 2 ))
      name_w=$(( 18 + extra )); [ "$name_w" -gt 40 ] && name_w=40
      desc_w=$(( 26 + extra )); [ "$desc_w" -gt 60 ] && desc_w=60
    fi
    declare -A pins=()
    load_pins_into pins
    # Optional content filter (ctrl-g): restrict to profiles whose snapshot
    # matches the pattern, via resurrect-named.sh's `find`.
    filter="$(content_filter)"
    declare -A match=()
    if [ -n "$filter" ]; then
      while IFS= read -r m; do [ -n "$m" ] && match["$m"]=1; done < <("$NAMED_BIN" find "$filter" 2>/dev/null)
    fi
    if [ "${COLOR:-0}" = "1" ]; then
      y=$'\x1b[1;33m'; c=$'\x1b[1;36m'; d=$'\x1b[2m'; r=$'\x1b[0m'
    else
      y=; c=; d=; r=
    fi
    mapfile -t files < <(sorted_files "$mode")
    # All session/window counts in one awk pass instead of one python3 per row.
    declare -A CNT=()
    if [ "${#files[@]}" -gt 0 ]; then
      while IFS=$'\t' read -r cf cns cnw; do CNT["$cf"]="$cns $cnw"; done < <(counts_all "${files[@]}")
    fi
    for f in "${files[@]}"; do
      [ -e "$f" ] || continue
      name="${f##*/}"; name="${name%.txt}"
      if [ -n "$filter" ] && [ -z "${match[$name]:-}" ]; then continue; fi
      if [ -n "${pins[$name]:-}" ]; then pin_mark="${y}*${r}"; else pin_mark=' '; fi
      if [ "$name" = "$current" ];   then cur_mark="${c}▶${r}";  else cur_mark=' '; fi
      read -r ns nw <<< "${CNT[$f]:-0 0}"
      # Pad visible text BEFORE wrapping in ANSI, with pad() (character-aware)
      # so multibyte names/descriptions don't shift the columns.
      cnt_col="$(printf '%2s' "$ns")${d}s${r}·$(printf '%-2s' "$nw")${d}w${r}"
      desc_col="${d}$(pad "$(trunc "$(desc_of "$name")" "$desc_w")" "$desc_w")${r}"
      printf '%s\t %b%b %s %b  %b  %s%s%s\n' \
        "$name" \
        "$pin_mark" "$cur_mark" \
        "$(pad "$(trunc "$name" "$name_w")" "$name_w")" \
        "$cnt_col" \
        "$desc_col" \
        "$d" "$(rel_time "$f")" "$r"
    done
    ;;

  header)
    # Two-line fzf header: key hints, then live state (profile count + sort
    # mode + any active filter). Re-rendered via transform-header after actions
    # that change either.
    if [ -n "${NO_COLOR:-}" ]; then hk=; hd=; hr=; else hk=$'\x1b[36m'; hd=$'\x1b[2m'; hr=$'\x1b[0m'; fi
    pair() { printf '%s%s%s %s→%s %s' "$hk" "$1" "$hr" "$hd" "$hr" "$2"; }
    sep=" ${hd}│${hr} "
    shopt -s nullglob
    files=("$NAMED_DIR"/*.txt)
    total=${#files[@]}
    if [ "$total" -eq 0 ]; then
      # Empty state — also reached after deleting the last profile inside fzf.
      printf '%s\n' "$(pair ctrl-s save)$sep$(pair esc close)"
      printf '%sno profiles yet — press ctrl-s to save the current tmux state%s\n' "$hd" "$hr"
      exit 0
    fi
    case "$(sort_mode)" in name) sm="name" ;; *) sm="recent" ;; esac
    filter="$(content_filter)"
    if [ -n "$filter" ]; then
      visible=0
      while IFS= read -r m; do [ -n "$m" ] && visible=$((visible + 1)); done < <("$NAMED_BIN" find "$filter" 2>/dev/null)
    else
      visible="$total"
    fi
    [ "$total" -eq 1 ] && noun="profile" || noun="profiles"
    printf '%s\n' "$(pair type filter)$sep$(pair tab select)$sep$(pair enter restore)$sep$(pair esc close)$sep$(pair '?' shortcuts)"
    if [ -n "$filter" ]; then
      printf '%s%s/%s %s · sort: %s (ctrl-t) · filter: %s (ctrl-g clears)%s\n' "$hd" "$visible" "$total" "$noun" "$sm" "$filter" "$hr"
    else
      printf '%s%s %s · sort: %s (ctrl-t)%s\n' "$hd" "$total" "$noun" "$sm" "$hr"
    fi
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
    view="$(view_mode)"
    printf '%sview: %s  ·  alt-v to change%s\n' "$d" "$view" "$r"
    # For the current profile, show whether the live tmux state has drifted.
    if [ "$name" = "$cur" ] && [ -n "${TMUX:-}" ]; then
      if [ -n "$("$NAMED_BIN" status-indicator 2>/dev/null)" ]; then
        printf '%slive: drifted from this profile · prefix+W to write back%s\n' "$y" "$r"
      else
        printf '%slive: in sync with this profile%s\n' "$d" "$r"
      fi
    fi
    printf '\n'
    parse_profile "$file" "$view"
    ;;

  dump)
    # Color-free, view-independent structural render with no volatile header —
    # used by `resurrect-named.sh diff` so diffs aren't polluted by timestamps,
    # badges, or the current preview mode.
    name="${2:-}"
    file="$NAMED_DIR/$name.txt"
    [ -f "$file" ] || { echo "(no such profile)"; exit 0; }
    COLOR=0 parse_profile "$file" full
    ;;

  save-interactive)
    dlg "save profile"
    cur_sess="$(tmux display-message -p '#{client_session}' 2>/dev/null || true)"
    if [ -n "$cur_sess" ]; then
      dlg_hint "snapshots the current session ($cur_sess) · empty cancels"
    else
      dlg_hint "snapshots all sessions (no attached client) · empty cancels"
    fi
    printf '\n  %sname:%s ' "$DC" "$DR"
    read -r n
    [ -n "$n" ] || exit 0
    # Per-session by default; offer the whole server as the explicit choice.
    flag=""
    if [ -n "$cur_sess" ]; then
      printf '  %sscope — [c]urrent session "%s" or [a]ll sessions?%s [C/a] ' "$DC" "$cur_sess" "$DR"
      read -r sc
      case "$sc" in a|A) flag="--all" ;; esac
    fi
    if "$NAMED_BIN" exists "$n"; then
      printf '  %s"%s" exists — overwrite?%s [y/N] ' "$DY" "$n" "$DR"
      read -r a
      [ "$a" = y ] || [ "$a" = Y ] || exit 0
      # shellcheck disable=SC2086  # $flag intentionally empty or one word
      "$NAMED_BIN" save --force $flag "$n"
    else
      # shellcheck disable=SC2086
      "$NAMED_BIN" save $flag "$n"
    fi
    ;;

  rename-interactive)
    old="${2:-}"
    [ -n "$old" ] || exit 0
    dlg "rename profile"
    if [ -f "$NAMED_DIR/$old.txt" ]; then
      read -r ns nw < <(parse_profile "$NAMED_DIR/$old.txt" counts)
      dlg_hint "$old · ${ns}s·${nw}w · empty cancels"
    fi
    # Pre-fill the old name so it can be edited in place instead of retyped.
    ask_prefill n "new name:" "$old"
    [ -n "$n" ] || exit 0
    [ "$n" = "$old" ] && exit 0
    "$NAMED_BIN" rename "$old" "$n"
    ;;

  delete-interactive)
    shift
    # fzf passes one name per arg when multi-select is on; just one in single mode.
    [ $# -gt 0 ] || exit 0
    dlg "delete"
    if [ $# -eq 1 ]; then
      # Show what the profile holds before asking.
      if [ -f "$NAMED_DIR/$1.txt" ]; then
        COLOR=1 parse_profile "$NAMED_DIR/$1.txt" collapsed | sed 's/^/  /'
      fi
      printf '\n  %sdelete "%s" → trash?%s [y/N] ' "$DY" "$1" "$DR"
    else
      # Summarize each profile (counts) so a bulk delete isn't blind.
      for n in "$@"; do
        if [ -f "$NAMED_DIR/$n.txt" ]; then
          read -r ns nw < <(parse_profile "$NAMED_DIR/$n.txt" counts)
          printf '  %s•%s %s   %s%ss·%sw%s\n' "$DD" "$DR" "$(pad "$n" 20)" "$DD" "$ns" "$nw" "$DR"
        else
          printf '  %s•%s %s\n' "$DD" "$DR" "$n"
        fi
      done
      printf '\n  %sdelete these %d profiles → trash?%s [y/N] ' "$DY" "$#" "$DR"
    fi
    read -r a
    [ "$a" = y ] || [ "$a" = Y ] || exit 0
    for n in "$@"; do "$NAMED_BIN" delete "$n"; done
    ;;

  describe-interactive)
    shift
    [ $# -gt 0 ] || exit 0
    current_desc=""
    [ $# -eq 1 ] && current_desc="$(desc_of "$1")"
    dlg "describe profile"
    if [ $# -eq 1 ]; then
      if [ -n "$current_desc" ]; then
        dlg_hint "$1 · edit below · empty clears"
      else
        dlg_hint "$1 · empty cancels"
      fi
    else
      dlg_hint "$# profiles · same text applied to all · empty clears"
    fi
    # Pre-fill the current description (single target) so it can be edited.
    ask_prefill text "description:" "$current_desc"
    if [ -z "$text" ] && [ $# -eq 1 ] && [ -z "$current_desc" ]; then exit 0; fi
    for name in "$@"; do "$NAMED_BIN" describe "$name" "$text"; done
    ;;

  restore-interactive)
    # Bound to enter (via become). Confirms first — restore spawns/clobbers live
    # sessions, so it shouldn't fire on a stray keypress — and keeps the popup
    # open with the error if restore fails (become would otherwise just vanish).
    name="${2:-}"
    [ -n "$name" ] || exit 0
    dlg "restore profile"
    if [ -f "$NAMED_DIR/$name.txt" ]; then
      COLOR=1 parse_profile "$NAMED_DIR/$name.txt" collapsed | sed 's/^/  /'
      # Warn when some of these sessions are already open: restore merges into
      # the live server rather than replacing it, so existing sessions persist.
      if [ -n "${TMUX:-}" ]; then
        clash="$(comm -12 <(live_sessions) <(profile_sessions "$NAMED_DIR/$name.txt") 2>/dev/null | sed '/^$/d' | paste -sd ',' | sed 's/,/, /g')"
        if [ -n "$clash" ]; then
          printf '\n  %s⚠ already open: %s%s\n' "$DY" "$clash" "$DR"
          printf '  %srestore merges into the live server (existing sessions kept)%s\n' "$DD" "$DR"
        fi
      fi
    fi
    printf '\n  %srestore "%s"?%s [Y/n] ' "$DC" "$name" "$DR"
    read -r a
    case "$a" in n|N) exit 0 ;; esac
    if ! "$NAMED_BIN" restore "$name"; then
      printf '\n  %srestore failed — press any key…%s' "$DY" "$DR"
      read -rsn1
      exit 1
    fi
    ;;

  copy-interactive)
    src="${2:-}"
    [ -n "$src" ] || exit 0
    dlg "copy profile"
    dlg_hint "$src → new name · empty cancels"
    ask_prefill dst "new name:" "${src}-copy"
    [ -n "$dst" ] || exit 0
    "$NAMED_BIN" copy "$src" "$dst"
    ;;

  diff-interactive)
    shift
    if [ $# -ne 2 ]; then
      dlg "diff"
      dlg_hint "tab-select exactly two profiles, then alt-d"
      printf '\n  %spress any key…%s' "$DD" "$DR"
      read -rsn1
      exit 0
    fi
    out="$("$NAMED_BIN" diff "$1" "$2")"
    if command -v less >/dev/null 2>&1; then
      printf '%s\n' "$out" | less -R
    else
      clear 2>/dev/null || printf '\033c'
      printf '%s\n\n  %spress any key…%s' "$out" "$DD" "$DR"
      read -rsn1
    fi
    ;;

  find-interactive)
    cur="$(content_filter)"
    dlg "search snapshots"
    dlg_hint "match text inside snapshots (sessions, paths, commands) · empty clears"
    ask_prefill pat "pattern:" "$cur"
    if [ -z "$pat" ]; then
      rm -f "$FILTER_FILE"
    else
      printf '%s' "$pat" > "$FILTER_FILE"
    fi
    ;;

  write-back-interactive)
    # Bound to ctrl-w. Re-save the CURRENT (▶) profile from the live tmux state,
    # i.e. prefix+W from inside the popup. Overwrites the saved snapshot, so it
    # confirms first and shows saved→live counts. Uses --force to avoid the
    # backend's tmux confirm-before (a nested popup won't render in here).
    cur="$($NAMED_BIN current 2>/dev/null || true)"
    dlg "write back"
    if [ -z "$cur" ]; then
      dlg_hint "no current profile — restore one (enter) or save one (ctrl-s) first"
      printf '\n  %spress any key…%s' "$DD" "$DR"
      read -rsn1
      exit 0
    fi
    if [ ! -f "$NAMED_DIR/$cur.txt" ]; then
      dlg_hint "current profile '$cur' has no saved snapshot to overwrite"
      printf '\n  %spress any key…%s' "$DD" "$DR"
      read -rsn1
      exit 0
    fi
    read -r sns snw < <(parse_profile "$NAMED_DIR/$cur.txt" counts)
    # Live counts scoped to the profile's own sessions — write-back keeps the
    # profile's scope (save-current --profile-scope), so whole-server counts
    # would misrepresent what's about to be written.
    lns=0; lnw=0
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      if tmux has-session -t "=$s" 2>/dev/null; then
        lns=$((lns + 1))
        lnw=$((lnw + $(tmux list-windows -t "=$s" -F x 2>/dev/null | wc -l | tr -d ' ')))
      fi
    done < <(profile_sessions "$NAMED_DIR/$cur.txt")
    dlg_hint "overwrite this profile's snapshot from its live sessions"
    printf '\n  %s▶ %s%s   saved %ss·%sw  →  live %ss·%sw\n' "$DC" "$cur" "$DR" "$sns" "$snw" "$lns" "$lnw"
    printf '\n  %swrite back to "%s"?%s [y/N] ' "$DY" "$cur" "$DR"
    read -r a
    [ "$a" = y ] || [ "$a" = Y ] || exit 0
    "$NAMED_BIN" save-current --force
    ;;

  overwrite-interactive)
    # Bound to ctrl-o. Overwrite the HIGHLIGHTED profile with the live tmux
    # state — a targeted write-back for any profile, not just the current ▶
    # one. Lets a session started plain (`tmux`) be saved over an existing
    # profile without restoring it first. Confirms with saved→live counts and
    # shows what the profile currently holds, since this replaces it.
    name="${2:-}"
    [ -n "$name" ] || exit 0
    dlg "overwrite from live"
    if [ ! -f "$NAMED_DIR/$name.txt" ]; then
      dlg_hint "no profile '$name'"
      printf '\n  %spress any key…%s' "$DD" "$DR"
      read -rsn1
      exit 0
    fi
    dlg_hint "replace this profile's snapshot with the current live state"
    printf '\n'
    COLOR=1 parse_profile "$NAMED_DIR/$name.txt" collapsed | sed 's/^/  /'
    read -r sns snw < <(parse_profile "$NAMED_DIR/$name.txt" counts)
    # Per-session by default, matching save; the counts preview reflects the
    # chosen scope so the shrink/grow is visible before confirming.
    cur_sess="$(tmux display-message -p '#{client_session}' 2>/dev/null || true)"
    flag=""
    if [ -n "$cur_sess" ]; then
      printf '\n  %sscope — [c]urrent session "%s" or [a]ll sessions?%s [C/a] ' "$DC" "$cur_sess" "$DR"
      read -r sc
      case "$sc" in a|A) flag="--all" ;; esac
    fi
    if [ "$flag" = "--all" ] || [ -z "$cur_sess" ]; then
      lns="$(tmux list-sessions -F x 2>/dev/null | wc -l | tr -d ' ')"
      lnw="$(tmux list-windows -a -F x 2>/dev/null | wc -l | tr -d ' ')"
    else
      lns=1
      lnw="$(tmux list-windows -t "=$cur_sess" -F x 2>/dev/null | wc -l | tr -d ' ')"
    fi
    printf '\n  %s%s%s   saved %ss·%sw  →  live %ss·%sw\n' "$DC" "$name" "$DR" "$sns" "$snw" "$lns" "$lnw"
    printf '\n  %soverwrite "%s" with the live state?%s [y/N] ' "$DY" "$name" "$DR"
    read -r a
    [ "$a" = y ] || [ "$a" = Y ] || exit 0
    # --force: skip the backend's tmux confirm-before (nested popups don't
    # render in here) — this dialog already asked.
    # shellcheck disable=SC2086  # $flag intentionally empty or one word
    "$NAMED_BIN" save --force $flag "$name"
    ;;

  reopen)
    # Bound to ctrl-l (execute-silent + abort). tmux resolves the popup's
    # percentage size into absolute cells once, at open time, and on client
    # resize only ever SHRINKS a popup to fit (3.6's popup_resize_cb clamps,
    # never grows) — so a popup opened in a small terminal stays small after
    # maximizing. Close + reopen is the only way to re-apply the 70% geometry.
    # The typed filter query rides along via QUERY_FILE.
    printf '%s' "${2:-}" > "$QUERY_FILE"
    client="$(tmux display-message -p '#{client_name}' 2>/dev/null || true)"
    [ -n "$client" ] || { rm -f "$QUERY_FILE"; exit 0; }
    # -b: return immediately so fzf's abort can close THIS popup first; the
    # sleep lets it tear down (a popup can't open while one is still up).
    # Geometry mirrors the prefix+G binding in tmux.conf.
    # The trailing `; true` + redirects matter: display-popup -E blocks until
    # the NEW popup closes and returns its exit code — esc/ctrl-l abort with
    # 130 — and run-shell dumps any non-zero status ("'sleep 0.15; …'
    # returned 130") plus stderr ("popup already displayed" when ctrl-l is
    # spammed) straight into the pane behind the popup.
    tmux run-shell -b "sleep 0.15; tmux display-popup -c '$client' -E -w 70% -h 70% -T ' saved tmux sessions ' '$SELF' >/dev/null 2>&1; true"
    ;;

  pin-toggle)
    shift
    [ $# -gt 0 ] || exit 0
    for name in "$@"; do
      if [ -f "$PINS_FILE" ] && grep -qxF "$name" "$PINS_FILE" 2>/dev/null; then
        "$NAMED_BIN" unpin "$name"
      else
        "$NAMED_BIN" pin "$name"
      fi
    done
    ;;

  cycle-sort)
    case "$(sort_mode)" in
      name) set_sort mtime ;;
      *)    set_sort name  ;;
    esac
    ;;

  cycle-view)
    # active -> collapsed -> full -> active
    case "$(view_mode)" in
      active)    set_view collapsed ;;
      collapsed) set_view full      ;;
      *)         set_view active    ;;
    esac
    ;;

  keys-help)
    # Help shown via fzf's execute() (bound to `?`). The popup is short, so a
    # plain printf scrolls the top (NAVIGATION + ACTIONS) off-screen — pipe the
    # body through a pager so every key is reachable with ↑/↓ regardless of
    # popup height. Falls back to clear+printf if `less` is missing. (Nested
    # display-popups don't render inside a popup, so we own the popup's screen.)
    emit_help() {
      local t="keyboard shortcuts"
      row() { printf '     %s%-10s%s %s│%s %s\n' "$2" "$1" "$DR" "$DD" "$DR" "$3"; }
      printf '\n  %s┌─ %s%s%s %s%s%s\n' "$DD" "$DB" "$t" "$DR" "$DD" "${DRULE:$(( ${#t} + 4 ))}" "$DR"
      printf '\n  %sNAVIGATION%s\n' "$DB" "$DR"
      row type      "$DC" "filter the list"
      row up/down   "$DC" "move selection (ctrl-j / ctrl-k)"
      row pgup/dn   "$DC" "jump a page"
      row tab       "$DC" "toggle multi-select"
      row enter     "$DC" "restore profile (confirms first)"
      row sh-up/dn  "$DC" "scroll the preview pane"
      row '?'       "$DC" "show this help"
      row esc       "$DC" "close the popup"
      printf '\n  %sACTIONS%s\n' "$DB" "$DR"
      row ctrl-s "$DC" "save current session (or all) as a new profile"
      row ctrl-w "$DC" "write-back current ▶ profile (overwrite from live)"
      row ctrl-o "$DC" "overwrite highlighted profile from live state"
      row ctrl-r "$DC" "rename"
      row ctrl-x "$DC" "delete → trash (multi-select ok)"
      row ctrl-e "$DC" "set / clear description (multi ok)"
      row ctrl-y "$DC" "copy / duplicate profile"
      row ctrl-p "$DC" "pin / unpin (multi ok)"
      row ctrl-g "$DC" "search inside snapshots (filter)"
      row alt-d  "$DC" "diff two selected profiles"
      row ctrl-t "$DC" "cycle sort (recent ⇄ name)"
      row ctrl-l "$DC" "reopen popup (re-fit after terminal resize)"
      row alt-v  "$DC" "cycle preview (active/collapsed/full)"
      row ctrl-/ "$DC" "cycle preview pane (right/down/hidden)"
      printf '\n  %sMARKERS%s\n' "$DB" "$DR"
      printf '     %s▶%s current   %s*%s pinned   %s●%s session   %s*%s after the name = live drifted\n' "$DC" "$DR" "$DY" "$DR" "$DC" "$DR" "$DY" "$DR"
      printf '\n  %sFROM TMUX%s\n' "$DB" "$DR"
      row prefix+G "$DY" "open this picker"
      row prefix+S "$DY" "save current state (named)"
      row prefix+R "$DY" "restore a named profile"
      row prefix+L "$DY" "restore most recent"
      row prefix+W "$DY" "write-back current profile"
      row prefix+D "$DY" "delete a profile"
      printf '\n  %sMORE (CLI: resurrect-named.sh)%s\n' "$DB" "$DR"
      printf '     %sexport · import · prune · find · diff · untrash%s\n' "$DD" "$DR"
      printf '\n  %s└%s%s\n' "$DD" "$DRULE" "$DR"
    }
    if command -v less >/dev/null 2>&1; then
      # -R: keep colors · custom prompt instead of less's ':' · no -F so it
      # always pages (waits) even when the content happens to fit one screen.
      emit_help | less -R -P'  ↑/↓ scroll  ·  q to close '
    else
      clear 2>/dev/null || printf '\033c'
      emit_help
      printf '\n  %spress any key to close…%s' "$DD" "$DR"
      read -rsn1
    fi
    ;;

  menu|*)
    if ! command -v fzf >/dev/null 2>&1; then
      printf '\n  fzf is not installed.\n  Install it (sudo apt install -y fzf), then reopen.\n\n'
      read -rsn1 -p "  press any key to close…"
      exit 0
    fi
    # The content filter is transient — don't let a stale one from a previous
    # popup hide profiles on the next open. Exception: a ctrl-l reopen bounce
    # (QUERY_FILE present) is the same "session" continuing, so it keeps both
    # the ctrl-g filter and the typed query.
    query=""
    if [ -f "$QUERY_FILE" ]; then
      query="$(cat "$QUERY_FILE" 2>/dev/null || true)"
      rm -f "$QUERY_FILE"
    else
      rm -f "$FILTER_FILE"
    fi
    if [ -z "$("$SELF" rows)" ]; then
      printf '\n  No saved profiles yet.\n\n'
      printf '  Save the current tmux state with  prefix + S  (named save),\n'
      printf '  or reopen this popup and press  ctrl-s  to name + save.\n\n'
      read -rsn1 -p "  press any key to close…"
      exit 0
    fi
    # Popup width at open time — threaded into rows so columns can be responsive
    # (the popup doesn't resize mid-session, so capturing it once is enough).
    cols="$(tput cols 2>/dev/null || echo 80)"
    # Header (key hints + live count/sort state) comes from the `header`
    # subcommand so the binds below can refresh it via transform-header.
    header="$("$SELF" header)"
    COLS="$cols" COLOR=1 "$SELF" rows | COLS="$cols" COLOR=1 fzf \
      --delimiter='\t' \
      --with-nth=2.. \
      --no-sort \
      --reverse \
      --ansi \
      --multi \
      --marker='+' \
      --header="$header" \
      --query="$query" \
      --preview="COLOR=1 $SELF preview {1}" \
      --preview-window='down,55%,wrap' \
      --bind="enter:become($SELF restore-interactive {1})" \
      --bind="ctrl-s:execute($SELF save-interactive)+reload(COLS=$cols COLOR=1 $SELF rows)+transform-header($SELF header)" \
      --bind="ctrl-w:execute($SELF write-back-interactive)+reload(COLS=$cols COLOR=1 $SELF rows)+refresh-preview" \
      --bind="ctrl-o:execute($SELF overwrite-interactive {1})+reload(COLS=$cols COLOR=1 $SELF rows)+refresh-preview" \
      --bind="ctrl-r:execute($SELF rename-interactive {1})+reload(COLS=$cols COLOR=1 $SELF rows)" \
      --bind="ctrl-x:execute($SELF delete-interactive {+1})+reload(COLS=$cols COLOR=1 $SELF rows)+transform-header($SELF header)" \
      --bind="ctrl-e:execute($SELF describe-interactive {+1})+reload(COLS=$cols COLOR=1 $SELF rows)" \
      --bind="ctrl-y:execute($SELF copy-interactive {1})+reload(COLS=$cols COLOR=1 $SELF rows)+transform-header($SELF header)" \
      --bind="alt-d:execute($SELF diff-interactive {+1})" \
      --bind="ctrl-g:execute($SELF find-interactive)+reload(COLS=$cols COLOR=1 $SELF rows)+transform-header($SELF header)" \
      --bind="ctrl-p:execute-silent($SELF pin-toggle {+1})+reload(COLS=$cols COLOR=1 $SELF rows)" \
      --bind="ctrl-t:execute-silent($SELF cycle-sort)+reload(COLS=$cols COLOR=1 $SELF rows)+transform-header($SELF header)" \
      --bind="ctrl-l:execute-silent($SELF reopen {q})+abort" \
      --bind="alt-v:execute-silent($SELF cycle-view)+refresh-preview" \
      --bind="ctrl-/:change-preview-window(right,60%|down,40%|hidden|down,55%)" \
      --bind="shift-up:preview-up" \
      --bind="shift-down:preview-down" \
      --bind="?:execute($SELF keys-help)"
    ;;
esac
