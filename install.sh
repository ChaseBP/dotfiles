#!/usr/bin/env bash
set -e

echo "🚀 Installing dotfiles..."

./scripts/install_zsh.sh
./scripts/install_deps.sh
./scripts/install_nvim.sh
./scripts/install_tmux.sh

echo "✅ All done. Restart terminal."
