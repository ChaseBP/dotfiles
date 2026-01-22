#!/usr/bin/env bash
set -e

echo "🧩 Setting up tmux..."

# ------------------------------
# 1. Install tmux
# ------------------------------
if ! command -v tmux >/dev/null 2>&1; then
    echo "📦 Installing tmux..."
    sudo apt update
    sudo apt install -y tmux
else
    echo "✔  tmux already installed"
fi

# ------------------------------
# 2. Install TPM
# ------------------------------
TPM_DIR="$HOME/.tmux/plugins/tpm"

if [ ! -d "$TPM_DIR" ]; then
    echo "🔌 Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    echo "✔  TPM already installed"
fi

# ------------------------------
# 3. Link tmux config
# ------------------------------
echo "🔗 Linking tmux config..."
ln -sf "$PWD/tmux/tmux.conf" "$HOME/.tmux.conf"

echo "✅ tmux setup complete"
echo "👉 Start tmux and press Prefix + I to install plugins"
