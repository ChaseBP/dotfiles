#!/usr/bin/env bash
# Dotfiles installer. Runs every step by default; each step script under
# scripts/ is also independently runnable.
#
# Usage: ./install.sh [options]
#   --only LIST   run only these steps (comma-separated, e.g. --only zsh,tmux)
#   --skip LIST   run everything except these steps
#   --dry-run     show what would change without touching anything
#   --no-sudo     never use sudo: system packages are skipped (with warnings),
#                 binaries install under ~/.local instead
#   --list        print the available steps
#   -h, --help    this message
#
# Steps run in order: zsh deps nvim tmux desktop caelestia. A failing step doesn't abort the
# rest — the summary at the end shows what to retry with --only <step>.
#
# Env: SKIP_UPGRADE=1 skips the up-front full system upgrade (pacman -Syu).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
. scripts/lib.sh

STEPS=(zsh deps nvim tmux desktop caelestia)
ONLY=""; SKIP=""

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --only)    ONLY="${2:?--only needs a comma-separated list}"; shift 2 ;;
    --only=*)  ONLY="${1#*=}"; shift ;;
    --skip)    SKIP="${2:?--skip needs a comma-separated list}"; shift 2 ;;
    --skip=*)  SKIP="${1#*=}"; shift ;;
    --dry-run) export DRY_RUN=1; shift ;;
    --no-sudo) export NO_SUDO=1; shift ;;
    --list)    printf '%s\n' "${STEPS[@]}"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

in_csv() { case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
selected() { { [ -z "$ONLY" ] || in_csv "$1" "$ONLY"; } && { [ -z "$SKIP" ] || ! in_csv "$1" "$SKIP"; }; }

all_csv="$(IFS=,; echo "${STEPS[*]}")"
for n in ${ONLY//,/ } ${SKIP//,/ }; do
  in_csv "$n" "$all_csv" || { echo "unknown step: $n (steps: ${STEPS[*]})" >&2; exit 2; }
done

# ------------------------------------------------------------------ pre-flight
# Run as yourself: files would end up root-owned, and paru refuses root.
[ "$(id -u)" != 0 ] || die "run as your normal user, not root — sudo is used where needed"

# Everything after here talks to GitHub and the package mirrors.
if ! dry && ! curl -fsS --max-time 15 -o /dev/null https://github.com; then
  die "can't reach github.com — connect to the internet, then run this again"
fi

# Full log of the run, for when something scrolls past too fast.
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

echo "🚀 Installing dotfiles...${DRY_RUN:+ (dry run)}${NO_SUDO:+ (no sudo)}"
echo "   log: $LOG"

# One password prompt for the whole run, then keep sudo's timestamp fresh: the AUR
# builds and source builds below outlast its 5-minute timeout many times over.
if ! dry && [ -z "${NO_SUDO:-}" ] && command -v sudo >/dev/null 2>&1; then
  echo "🔑 Some steps install system packages — enter your password once:"
  if sudo -v; then
    ( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null || true; sleep 50; done ) &
    keepalive=$!
    trap 'kill "$keepalive" 2>/dev/null || true' EXIT
  else
    warn "sudo didn't work — continuing without it (system packages will be skipped)"
    export NO_SUDO=1
  fi
fi

# Install against a fresh package database: CachyOS rebuilds often and its mirrors
# drop old files (404s mid-install), and AUR builds must link current libraries.
# Done once here so every step benefits; -Syu, never a partial -Sy.
if [ "$PKG_MGR" = pacman ] && can_root && ! dry && [ -z "${SKIP_UPGRADE:-}" ]; then
  echo "⬆  Full system upgrade first (pacman -Syu)..."
  if retry 2 as_root pacman -Syu --noconfirm; then
    export DOTFILES_UPGRADED=1
  else
    warn "system upgrade failed — continuing; package installs may hit stale mirrors"
  fi
fi

declare -A status=() took=()
failed=0
for s in "${STEPS[@]}"; do
  if ! selected "$s"; then
    status[$s]="skipped"; took[$s]=""
    continue
  fi
  printf '\n━━━ %s ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' "$s"
  start=$SECONDS
  if "./scripts/install_$s.sh"; then
    status[$s]="ok"
  else
    status[$s]="FAILED"
    failed=1
  fi
  took[$s]="$(( (SECONDS - start) / 60 ))m$(( (SECONDS - start) % 60 ))s"
done

printf '\n📋 Summary\n'
for s in "${STEPS[@]}"; do
  printf '   %-10s %-8s %s\n' "$s" "${status[$s]}" "${took[$s]}"
done
echo "   log: $LOG"
if [ "$failed" = 1 ]; then
  printf '\n❌ Some steps failed — fix what the log shows, then retry just those: ./install.sh --only <step>\n'
  exit 1
fi
if [ "${status[desktop]}" = ok ] || [ "${status[caelestia]}" = ok ]; then
  printf '\n✅ All done. Next:\n'
  printf '   1. Log out and pick "Hyprland (uwsm-managed)" at the login screen.\n'
  printf '   2. In a terminal there, run: caelestia-doctor   (should be all green)\n'
else
  printf '\n✅ All done. Restart your terminal.\n'
fi
