#!/usr/bin/env bash
set -e

echo "🐚 Setting up Zsh..."

# ------------------------------
# 1. Install zsh
# ------------------------------
if ! command -v zsh >/dev/null 2>&1; then
    echo "📦 Installing zsh..."
    sudo apt update
    sudo apt install -y zsh
else
    echo "✔ zsh already installed"
fi

# ------------------------------
# 2. Install Oh My Zsh
# ------------------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "✨ Installing Oh My Zsh..."
    RUNZSH=no CHSH=no sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "✔ Oh My Zsh already installed"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# ------------------------------
# 3. Install required plugins
# ------------------------------
declare -A plugins=(
    ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
    ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting"
)

for plugin in "${!plugins[@]}"; do
    if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
        echo "🔌 Installing $plugin..."
        git clone "${plugins[$plugin]}" "$ZSH_CUSTOM/plugins/$plugin"
    else
        echo "✔ $plugin already installed"
    fi
done

# ------------------------------
# 4. Link .zshrc
# ------------------------------
echo "🔗 Linking .zshrc..."
ln -sf "$PWD/zsh/.zshrc" "$HOME/.zshrc"

# ------------------------------
# 5. Set zsh as default shell
# ------------------------------
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "🔁 Setting zsh as default shell..."
    chsh -s "$(which zsh)"
else
    echo "✔ zsh already default shell"
fi

echo "✅ Zsh setup complete"
echo "👉 Restart terminal or run: zsh"
