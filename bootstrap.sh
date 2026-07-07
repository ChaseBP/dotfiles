#!/usr/bin/env bash
# Zero-to-dotfiles on a fresh machine:
#
#   curl -fsSL https://raw.githubusercontent.com/ChaseBP/dotfiles/main/bootstrap.sh | bash
#
# Clones (or fast-forwards) the repo and hands off to install.sh. Installer
# flags pass straight through:
#
#   curl -fsSL .../bootstrap.sh | bash -s -- --dry-run --skip nvim
#
# Override the clone location/source with DOTFILES_DIR / DOTFILES_REPO.
# Uses HTTPS by default — a fresh box has no SSH keys yet; switch the remote
# to SSH later with: git remote set-url origin git@github.com:ChaseBP/dotfiles.git
set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/ChaseBP/dotfiles.git}"
DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

command -v git >/dev/null 2>&1 || {
  echo "❌ git is required — install it first (e.g. apt/dnf/pacman install git)" >&2
  exit 1
}

if [ -d "$DIR/.git" ]; then
  echo "↻  updating existing clone at $DIR"
  git -C "$DIR" pull --ff-only || {
    echo "⚠  pull failed (local changes or diverged history) — continuing with what's there" >&2
  }
elif [ -e "$DIR" ]; then
  echo "❌ $DIR exists but isn't a git clone — move it aside or set DOTFILES_DIR" >&2
  exit 1
else
  echo "⬇  cloning $REPO → $DIR"
  git clone "$REPO" "$DIR"
fi

exec "$DIR/install.sh" "$@"
