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

# fzf powers the saved-session popup (prefix + G)
if ! command -v fzf >/dev/null 2>&1; then
    echo "📦 Installing fzf..."
    sudo apt install -y fzf
else
    echo "✔  fzf already installed"
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

# ------------------------------
# 4. Link helper scripts
# ------------------------------
echo "🔗 Linking tmux helper scripts..."
mkdir -p "$HOME/.tmux/scripts"
chmod +x "$PWD/tmux/scripts/"*.sh
for f in "$PWD/tmux/scripts/"*.sh; do
    ln -sf "$f" "$HOME/.tmux/scripts/$(basename "$f")"
done

# ------------------------------
# 5. Expose the launcher on PATH
# ------------------------------
# `tmux-sessions` opens the session/profile picker BEFORE attaching, so a
# session is created only when you choose one (no throwaway session left
# behind). Type it from a plain shell; inside tmux it mirrors prefix + G.
echo "🔗 Linking tmux-sessions command..."
mkdir -p "$HOME/.local/bin"
ln -sf "$PWD/tmux/scripts/tmux-sessions.sh" "$HOME/.local/bin/tmux-sessions"

echo "✅ tmux setup complete"
echo "👉 Start tmux and press Prefix + I to install plugins"
