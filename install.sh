#!/usr/bin/env bash
set -e

echo "🚀 Installing dotfiles..."

./scripts/install_zsh.sh
./scripts/install_deps.sh
./scripts/install_nvim.sh
./scripts/install_tmux.sh

# CLI tools -> ~/.local/bin (already on PATH via zsh/.zshrc)
echo "🔗 Linking CLI tools..."
mkdir -p "$HOME/.local/bin"
chmod +x "$PWD/scripts/claude-log"
ln -sf "$PWD/scripts/claude-log" "$HOME/.local/bin/claude-log"

echo "✅ All done. Restart terminal."
