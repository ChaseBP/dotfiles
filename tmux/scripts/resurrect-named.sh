#!/usr/bin/env bash
# Named tmux-resurrect profiles.
#
# tmux-resurrect saves the whole tmux server into one snapshot and points
# `last` at it; restore always reads `last`. This wraps resurrect's own
# save.sh/restore.sh so you can keep several *named* snapshots — each with
# an optional description and pin — and restore any one of them on demand.
#
# Run `resurrect-named.sh help` for the full command reference.
set -euo pipefail

print_help() {
  cat <<'HELP'
Named tmux-resurrect profiles.

Usage:
  save [--force] <name>         snapshot current state as <name>
  restore <name>                restore the <name> snapshot
  rename <old> <new>            rename a saved profile (and metadata)
  list                          list saved profile names
  delete <name>                 remove a saved profile (and metadata)
  exists <name>                 exit 0 if profile exists
  dir                           print the named-profiles directory

  describe <name> <text...>     set the one-line description for <name>
                                (omit text to clear it)
  description <name>            print the description for <name>
  copy <src> <dst> [--force]    duplicate a profile (with its description)
  prune [--older-than N] [--dry-run]
                                delete profiles older than N days (default 30,
                                skipping pinned profiles)

  pin <name>                    mark <name> as pinned (sorted to top)
  unpin <name>                  remove pin from <name>
  pins                          list pinned profiles
  pinned <name>                 exit 0 if <name> is pinned

  find <pattern>                list profiles whose snapshot matches <pattern>
  diff <a> <b>                  show differences between two profiles
  dry-run <name>                print what `restore <name>` would do

  export <name> [path]          tar up <name> (+ .desc) into [path]
  import <file>                 extract a tar produced by `export`

  current                       print the current profile (last save/restore)
  restore-current               restore the current profile
  save-current [--force]        re-save under the current profile name
  restore-recent                restore the most recently saved profile

  help                          this message

Hooks (configure in tmux.conf):
  set -g @resurrect-pre-save     '<shell command>'   # runs before save
  set -g @resurrect-post-restore '<shell command>'   # runs after restore
  PROFILE=<name> is exported into the hook environment.

Status line:
  #{@resurrect-current}  -> the current profile name (set on save/restore).
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

# Filesystem-safe names: anything outside [A-Za-z0-9._-] is collapsed to '_'.
sanitize() { printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '_'; }

# Resolve <raw> -> <sanitized> on stdout. Warns if sanitization changed it;
# rejects empty or reserved names. Use inside command substitution.
need_name() {
  local raw="$1" role="$2" name
  [ -n "$raw" ] || { msg "$role needs a name"; exit 1; }
  name="$(sanitize "$raw")"
  [ -n "$name" ] || { msg "$role: invalid name"; exit 1; }
  if [ "$name" = "last" ]; then
    msg "$role: 'last' is reserved by tmux-resurrect"; exit 1
  fi
  [ "$name" = "$raw" ] || msg "name sanitized to '$name'"
  printf '%s' "$name"
}

need_plugin() {
  if [ ! -x "$SAVE_SH" ] || [ ! -x "$RESTORE_SH" ]; then
    msg "tmux-resurrect plugin not found at $PLUGIN_DIR"
    msg "install it (TPM: prefix + I) or adjust the path in this script"
    exit 1
  fi
}

# Refuse save/restore from outside tmux. resurrect's restore.sh derives the
# server socket from `$TMUX`; when it's empty, it runs `tmux -S "" new-session`
# which spawns an orphan server, then crashes mid-restore and leaves the
# "Restoring..." spinner looping forever. The only safe place to invoke
# save.sh/restore.sh is from a tmux client (e.g. via run-shell from a binding).
need_tmux() {
  if [ -z "${TMUX:-}" ]; then
    msg "this command must be run from inside a tmux session"
    exit 1
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

cmd="${1:-help}"
shift || true

case "$cmd" in
  save)
    force=0
    if [ "${1:-}" = "--force" ]; then force=1; shift; fi
    name="$(need_name "${1:-}" save)"
    need_plugin
    need_tmux
    target="$NAMED_DIR/$name.txt"
    if [ -e "$target" ] && [ "$force" != 1 ]; then
      if [ -n "${TMUX:-}" ]; then
        tmux confirm-before -p "profile '$name' exists — overwrite? (y/n)" \
          "run-shell '$SELF save --force $name'"
        exit 0
      fi
      msg "profile '$name' exists (use --force to overwrite)"
      exit 0
    fi
    mkdir -p "$NAMED_DIR"
    # Serialize concurrent saves so two clients don't race on `last`.
    exec 9>>"$LOCK_FILE"
    flock 9
    run_hook '@resurrect-pre-save' "PROFILE=$name"
    SCRIPT_OUTPUT="quiet" "$SAVE_SH"
    cp -L "$RESURRECT_DIR/last" "$target"
    flock -u 9
    set_current "$name"
    read -r ns nw < <(counts "$target")
    msg "saved '$name' ($(pluralize "$ns" session), $(pluralize "$nw" window))"
    ;;

  restore)
    name="$(need_name "${1:-}" restore)"
    need_plugin
    need_tmux
    target="$NAMED_DIR/$name.txt"
    [ -f "$target" ] || { msg "no profile '$name'"; exit 1; }
    # Absolute symlink: works regardless of restore.sh's cwd.
    ln -sf "$target" "$RESURRECT_DIR/last"
    "$RESTORE_SH"
    set_current "$name"
    run_hook '@resurrect-post-restore' "PROFILE=$name"
    read -r ns nw < <(counts "$target")
    msg "restored '$name' ($(pluralize "$ns" session), $(pluralize "$nw" window))"
    ;;

  rename)
    old="$(need_name "${1:-}" rename)"
    new="$(need_name "${2:-}" rename)"
    [ -f "$NAMED_DIR/$old.txt" ] || { msg "no profile '$old'"; exit 1; }
    [ -e "$NAMED_DIR/$new.txt" ] && { msg "profile '$new' already exists"; exit 1; }
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
      rm -f "$NAMED_DIR/$name.txt" "$NAMED_DIR/$name.desc"
      unpin_name "$name"
      [ "$(get_current)" = "$name" ] && set_current ""
      msg "deleted profile '$name'"
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
    [ -f "$NAMED_DIR/$name.txt" ] || { msg "no profile '$name'"; exit 1; }
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
    [ -f "$NAMED_DIR/$src.txt" ] || { msg "no profile '$src'"; exit 1; }
    if [ -e "$NAMED_DIR/$dst.txt" ] && [ "$force" != 1 ]; then
      msg "profile '$dst' already exists (use --force)"
      exit 1
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
      rm -f "$NAMED_DIR/$n.txt" "$NAMED_DIR/$n.desc"
    done
    msg "pruned ${#drop[@]} profile(s); skipped pinned: ${keep[*]:-none}"
    ;;

  pin)
    name="$(need_name "${1:-}" pin)"
    [ -f "$NAMED_DIR/$name.txt" ] || { msg "no profile '$name'"; exit 1; }
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
    [ -n "$pat" ] || { msg "$cmd needs a pattern"; exit 1; }
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
    [ -f "$NAMED_DIR/$a.txt" ] || { msg "no profile '$a'"; exit 1; }
    [ -f "$NAMED_DIR/$b.txt" ] || { msg "no profile '$b'"; exit 1; }
    a_tmp="$(mktemp)"; b_tmp="$(mktemp)"
    "$MENU" preview "$a" > "$a_tmp"
    "$MENU" preview "$b" > "$b_tmp"
    diff -u --label "$a" --label "$b" "$a_tmp" "$b_tmp" || true
    rm -f "$a_tmp" "$b_tmp"
    ;;

  export)
    name="$(need_name "${1:-}" export)"
    [ -f "$NAMED_DIR/$name.txt" ] || { msg "no profile '$name'"; exit 1; }
    out="${2:-$PWD/${name}.resurrect.tar.gz}"
    files=("$name.txt")
    [ -f "$NAMED_DIR/$name.desc" ] && files+=("$name.desc")
    ( cd "$NAMED_DIR" && tar -czf "$out" "${files[@]}" )
    msg "exported '$name' -> $out"
    ;;
  import)
    file="${1:-}"
    [ -n "$file" ] && [ -f "$file" ] || { msg "import needs a tarball path"; exit 1; }
    mkdir -p "$NAMED_DIR"
    # Restrict to .txt and .desc so a hostile tarball can't write elsewhere.
    tar -xzf "$file" -C "$NAMED_DIR" --wildcards '*.txt' '*.desc' 2>/dev/null || true
    msg "imported $(basename "$file")"
    ;;

  dry-run|preview)
    name="$(need_name "${1:-}" dry-run)"
    [ -f "$NAMED_DIR/$name.txt" ] || { msg "no profile '$name'"; exit 1; }
    "$MENU" preview "$name"
    ;;

  current)
    c="$(get_current)"
    if [ -n "$c" ]; then printf '%s\n' "$c"; else exit 1; fi
    ;;
  restore-current)
    need_tmux
    c="$(get_current)"
    [ -n "$c" ] || { msg "no current profile"; exit 1; }
    exec "$SELF" restore "$c"
    ;;
  save-current)
    need_tmux
    c="$(get_current)"
    [ -n "$c" ] || { msg "no current profile to save to"; exit 1; }
    if [ "${1:-}" = "--force" ]; then
      exec "$SELF" save --force "$c"
    else
      exec "$SELF" save "$c"
    fi
    ;;
  restore-recent)
    need_tmux
    [ -d "$NAMED_DIR" ] || { msg "no saved profiles"; exit 1; }
    # `ls *.txt` with no match exits 2; under `set -e` + `pipefail` the
    # command substitution would abort the script silently, so swallow it.
    recent="$(ls -t "$NAMED_DIR"/*.txt 2>/dev/null | head -n 1 || true)"
    [ -n "$recent" ] || { msg "no saved profiles"; exit 1; }
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
