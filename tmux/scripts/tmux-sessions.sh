#!/usr/bin/env bash
# tmux-sessions — type this to open the session/profile picker BEFORE attaching,
# so a tmux session is created only when you choose one. No throwaway session is
# left behind (the usual `tmux` → prefix+G dance leaves an empty session around).
#
# Companion to resurrect-menu.sh / resurrect-named.sh:
#   inside tmux   -> opens the saved-profiles popup (identical to prefix + G)
#   outside tmux  -> an fzf list of live sessions (if any) + saved profiles +
#                    "[ + new blank session ]". enter attaches / restores / starts.
#                    Popup-parity keys: ctrl-x delete profile / kill live session,
#                    ctrl-s save, ctrl-o overwrite profile from live state,
#                    ctrl-r rename, ctrl-e describe, ctrl-y copy, ctrl-p pin,
#                    ctrl-t sort, alt-v preview view, ? help.
#
# Restoring a profile from a cold start uses a throwaway "_ts_boot" session only
# to give tmux-resurrect a server to restore into, then kills it before
# attaching — so nothing redundant survives.
#
# Subcommands (internal):
#   (none)               the launcher itself (picks a row, then acts on it)
#   rows                 emit the fzf rows (used for the initial list + reload)
#   preview-row TYPE ID  render the preview pane (used by fzf --preview)
#   delete-row TYPE ID   confirm + delete a profile / kill a session (ctrl-x)
#   act-row ACT TYPE ID  route the other popup-parity actions (see above)
#   keys-help            launcher key reference (used by ?)
set -euo pipefail

# A non-interactive shell may not have ~/.local/bin on PATH; make fzf reachable.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac

NAMED_BIN="$HOME/.tmux/scripts/resurrect-named.sh"
MENU_BIN="$HOME/.tmux/scripts/resurrect-menu.sh"
SELF="$HOME/.tmux/scripts/tmux-sessions.sh"
NAMED_DIR="$("$NAMED_BIN" dir 2>/dev/null || true)"
BOOT='_ts_boot' # transient session used only to host a restore
# The popup persists a content filter here; ignore any stale one when listing.
FILTER_FILE="${TMPDIR:-/tmp}/resurrect-menu-filter.${USER:-$(id -u)}"

if [ -n "${NO_COLOR:-}" ]; then
  cyan=
  dim=
  bold=
  rst=
else
  cyan=$'\x1b[1;36m'
  dim=$'\x1b[2m'
  bold=$'\x1b[1m'
  rst=$'\x1b[0m'
fi

# True if a tmux server with at least one session is running.
have_sessions() { tmux list-sessions >/dev/null 2>&1; }

# Print a fake $TMUX (sock,pid,session-id) pointing at the running server, so
# resurrect-named.sh's need_tmux passes and the resurrect scripts target the
# right socket from outside tmux. Fails (rc 1) when no server is up.
server_env() {
  have_sessions || return 1
  local anchor sock pid sid
  anchor="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || true)"
  sock="$(tmux display-message -p -t "$anchor" '#{socket_path}' 2>/dev/null || true)"
  pid="$(tmux display-message -p -t "$anchor" '#{pid}' 2>/dev/null || true)"
  sid="$(tmux display-message -p -t "$anchor" '#{session_id}' 2>/dev/null | tr -d '$' || true)"
  { [ -n "$sock" ] && [ -n "$pid" ]; } || return 1
  printf '%s,%s,%s' "$sock" "$pid" "${sid:-0}"
}

# Full-screen one-liner notice + keypress (the launcher owns the terminal).
say_na() { # $1=text
  clear 2>/dev/null || printf '\033c'
  printf '\n  %s%s%s\n\n  %spress any key…%s' "$dim" "$1" "$rst" "$dim" "$rst"
  read -rsn1
}

# fzf rows for live sessions, most-recently-active first.
# Row format (tab-separated): <type>\t<id>\t<display>
live_rows() {
  have_sessions || return 0
  local last name nwin att tag
  while IFS=$'\t' read -r last name nwin att; do
    [ "$name" = "$BOOT" ] && continue
    tag=""
    [ "$att" = 1 ] && tag="   ${dim}(attached)${rst}"
    printf 'sess\t%s\t %s●%s %s   %s%s win%s%s\n' \
      "$name" "$cyan" "$rst" "$name" "$dim" "$nwin" "$rst" "$tag"
  done < <(tmux list-sessions -F '#{session_last_attached}	#{session_name}	#{session_windows}	#{?session_attached,1,0}' 2>/dev/null | sort -rn || true)
}

# fzf rows for saved profiles — reuse the popup's row renderer for a consistent
# look (markers/counts/age), re-tagged with the 'prof' type.
profile_rows() {
  [ -n "$NAMED_DIR" ] && [ -d "$NAMED_DIR" ] || return 0
  rm -f "$FILTER_FILE" # don't let a stale popup filter hide profiles
  local name disp
  while IFS=$'\t' read -r name disp; do
    [ -n "$name" ] || continue
    printf 'prof\t%s\t%s\n' "$name" "$disp"
  done < <(COLS="${cols:-80}" COLOR=1 "$MENU_BIN" rows 2>/dev/null || true)
}

# An inert section-header row (type 'hdr'): a bold label + a dim rule. `pick`
# ignores it so selecting one is a harmless no-op; it filters out when you
# search. Headers are emitted only for groups that actually have items.
hdr_row() { # $1=label
  printf 'hdr\t\t%s%s%s %s────────────────────────────%s\n' "$bold" "$1" "$rst" "$dim" "$rst"
}

list_rows() {
  local live prof
  live="$(live_rows)"
  prof="$(profile_rows)"
  if [ -n "$live" ]; then
    hdr_row "CURRENT SESSIONS"
    printf '%s\n' "$live"
  fi
  if [ -n "$prof" ]; then
    [ -n "$live" ] && printf 'hdr\t\t\n' # blank spacer between the two groups
    hdr_row "SAVED SESSIONS"
    printf '%s\n' "$prof"
  fi
  printf 'new\t__new__\t %s+ new blank session%s\n' "$dim" "$rst"
}

# Restore a profile and attach, leaving no throwaway session behind.
boot_restore() {
  # NB: separate `local`s — in one statement (`local prof=$1 file=...$prof`)
  # the second RHS expands $prof before it's assigned (unbound under set -u).
  local prof="$1"
  local file="$NAMED_DIR/$prof.txt"
  [ -f "$file" ] || exec tmux new-session
  local created=0
  if ! have_sessions; then
    tmux new-session -d -s "$BOOT"
    created=1
  fi
  # Give the restore wrapper a tmux context ($TMUX) pointing at the running
  # server, so it passes need_tmux and restore.sh targets the right socket.
  TMUX="$(server_env || true)" "$NAMED_BIN" restore "$prof" >/dev/null 2>&1 || true
  # Prefer the snapshot's active session; fall back to any restored one.
  local target
  target="$(awk -F'\t' '$1=="state"{print $2; exit}' "$file" 2>/dev/null || true)"
  [ "$created" = 1 ] && tmux kill-session -t "$BOOT" 2>/dev/null || true
  if [ -z "$target" ] || ! tmux has-session -t "$target" 2>/dev/null; then
    target="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -vx "$BOOT" | head -1 || true)"
  fi
  if [ -n "$target" ]; then exec tmux attach -t "$target"; else exec tmux new-session; fi
}

case "${1:-menu}" in
rows)
  # Emit the picker rows. Width comes from fzf's live size on reload
  # (FZF_COLUMNS), or the terminal at first launch.
  cols="${FZF_COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
  list_rows
  ;;

delete-row)
  # ctrl-x: on a saved profile, soft-delete to trash (popup's dialog); on a
  # live session, confirm + kill it — startup is where dead sessions get
  # cleaned out, so this beats the old "profiles only" notice.
  case "${2:-}" in
  prof) "$MENU_BIN" delete-interactive "${3:-}" ;;
  sess)
    clear 2>/dev/null || printf '\033c'
    printf '\n  %s●%s %s\n' "$cyan" "$rst" "${3:-}"
    tmux list-windows -t "=${3:-}" -F '   #{window_index}: #{window_name} (#{window_panes}p)' 2>/dev/null || true
    printf '\n  %skill this live session? (not saved anywhere unless you saved it)%s [y/N] ' "$bold" "$rst"
    read -r a
    if [ "$a" = y ] || [ "$a" = Y ]; then
      tmux kill-session -t "=${3:-}" 2>/dev/null || true
    fi
    ;;
  *) : ;;
  esac
  ;;

act-row)
  # Popup-parity actions (ctrl-r/e/y/p/s/o). Profile actions reuse
  # resurrect-menu.sh's dialogs — pure file ops, fine outside tmux.
  # save/overwrite snapshot the LIVE server, so they run with a faked $TMUX
  # (same trick as boot_restore) and need a server to exist.
  act="${2:-}"
  rtype="${3:-}"
  rid="${4:-}"
  case "$act" in
  rename | describe | copy)
    if [ "$rtype" = prof ]; then
      "$MENU_BIN" "$act-interactive" "$rid"
    elif [ "$rtype" = sess ]; then
      say_na "ctrl-r / ctrl-e / ctrl-y act on saved profiles — \"$rid\" is a live session."
    fi
    ;;
  pin)
    # Instant, no dialog — silently ignore non-profile rows.
    if [ "$rtype" = prof ]; then "$MENU_BIN" pin-toggle "$rid" 2>/dev/null || true; fi
    ;;
  save)
    if env="$(server_env)"; then
      TMUX="$env" "$MENU_BIN" save-interactive
    else
      say_na "no running tmux server — start a session first, then save it."
    fi
    ;;
  overwrite)
    if [ "$rtype" != prof ]; then
      say_na "ctrl-o overwrites a saved profile from the live state — pick a profile row."
    elif env="$(server_env)"; then
      TMUX="$env" "$MENU_BIN" overwrite-interactive "$rid"
    else
      say_na "no running tmux server — nothing to overwrite from."
    fi
    ;;
  esac
  ;;

keys-help)
  clear 2>/dev/null || printf '\033c'
  printf '\n  %stmux-sessions — keys%s\n\n' "$bold" "$rst"
  printf '   %senter %s  attach (live) · restore (saved) · start (new)\n' "$cyan" "$rst"
  printf '   %sctrl-x%s  delete saved profile → trash · kill live session\n' "$cyan" "$rst"
  printf '   %sctrl-s%s  save the live server state as a new profile\n' "$cyan" "$rst"
  printf '   %sctrl-o%s  overwrite highlighted profile from the live state\n' "$cyan" "$rst"
  printf '   %sctrl-r%s  rename profile\n' "$cyan" "$rst"
  printf '   %sctrl-e%s  set / clear profile description\n' "$cyan" "$rst"
  printf '   %sctrl-y%s  copy / duplicate profile\n' "$cyan" "$rst"
  printf '   %sctrl-p%s  pin / unpin profile (pinned sort to the top)\n' "$cyan" "$rst"
  printf '   %sctrl-t%s  cycle sort (recent ⇄ name)\n' "$cyan" "$rst"
  printf '   %salt-v %s  cycle preview (active/collapsed/full)\n' "$cyan" "$rst"
  printf '   %sesc   %s  back to the shell\n' "$cyan" "$rst"
  printf '\n  %sinside tmux this command opens the popup instead (prefix+G).%s' "$dim" "$rst"
  printf '\n\n  %spress any key…%s' "$dim" "$rst"
  read -rsn1
  ;;

preview-row)
  type="${2:-}"
  id="${3:-}"
  case "$type" in
  prof) COLOR=1 "$MENU_BIN" preview "$id" ;;
  sess)
    printf '%s●%s %s\n\n' "$cyan" "$rst" "$id"
    tmux list-windows -t "$id" -F '   #{window_index}: #{window_name} (#{window_panes}p)#{?window_active, ←active,}' 2>/dev/null || true
    ;;
  new) printf 'Start a brand-new, empty tmux session.\n' ;;
  hdr) : ;; # nothing to preview for a header/spacer
  esac
  ;;

menu | *)
  # Already inside tmux → open the existing popup, same as prefix + G.
  if [ -n "${TMUX:-}" ]; then
    exec tmux display-popup -E -w 70% -h 70% -T ' saved tmux sessions ' "$MENU_BIN"
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    printf 'tmux-sessions: fzf not found — starting a plain session.\n' >&2
    exec tmux new-session
  fi
  # Nothing to choose (no server, no profiles) → just start fresh.
  if ! have_sessions && { [ -z "$NAMED_DIR" ] || ! ls "$NAMED_DIR"/*.txt >/dev/null 2>&1; }; then
    exec tmux new-session
  fi
  # Sections are labelled in the list itself, so keep the top hint to one line.
  header="$(printf '%senter%s open · %sctrl-x%s delete/kill · %s?%s all keys · %sesc%s shell · type to filter' "$cyan" "$rst" "$cyan" "$rst" "$cyan" "$rst" "$cyan" "$rst")"
  # Capture the choice, then act in THIS process — it owns the real terminal.
  # (`become`+`exec tmux` inherits fzf's piped stdin and dies with
  #  "open terminal failed: can't use /dev/tty" when attaching a client.)
  # enter only `accept`s on a real row; on a header/spacer it's a no-op.
  # ctrl-x deletes the highlighted saved profile and reloads (stays in the picker).
  sel="$("$SELF" rows | fzf \
    --delimiter='\t' \
    --with-nth=3 \
    --ansi \
    --no-sort \
    --reverse \
    --header="$header" \
    --preview="$SELF preview-row {1} {2}" \
    --preview-window='down,55%,wrap' \
    --bind="start:down" \
    --bind="ctrl-x:execute($SELF delete-row {1} {2})+reload($SELF rows)" \
    --bind="ctrl-s:execute($SELF act-row save {1} {2})+reload($SELF rows)" \
    --bind="ctrl-o:execute($SELF act-row overwrite {1} {2})+reload($SELF rows)+refresh-preview" \
    --bind="ctrl-r:execute($SELF act-row rename {1} {2})+reload($SELF rows)" \
    --bind="ctrl-e:execute($SELF act-row describe {1} {2})+reload($SELF rows)" \
    --bind="ctrl-y:execute($SELF act-row copy {1} {2})+reload($SELF rows)" \
    --bind="ctrl-p:execute-silent($SELF act-row pin {1} {2})+reload($SELF rows)" \
    --bind="ctrl-t:execute-silent($MENU_BIN cycle-sort)+reload($SELF rows)" \
    --bind="alt-v:execute-silent($MENU_BIN cycle-view)+refresh-preview" \
    --bind="?:execute($SELF keys-help)" \
    --bind="enter:transform([ {1} = hdr ] || echo accept)")" || exit 0
  [ -n "$sel" ] || exit 0
  ttype="$(printf '%s\n' "$sel" | cut -f1)"
  tid="$(printf '%s\n' "$sel" | cut -f2)"
  case "$ttype" in
  sess) exec tmux attach -t "$tid" ;;
  prof) boot_restore "$tid" ;;
  new) exec tmux new-session ;;
  hdr) exec "$SELF" ;; # safety: a header slipped through → reopen
  *) exit 0 ;;
  esac
  ;;
esac
