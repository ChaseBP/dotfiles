#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# Resolve dotfiles root (safe even if script is run elsewhere)
# --------------------------------------------------
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZSH_REPO="$DOTFILES_DIR/zsh"
ZSHRC_SOURCE="$ZSH_REPO/.zshrc"
ZSHRC_TARGET="$HOME/.zshrc"

echo "🐚 Setting up Zsh"
echo "📁 Dotfiles dir: $DOTFILES_DIR"

# --------------------------------------------------
# 1. Install zsh if missing
# --------------------------------------------------
if ! command -v zsh >/dev/null 2>&1; then
    echo "📦 Installing zsh..."
    sudo apt update
    sudo apt install -y zsh
else
    echo "✔ zsh already installed"
fi

# --------------------------------------------------
# 2. Install Oh My Zsh (clone-only, no auto-run)
# --------------------------------------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "✨ Installing Oh My Zsh..."
    RUNZSH=no CHSH=no sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "✔ Oh My Zsh already installed"
fi

# --------------------------------------------------
# 3. Ensure repo .zshrc exists
# --------------------------------------------------
if [ ! -f "$ZSHRC_SOURCE" ]; then
    echo "❌ ERROR: $ZSHRC_SOURCE does not exist"
    echo "👉 Add your .zshrc to dotfiles/zsh/.zshrc first"
    exit 1
fi

# Normalize line endings if dos2unix exists
if command -v dos2unix >/dev/null 2>&1; then
    dos2unix "$ZSHRC_SOURCE" >/dev/null 2>&1 || true
fi

# --------------------------------------------------
# 4. Backup existing ~/.zshrc if needed
# --------------------------------------------------
if [ -e "$ZSHRC_TARGET" ] && [ ! -L "$ZSHRC_TARGET" ]; then
    echo "📦 Backing up existing ~/.zshrc → ~/.zshrc.pre-dotfiles"
    mv "$ZSHRC_TARGET" "$HOME/.zshrc.pre-dotfiles"
fi

# Remove broken symlink
if [ -L "$ZSHRC_TARGET" ] && [ ! -e "$ZSHRC_TARGET" ]; then
    echo "🧹 Removing broken ~/.zshrc symlink"
    rm -f "$ZSHRC_TARGET"
fi

# --------------------------------------------------
# 5. Create symlink
# --------------------------------------------------
echo "🔗 Linking dotfiles .zshrc"
ln -sf "$ZSHRC_SOURCE" "$ZSHRC_TARGET"

# --------------------------------------------------
# 6. Install Oh My Zsh plugins
# --------------------------------------------------
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

declare -A plugins=(
    ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
    ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
)

mkdir -p "$ZSH_CUSTOM/plugins"

for plugin in "${!plugins[@]}"; do
    if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
        echo "🔌 Installing $plugin..."
        git clone "${plugins[$plugin]}" "$ZSH_CUSTOM/plugins/$plugin"
    else
        echo "✔ $plugin already installed"
    fi
done

# --------------------------------------------------
# 7. Set zsh as default shell
# --------------------------------------------------
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "🔁 Setting zsh as default shell"
    chsh -s "$(which zsh)" || true
else
    echo "✔ zsh already default shell"
fi

# --------------------------------------------------
echo "✅ Zsh setup complete"
echo "👉 Restart terminal or run: source ~/.zshrc"
