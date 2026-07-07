#!/usr/bin/env bash
# Named tmux-resurrect profiles.
#
# tmux-resurrect saves the whole tmux server into one snapshot and points
# `last` at it; restore always reads `last`. This wraps resurrect's own
# save.sh/restore.sh so you can keep several *named* snapshots — each with
# an optional description and pin — and restore any one of them on demand.
#
# Deleting a profile moves it to a `.trash/` sidecar (recoverable with
# `untrash`) rather than removing it outright. Run `resurrect-named.sh help`
# for the full command reference.
set -euo pipefail

print_help() {
  cat <<'HELP'
Named tmux-resurrect profiles.

Usage:
  save [--force] [--all] [--session <s>] <name>
                                snapshot the CURRENT SESSION as <name>
                                (--all: every session on the server;
                                 --session <s>: a specific session)
  restore <name>                restore the <name> snapshot (merges into
                                the running server)
  rename <old> <new>            rename a saved profile (and metadata)
  list                          list saved profile names
  delete <name>                 move a profile to trash (recoverable)
  exists <name>                 exit 0 if profile exists
  dir                           print the named-profiles directory

  describe <name> <text...>     set the one-line description for <name>
                                (omit text to clear it)
  description <name>            print the description for <name>
  copy <src> <dst> [--force]    duplicate a profile (with its description)
  prune [--older-than N] [--dry-run]
                                delete profiles older than N days (default 30,
                                skipping pinned profiles); also sweeps trash

  trash                         list profiles currently in the trash
  untrash <name>                restore the most recently trashed <name>
  empty-trash [--older-than N]  permanently remove trashed items (older than N
                                days, or all of them if N is omitted)

  pin <name>                    mark <name> as pinned (sorted to top)
  unpin <name>                  remove pin from <name>
  pins                          list pinned profiles
  pinned <name>                 exit 0 if <name> is pinned

  find <pattern>                list profiles whose snapshot matches <pattern>
  diff <a> <b>                  show structural differences between two profiles
  dry-run <name>                print what `restore <name>` would do

  export <name> [path] [--force]
                                tar up <name> (+ .desc + pin) into [path]
  import <file> [--force]       extract a tar produced by `export`

  current                       print the current profile (last save/restore)
  restore-current               restore the current profile
  save-current [--force]        re-save the current profile from live state,
                                keeping the profile's own session scope
  restore-recent                restore the most recently saved profile
  auto-write-back               for the client-detached hook: silently re-save
                                the current profile if the live state drifted

  help                          this message

Notes:
  - Profiles are PER-SESSION by default: save captures only the session you
    are in, so each profile maps to one project. Use --all for a snapshot of
    the whole server. Overwriting an existing profile keeps its session scope.
  - save renames tmux's auto-named numeric sessions ("0", "1", …) to the
    profile name, so different profiles never collide on default session
    names at restore time (restore merges into same-named live sessions).
  - Overwriting a profile stashes the previous snapshot in the trash first
    (recover: delete the profile, then `untrash <name>`).

Hooks (configure in tmux.conf):
  set -g @resurrect-pre-save     '<shell command>'   # runs before save
  set -g @resurrect-post-restore '<shell command>'   # runs after restore
  PROFILE=<name> is exported into the hook environment.
  set -g @resurrect-autosave-on-detach '0'           # disable auto-write-back

Status line:
  #{@resurrect-current}        -> current profile name (set on save/restore).
  status-indicator [marker]    -> prints <marker> (default '*') when the live
                                  tmux state has drifted from the current
                                  profile; nothing if in sync. For status-right.
HELP
}

# Resolve the resurrect dir the same way the plugin does (mirrors helpers.sh
# upstream), so our copy/restore always targets the files save.sh/restore.sh
# actually read and write.
resurrect_dir() {
  local opt
  opt="$(tmux show-option -gqv '@resurrect-dir' 2>/dev/null || true)"
  if [ -n "$opt" ]; then
    opt="${opt/#\~/$HOME}"
    printf '%s' "${opt//\$HOME/$HOME}"
  else
    printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
  fi
}

RESURRECT_DIR="${RESURRECT_DIR:-$(resurrect_dir)}"
NAMED_DIR="$RESURRECT_DIR/named"
TRASH_DIR="$NAMED_DIR/.trash"
PINS_FILE="$NAMED_DIR/.pins"
LOCK_FILE="$NAMED_DIR/.lock"
SELF="$HOME/.tmux/scripts/resurrect-named.sh"
MENU="$HOME/.tmux/scripts/resurrect-menu.sh"
PLUGIN_DIR="$HOME/.tmux/plugins/tmux-resurrect/scripts"
SAVE_SH="$PLUGIN_DIR/save.sh"
RESTORE_SH="$PLUGIN_DIR/restore.sh"

# Send user-facing messages to tmux when possible; fall back to stderr so we
# never pollute stdout (need_name and friends return values via stdout).
msg() { tmux display-message "resurrect: $*" 2>/dev/null || printf 'resurrect: %s\n' "$*" >&2; }

# Report a fatal error and stop. Without this, a command failing under `set -e`
# would kill the script *before* any message — silent death on exactly the
# operations (save/restore) where feedback matters most.
die() { msg "$*"; exit 1; }

# Filesystem-safe names: anything outside [A-Za-z0-9._-] is collapsed to '_'.
sanitize() { printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '_'; }

# Resolve <raw> -> <sanitized> on stdout. Warns if sanitization changed it;
# rejects empty, reserved, or dot-only names. Use inside command substitution.
need_name() {
  local raw="$1" role="$2" name
  [ -n "$raw" ] || die "$role needs a name"
  name="$(sanitize "$raw")"
  [ -n "$name" ] || die "$role: invalid name"
  case "$name" in
    last)  die "$role: 'last' is reserved by tmux-resurrect" ;;
    .|..)  die "$role: '$name' is not a valid profile name" ;;
    # A leading dot would hide the file from every '*.txt' glob (the menu,
    # list, prune, find) while still existing on disk — a ghost profile.
    .*)    die "$role: profile names can't start with '.'" ;;
  esac
  [ "$name" = "$raw" ] || msg "name sanitized to '$name'"
  printf '%s' "$name"
}

need_plugin() {
  if [ ! -x "$SAVE_SH" ] || [ ! -x "$RESTORE_SH" ]; then
    msg "tmux-resurrect plugin not found at $PLUGIN_DIR"
    die "install it (TPM: prefix + I) or adjust the path in this script"
  fi
}

# Refuse save/restore from outside tmux. resurrect's restore.sh derives the
# server socket from `$TMUX`; when it's empty, it runs `tmux -S "" new-session`
# which spawns an orphan server, then crashes mid-restore and leaves the
# "Restoring..." spinner looping forever. The only safe place to invoke
# save.sh/restore.sh is from a tmux client (e.g. via run-shell from a binding).
need_tmux() {
  if [ -z "${TMUX:-}" ]; then
    die "this command must be run from inside a tmux session"
  fi
}

# Count distinct sessions and windows in a snapshot. Pure awk — no Python.
# Field map from save.sh: $1=record type, $2=session, $3=window_index.
counts() { # $1=file ; prints "<sessions> <windows>"
  awk -F'\t' '
    $1=="pane" || $1=="window" { sess[$2]=1; win[$2 SUBSEP $3]=1 }
    END {
      ns=0; for (s in sess) ns++
      nw=0; for (w in win)  nw++
      print ns, nw
    }
  ' "$1"
}

pluralize() { # $1=count $2=word ; prints "<n> word[s]"
  if [ "$1" = "1" ]; then printf '%s %s' "$1" "$2"
  else                    printf '%s %ss' "$1" "$2"; fi
}

set_current() { tmux set-option -g '@resurrect-current' "$1" 2>/dev/null || true; }
get_current() { tmux show-option -gqv '@resurrect-current' 2>/dev/null || true; }

# Run an optional user hook. The hook command is whatever string the user
# stored in the named tmux option; we exec it via sh with PROFILE in env.
run_hook() { # $1=option name (e.g. @resurrect-pre-save) ; remaining=env KEY=VAL
  local opt="$1"; shift
  local cmd
  cmd="$(tmux show-option -gqv "$opt" 2>/dev/null || true)"
  [ -n "$cmd" ] || return 0
  env "$@" sh -c "$cmd" || msg "hook $opt failed"
}

is_pinned() { [ -f "$PINS_FILE" ] && grep -qxF "$1" "$PINS_FILE"; }

# Rename an auto-named (all-digit) session to a profile-derived name; other
# names pass through. Prints the session's (possibly new) name. tmux's
# numeric defaults collide across profiles — restore merges a snapshot into
# any live session with the same name, so "0" saved twice under different
# profiles would clobber on restore.
rename_for_profile() { # $1=session $2=profile-derived base name
  local s="$1" base="$2" new
  case "$s" in ''|*[!0-9]*) printf '%s' "$s"; return 0 ;; esac
  [ "$s" = "$base" ] && { printf '%s' "$s"; return 0; }
  new="$base"
  if tmux has-session -t "=$new" 2>/dev/null; then new="$base-$s"; fi
  if tmux rename-session -t "=$s" "$new" 2>/dev/null; then
    printf '%s' "$new"
  else
    printf '%s' "$s"
  fi
}

# Remove a pin entry safely (no-op if not present). Removes the file entirely
# when the last pin is dropped, so an empty .pins file never lingers.
unpin_name() {
  [ -f "$PINS_FILE" ] || return 0
  if grep -qxF "$1" "$PINS_FILE"; then
    local tmp; tmp="$(mktemp)"
    # grep -v exits 1 when the result is empty (valid: last pin unpinned);
    # swallow that exit code so the rewrite still happens.
    { grep -vxF "$1" "$PINS_FILE" || true; } > "$tmp"
    if [ -s "$tmp" ]; then
      mv "$tmp" "$PINS_FILE"
    else
      rm -f "$tmp" "$PINS_FILE"
    fi
  fi
}

# Move a profile (and its description) into the trash, timestamped so repeated
# deletes of the same name don't collide. Soft-delete: recoverable via untrash.
trash_profile() { # $1=name
  local n="$1" ts
  ts="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$TRASH_DIR"
  if [ -f "$NAMED_DIR/$n.txt" ]; then
    mv -f "$NAMED_DIR/$n.txt" "$TRASH_DIR/$n.$ts.txt"
    # Reset the mtime so the trash-age clock starts at deletion time. mv keeps
    # the original mtime, so a profile pruned *because* it's old would otherwise
    # be swept by the trash retention sweep the instant it lands in the trash.
    touch "$TRASH_DIR/$n.$ts.txt" 2>/dev/null || true
  fi
  if [ -f "$NAMED_DIR/$n.desc" ]; then
    mv -f "$NAMED_DIR/$n.desc" "$TRASH_DIR/$n.$ts.desc"
    touch "$TRASH_DIR/$n.$ts.desc" 2>/dev/null || true
  fi
  return 0
}

# Single place that retires a profile: trash its files, drop its pin, and clear
# the current pointer if it named this profile. delete and prune both call this
# so cleanup can never diverge between them (and never leaves a dangling
# @resurrect-current pointing at a profile that no longer exists).
remove_profile() { # $1=name
  local n="$1"
  trash_profile "$n"
  unpin_name "$n"
  [ "$(get_current)" = "$n" ] && set_current "" || true
  return 0
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  save)
    force=0; all=0; pscope=0; scope_arg=""
    while :; do
      case "${1:-}" in
        --force)         force=1; shift ;;
        --all)           all=1; shift ;;
        --profile-scope) pscope=1; shift ;;   # keep the existing profile's sessions
        --session)       scope_arg="${2:-}"; shift 2 ;;
        --session=*)     scope_arg="${1#*=}"; shift ;;
        *) break ;;
      esac
    done
    name="$(need_name "${1:-}" save)"
    need_plugin
    need_tmux
    target="$NAMED_DIR/$name.txt"
    if [ -e "$target" ] && [ "$force" != 1 ]; then
      if [ -n "${TMUX:-}" ]; then
        flags="--force"
        [ "$all" = 1 ] && flags="$flags --all"
        [ "$pscope" = 1 ] && flags="$flags --profile-scope"
        [ -n "$scope_arg" ] && flags="$flags --session=$scope_arg"
        tmux confirm-before -p "profile '$name' exists — overwrite? (y/n)" \
          "run-shell '$SELF save $flags $name'"
        exit 0
      fi
      msg "profile '$name' exists (use --force to overwrite)"
      exit 0
    fi
    mkdir -p "$NAMED_DIR" || die "could not create $NAMED_DIR"
    # Scope: a profile captures ONE session by default (per-project snapshots;
    # a whole-server save silently drags every open project into the profile).
    # Resolution order:
    #   --all            whole server
    #   --session <s>    that session
    #   --profile-scope  the sessions the existing snapshot already holds
    #                    (write-back path: never let the client's current
    #                    session leak into a different project's profile)
    #   client session   whatever session the invoking client is on
    #   fallback         whole server (no client, e.g. launcher save)
    scope_sess=""; scope_from_target=0
    if [ "$all" != 1 ]; then
      if [ -n "$scope_arg" ]; then
        tmux has-session -t "=$scope_arg" 2>/dev/null || die "save: no session '$scope_arg'"
        scope_sess="$scope_arg"
      elif [ "$pscope" = 1 ] && [ -f "$target" ]; then
        scope_from_target=1
      else
        scope_sess="$(tmux display-message -p '#{client_session}' 2>/dev/null || true)"
        if [ -z "$scope_sess" ]; then
          if [ "$pscope" != 1 ] && [ -f "$target" ]; then scope_from_target=1; else all=1; fi
        fi
      fi
    fi
    # Rename auto-named numeric sessions to a profile-derived name before
    # snapshotting — the LIVE session, not just the file, because the
    # status-indicator drift check compares live names against saved ones.
    base="${name//[.:]/_}"        # '.' and ':' are invalid in session names
    renamed=""
    if [ "$all" = 1 ]; then
      while IFS= read -r s; do
        new="$(rename_for_profile "$s" "$base")"
        [ "$new" != "$s" ] && renamed="$renamed $s→$new"
      done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
    elif [ -n "$scope_sess" ]; then
      new="$(rename_for_profile "$scope_sess" "$base")"
      [ "$new" != "$scope_sess" ] && renamed=" $scope_sess→$new"
      scope_sess="$new"
    fi
    # Serialize concurrent saves so two clients don't race on `last`. The
    # native `prefix + Ctrl-s` and tmux-continuum's auto-save call save.sh
    # *without* this lock, so keep @continuum-save-interval '0' (see tmux.conf)
    # to avoid a background writer clobbering `last` between save.sh and cp.
    locked=0
    if command -v flock >/dev/null 2>&1; then
      if exec 9>>"$LOCK_FILE" && flock 9; then locked=1; else msg "warning: could not acquire save lock; continuing"; fi
    else
      msg "note: flock not found — saving without a concurrency lock"
    fi
    run_hook '@resurrect-pre-save' "PROFILE=$name"
    if ! SCRIPT_OUTPUT="quiet" "$SAVE_SH"; then
      [ "$locked" = 1 ] && flock -u 9 || true
      die "resurrect save.sh failed — nothing saved for '$name'"
    fi
    # Undo copy: stash the snapshot being overwritten in the trash
    # (recover with: delete <name>, then untrash <name>).
    if [ -e "$target" ]; then
      mkdir -p "$TRASH_DIR"
      cp -f "$target" "$TRASH_DIR/$name.$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
    fi
    # save.sh returns before `last` is always visible to an immediate reader
    # (symlink swap); give it a beat rather than dying on a transient.
    if [ ! -r "$RESURRECT_DIR/last" ]; then
      sleep 0.3
      [ -r "$RESURRECT_DIR/last" ] || { [ "$locked" = 1 ] && flock -u 9 || true; die "save.sh left no snapshot for '$name'"; }
    fi
    # Capture from `last` into the profile, filtered to the chosen scope.
    # Snapshot record fields: $1=type, $2=session. The `state` record names
    # the client's session for restore's switch-client — point it inside the
    # kept set so restoring never jumps to an unrelated session.
    captured=1
    if [ "$all" = 1 ]; then
      cp -L "$RESURRECT_DIR/last" "$target.new" 2>/dev/null || captured=0
    elif [ "$scope_from_target" = 1 ]; then
      awk -F'\t' -v OFS='\t' '
        NR==FNR { if ($1=="pane" || $1=="window") keep[$2]=1; next }
        $1=="pane" || $1=="window" || $1=="grouped_session" { if ($2 in keep) print; next }
        $1=="state" { if ($2 in keep) print "state", $2
                      else for (s in keep) { print "state", s; break }
                      next }
        { print }
      ' "$target" "$RESURRECT_DIR/last" > "$target.new" || captured=0
    else
      awk -F'\t' -v OFS='\t' -v s="$scope_sess" '
        $1=="pane" || $1=="window" || $1=="grouped_session" { if ($2 == s) print; next }
        $1=="state" { print "state", s; next }
        { print }
      ' "$RESURRECT_DIR/last" > "$target.new" || captured=0
    fi
    if [ "$captured" != 1 ] || [ ! -s "$target.new" ]; then
      rm -f "$target.new"
      [ "$locked" = 1 ] && flock -u 9 || true
      die "could not capture snapshot for '$name'"
    fi
    mv -f "$target.new" "$target"
    [ "$locked" = 1 ] && flock -u 9 || true
    set_current "$name"
    read -r ns nw < <(counts "$target")
    scope_note=""
    if [ "$all" != 1 ]; then
      if [ "$scope_from_target" = 1 ]; then scope_note=" [profile scope]"
      else scope_note=" [session: $scope_sess]"
      fi
    fi
    msg "saved '$name' ($(pluralize "$ns" session), $(pluralize "$nw" window))$scope_note${renamed:+; renamed$renamed}"
    ;;

  restore)
    name="$(need_name "${1:-}" restore)"
    need_plugin
    need_tmux
    target="$NAMED_DIR/$name.txt"
    [ -f "$target" ] || die "no profile '$name'"
    last="$RESURRECT_DIR/last"
    # Preserve the rolling `last` slot. A named restore must not permanently
    # hijack what `prefix + Ctrl-r` (native restore of `last`) points at, so we
    # remember the prior target, point `last` at the named profile just for the
    # duration of restore.sh, then put it back — even if restore fails.
    prev_kind=none; prev_target=""
    if   [ -L "$last" ]; then prev_kind=link; prev_target="$(readlink "$last")"
    elif [ -e "$last" ]; then prev_kind=file; mv -f "$last" "$last.named-bak"
    fi
    ln -sfn "$target" "$last"
    if ! "$RESTORE_SH"; then
      case "$prev_kind" in
        link) ln -sfn "$prev_target" "$last" ;;
        file) mv -f "$last.named-bak" "$last" ;;
        none) rm -f "$last" ;;
      esac
      die "restore failed for '$name'"
    fi
    case "$prev_kind" in
      link) ln -sfn "$prev_target" "$last" ;;
      file) mv -f "$last.named-bak" "$last" ;;
      none) rm -f "$last" ;;
    esac
    set_current "$name"
    run_hook '@resurrect-post-restore' "PROFILE=$name"
    read -r ns nw < <(counts "$target")
    msg "restored '$name' ($(pluralize "$ns" session), $(pluralize "$nw" window))"
    ;;

  rename)
    old="$(need_name "${1:-}" rename)"
    new="$(need_name "${2:-}" rename)"
    [ -f "$NAMED_DIR/$old.txt" ] || die "no profile '$old'"
    [ -e "$NAMED_DIR/$new.txt" ] && die "profile '$new' already exists"
    mv "$NAMED_DIR/$old.txt" "$NAMED_DIR/$new.txt"
    [ -f "$NAMED_DIR/$old.desc" ] && mv "$NAMED_DIR/$old.desc" "$NAMED_DIR/$new.desc"
    if is_pinned "$old"; then
      unpin_name "$old"
      printf '%s\n' "$new" >> "$PINS_FILE"
    fi
    [ "$(get_current)" = "$old" ] && set_current "$new"
    msg "renamed '$old' to '$new'"
    ;;

  list)
    if [ -d "$NAMED_DIR" ] && ls "$NAMED_DIR"/*.txt >/dev/null 2>&1; then
      # `paste -d` treats the argument as a *cycling* delimiter set, so
      # `-d ', '` would alternate comma and space. Use a single delimiter
      # and post-process to get "a, b, c".
      names="$(for f in "$NAMED_DIR"/*.txt; do basename "$f" .txt; done | paste -sd ',' | sed 's/,/, /g')"
      msg "profiles: $names"
    else
      msg "no saved profiles"
    fi
    ;;

  delete)
    name="$(need_name "${1:-}" delete)"
    if [ -f "$NAMED_DIR/$name.txt" ]; then
      remove_profile "$name"
      msg "deleted '$name' (recoverable — 'untrash $name' to restore)"
    else
      msg "no profile '$name'"
    fi
    ;;

  exists)
    [ -n "${1:-}" ] || exit 1
    name="$(sanitize "$1")"
    [ -f "$NAMED_DIR/$name.txt" ]
    ;;

  dir)
    printf '%s\n' "$NAMED_DIR"
    ;;

  describe)
    name="$(need_name "${1:-}" describe)"
    [ -f "$NAMED_DIR/$name.txt" ] || die "no profile '$name'"
    shift || true
    text="${*:-}"
    if [ -z "$text" ]; then
      rm -f "$NAMED_DIR/$name.desc"
      msg "cleared description for '$name'"
    else
      # Keep descriptions to a single line; strip trailing whitespace.
      printf '%s' "$text" | tr '\n\r\t' '   ' | sed 's/[[:space:]]*$//' > "$NAMED_DIR/$name.desc"
      msg "described '$name'"
    fi
    ;;

  description)
    name="$(need_name "${1:-}" description)"
    [ -f "$NAMED_DIR/$name.desc" ] && cat "$NAMED_DIR/$name.desc"
    ;;

  copy)
    src="$(need_name "${1:-}" copy)"
    dst="$(need_name "${2:-}" copy)"
    force=0
    [ "${3:-}" = "--force" ] && force=1
    [ -f "$NAMED_DIR/$src.txt" ] || die "no profile '$src'"
    if [ -e "$NAMED_DIR/$dst.txt" ] && [ "$force" != 1 ]; then
      die "profile '$dst' already exists (use --force)"
    fi
    cp -f "$NAMED_DIR/$src.txt" "$NAMED_DIR/$dst.txt"
    [ -f "$NAMED_DIR/$src.desc" ] && cp -f "$NAMED_DIR/$src.desc" "$NAMED_DIR/$dst.desc"
    msg "copied '$src' to '$dst'"
    ;;

  prune)
    older=30; dry=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --older-than)   older="${2:-30}"; shift 2 ;;
        --older-than=*) older="${1#--older-than=}"; shift ;;
        --dry-run)      dry=1; shift ;;
        *)              shift ;;
      esac
    done
    older="${older%d}"
    case "$older" in ''|*[!0-9]*) die "prune: --older-than needs a number of days" ;; esac
    [ -d "$NAMED_DIR" ] || { msg "no saved profiles"; exit 0; }
    drop=(); keep=()
    while IFS= read -r -d '' f; do
      n="$(basename "$f" .txt)"
      if is_pinned "$n"; then keep+=("$n"); else drop+=("$n"); fi
    done < <(find "$NAMED_DIR" -maxdepth 1 -name '*.txt' -type f -mtime "+$older" -print0)
    if [ "${#drop[@]}" -eq 0 ]; then
      msg "nothing to prune (older than ${older}d, skipping ${#keep[@]} pinned)"
      exit 0
    fi
    if [ "$dry" = 1 ]; then
      msg "would delete: ${drop[*]} (skipping pinned: ${keep[*]:-none})"
      exit 0
    fi
    for n in "${drop[@]}"; do
      remove_profile "$n"
    done
    # Sweep trashed items past the same window so the trash can't grow forever.
    [ -d "$TRASH_DIR" ] && find "$TRASH_DIR" -maxdepth 1 -type f -mtime "+$older" -delete 2>/dev/null || true
    msg "pruned ${#drop[@]} profile(s) to trash; skipped pinned: ${keep[*]:-none}"
    ;;

  trash)
    shopt -s nullglob
    files=("$TRASH_DIR"/*.txt)
    if [ "${#files[@]}" -eq 0 ]; then
      msg "trash is empty"
    else
      names="$(for f in "${files[@]}"; do basename "$f" .txt; done | paste -sd ',' | sed 's/,/, /g')"
      msg "trashed: $names"
    fi
    ;;

  untrash)
    name="$(need_name "${1:-}" untrash)"
    [ -e "$NAMED_DIR/$name.txt" ] && die "profile '$name' already exists (rename or delete it first)"
    # Most-recently trashed copy of this name.
    recent="$(ls -t "$TRASH_DIR/$name".*.txt 2>/dev/null | head -n 1 || true)"
    [ -n "$recent" ] || die "nothing in trash for '$name'"
    mv "$recent" "$NAMED_DIR/$name.txt"
    touch "$NAMED_DIR/$name.txt" 2>/dev/null || true   # bubble back up as recent
    d="${recent%.txt}.desc"
    [ -f "$d" ] && mv "$d" "$NAMED_DIR/$name.desc" || true
    msg "restored '$name' from trash"
    ;;

  empty-trash)
    older=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --older-than)   older="${2:-}"; shift 2 ;;
        --older-than=*) older="${1#--older-than=}"; shift ;;
        *)              shift ;;
      esac
    done
    if [ ! -d "$TRASH_DIR" ]; then
      msg "trash is empty"
    elif [ -n "$older" ]; then
      older="${older%d}"
      case "$older" in ''|*[!0-9]*) die "empty-trash: --older-than needs a number of days" ;; esac
      find "$TRASH_DIR" -maxdepth 1 -type f -mtime "+$older" -delete 2>/dev/null || true
      msg "emptied trashed items older than ${older}d"
    else
      rm -rf "$TRASH_DIR"
      msg "emptied trash"
    fi
    ;;

  pin)
    name="$(need_name "${1:-}" pin)"
    [ -f "$NAMED_DIR/$name.txt" ] || die "no profile '$name'"
    if is_pinned "$name"; then
      msg "'$name' already pinned"
    else
      mkdir -p "$NAMED_DIR"
      printf '%s\n' "$name" >> "$PINS_FILE"
      msg "pinned '$name'"
    fi
    ;;
  unpin)
    name="$(need_name "${1:-}" unpin)"
    if is_pinned "$name"; then
      unpin_name "$name"
      msg "unpinned '$name'"
    else
      msg "'$name' not pinned"
    fi
    ;;
  pins)
    [ -f "$PINS_FILE" ] && cat "$PINS_FILE"
    ;;
  pinned)
    [ -n "${1:-}" ] || exit 1
    name="$(sanitize "$1")"
    is_pinned "$name"
    ;;

  find|grep)
    pat="${1:-}"
    [ -n "$pat" ] || die "$cmd needs a pattern"
    [ -d "$NAMED_DIR" ] || exit 0
    shopt -s nullglob
    for f in "$NAMED_DIR"/*.txt; do
      if grep -q -- "$pat" "$f" 2>/dev/null; then
        basename "$f" .txt
      fi
    done
    # Don't leak the last grep's exit code (set -e + 1 = sad script).
    exit 0
    ;;

  diff)
    a="$(need_name "${1:-}" diff)"
    b="$(need_name "${2:-}" diff)"
    [ -f "$NAMED_DIR/$a.txt" ] || die "no profile '$a'"
    [ -f "$NAMED_DIR/$b.txt" ] || die "no profile '$b'"
    a_tmp="$(mktemp)"; b_tmp="$(mktemp)"
    # `dump` is the color-free, view-independent structural rendering (no
    # volatile "saved 2h ago" header), so the diff shows real differences
    # rather than timestamp/view-mode noise.
    "$MENU" dump "$a" > "$a_tmp"
    "$MENU" dump "$b" > "$b_tmp"
    diff -u --label "$a" --label "$b" "$a_tmp" "$b_tmp" || true
    rm -f "$a_tmp" "$b_tmp"
    ;;

  export)
    force=0; rest=()
    for a in "$@"; do
      case "$a" in --force) force=1 ;; *) rest+=("$a") ;; esac
    done
    set -- "${rest[@]:-}"
    name="$(need_name "${1:-}" export)"
    [ -f "$NAMED_DIR/$name.txt" ] || die "no profile '$name'"
    out="${2:-$PWD/${name}.resurrect.tar.gz}"
    # Resolve to absolute so the `cd` below can't relocate a relative path.
    case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
    [ -e "$out" ] && [ "$force" != 1 ] && die "refusing to overwrite '$out' (use --force or choose another path)"
    # Stage txt + desc + a pin marker so import can round-trip the pin too.
    stage="$(mktemp -d)"
    cp "$NAMED_DIR/$name.txt" "$stage/$name.txt"
    [ -f "$NAMED_DIR/$name.desc" ] && cp "$NAMED_DIR/$name.desc" "$stage/$name.desc"
    is_pinned "$name" && : > "$stage/$name.pinned" || true
    if ( cd "$stage" && tar -czf "$out" . ); then
      rm -rf "$stage"
      msg "exported '$name' -> $out"
    else
      rm -rf "$stage"
      die "export failed for '$name'"
    fi
    ;;
  import)
    file=""; force=0
    for a in "$@"; do
      case "$a" in --force) force=1 ;; *) [ -z "$file" ] && file="$a" ;; esac
    done
    { [ -n "$file" ] && [ -f "$file" ]; } || die "import needs a tarball path"
    mkdir -p "$NAMED_DIR"
    # Extract into a staging dir, then move only basename-stripped files into
    # place. The earlier `--wildcards '*.txt'` approach did NOT prevent path
    # traversal (a '../x.txt' member matches '*.txt'); basename-on-move does.
    stage="$(mktemp -d)"
    if ! tar -xzf "$file" -C "$stage" 2>/dev/null; then
      rm -rf "$stage"
      die "import: cannot read '$file' (corrupt or not a tar.gz?)"
    fi
    mapfile -d '' txts < <(find "$stage" -type f -name '*.txt' -print0)
    if [ "${#txts[@]}" -eq 0 ]; then
      rm -rf "$stage"
      die "import: no profiles found in '$file'"
    fi
    imported=0; skipped=""
    for p in "${txts[@]}"; do
      bn="$(basename "$p")"; pn="$(sanitize "${bn%.txt}")"
      { [ -n "$pn" ] && [ "$pn" != "last" ]; } || continue
      case "$pn" in .*) continue ;; esac
      if [ -e "$NAMED_DIR/$pn.txt" ] && [ "$force" != 1 ]; then
        skipped="$skipped $pn"; continue
      fi
      mv -f "$p" "$NAMED_DIR/$pn.txt"
      [ -f "${p%.txt}.desc" ] && mv -f "${p%.txt}.desc" "$NAMED_DIR/$pn.desc"
      if [ -f "${p%.txt}.pinned" ] && ! is_pinned "$pn"; then
        printf '%s\n' "$pn" >> "$PINS_FILE"
      fi
      imported=$((imported + 1))
    done
    rm -rf "$stage"
    if [ -n "$skipped" ]; then
      msg "imported $imported profile(s); skipped existing:$skipped (use --force to overwrite)"
    else
      msg "imported $imported profile(s) from $(basename "$file")"
    fi
    ;;

  dry-run|preview)
    name="$(need_name "${1:-}" dry-run)"
    [ -f "$NAMED_DIR/$name.txt" ] || die "no profile '$name'"
    "$MENU" preview "$name"
    ;;

  current)
    c="$(get_current)"
    if [ -n "$c" ]; then printf '%s\n' "$c"; else exit 1; fi
    ;;
  status-indicator)
    # Print <marker> (default '*') when the LIVE tmux state has structurally
    # drifted (sessions or windows added/removed) from the current profile's
    # snapshot; print nothing otherwise. Cheap enough for a status-line #()
    # poll, and must never fail the status bar — always exits 0.
    marker="${1:-*}"
    c="$(get_current)"
    { [ -n "$c" ] && [ -f "$NAMED_DIR/$c.txt" ] && [ -n "${TMUX:-}" ]; } || exit 0
    # Compare only the sessions the PROFILE contains: per-session profiles
    # must not flag unrelated live sessions (other projects) as drift. Drift
    # means: a saved session is missing live, or its window count changed.
    drift="$( {
        awk -F'\t' '
          ($1=="window" || $1=="pane") && !(($2 SUBSEP $3) in w) { w[$2 SUBSEP $3]=1; n[$2]++ }
          END { for (s in n) printf "S\t%s\t%d\n", s, n[s] }
        ' "$NAMED_DIR/$c.txt" 2>/dev/null
        tmux list-sessions -F 'L	#{session_name}	#{session_windows}' 2>/dev/null
      } | awk -F'\t' '
        $1=="S" { want[$2]=$3; next }
        $1=="L" && ($2 in want) { got[$2]=$3 }
        END { for (s in want) if (!(s in got) || got[s] != want[s]) { print "y"; exit } }
      ' || true)"
    [ -z "$drift" ] || printf '%s' "$marker"
    exit 0
    ;;
  restore-current)
    need_tmux
    c="$(get_current)"
    [ -n "$c" ] || die "no current profile"
    exec "$SELF" restore "$c"
    ;;
  save-current)
    need_tmux
    c="$(get_current)"
    [ -n "$c" ] || die "no current profile to save to"
    # --profile-scope: write-back must refresh the profile's OWN sessions.
    # Scoping to the client's session instead would leak whatever session
    # you happen to be on into a different project's profile.
    if [ "${1:-}" = "--force" ]; then
      exec "$SELF" save --force --profile-scope "$c"
    else
      exec "$SELF" save --profile-scope "$c"
    fi
    ;;
  auto-write-back)
    # Wired to the client-detached hook (tmux.conf). If a current (▶) profile
    # is set and the live state has drifted from it, silently re-save it —
    # closing the terminal can never lose a working session again. The
    # snapshot being replaced is stashed in the trash (see save), so a bad
    # auto-save is recoverable. Disable with:
    #   set -g @resurrect-autosave-on-detach '0'
    [ "$(tmux show-option -gqv '@resurrect-autosave-on-detach' 2>/dev/null || true)" = "0" ] && exit 0
    c="$(get_current)"
    { [ -n "$c" ] && [ -f "$NAMED_DIR/$c.txt" ]; } || exit 0
    [ -n "$("$SELF" status-indicator 2>/dev/null)" ] || exit 0
    exec "$SELF" save-current --force
    ;;

  restore-recent)
    need_tmux
    [ -d "$NAMED_DIR" ] || die "no saved profiles"
    # `ls *.txt` with no match exits 2; under `set -e` + `pipefail` the
    # command substitution would abort the script silently, so swallow it.
    recent="$(ls -t "$NAMED_DIR"/*.txt 2>/dev/null | head -n 1 || true)"
    [ -n "$recent" ] || die "no saved profiles"
    exec "$SELF" restore "$(basename "$recent" .txt)"
    ;;

  help|-h|--help)
    print_help
    ;;
  *)
    msg "unknown command: $cmd (try '$(basename "$SELF") help')"
    exit 1
    ;;
esac
