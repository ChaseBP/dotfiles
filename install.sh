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
# Steps run in order: zsh deps nvim tmux. A failing step doesn't abort the
# rest — the summary at the end shows what to retry with --only <step>.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

STEPS=(zsh deps nvim tmux)
ONLY=""; SKIP=""

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

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

all_csv="$(IFS=,; echo "${STEPS[*]}")"
for n in ${ONLY//,/ } ${SKIP//,/ }; do
  in_csv "$n" "$all_csv" || { echo "unknown step: $n (steps: ${STEPS[*]})" >&2; exit 2; }
done

echo "🚀 Installing dotfiles...${DRY_RUN:+ (dry run)}${NO_SUDO:+ (no sudo)}"

declare -A status=()
failed=0
for s in "${STEPS[@]}"; do
  if { [ -n "$ONLY" ] && ! in_csv "$s" "$ONLY"; } || { [ -n "$SKIP" ] && in_csv "$s" "$SKIP"; }; then
    status[$s]="skipped"
    continue
  fi
  printf '\n━━━ %s ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' "$s"
  if "./scripts/install_$s.sh"; then
    status[$s]="ok"
  else
    status[$s]="FAILED"
    failed=1
  fi
done

printf '\n📋 Summary\n'
for s in "${STEPS[@]}"; do
  printf '   %-6s %s\n' "$s" "${status[$s]}"
done
if [ "$failed" = 1 ]; then
  printf '\n❌ Some steps failed — retry one with: ./install.sh --only <step>\n'
  exit 1
fi
printf '\n✅ All done. Restart your terminal.\n'
