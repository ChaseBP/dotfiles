#!/usr/bin/env bash
set -e

echo "📝 Setting up Neovim..."

# ------------------------------
# 1. Install dependencies
# ------------------------------
echo "📦 Installing Neovim dependencies..."
sudo apt update
sudo apt install -y \
    software-properties-common \
    make \
    gcc \
    ripgrep \
    unzip \
    git \
    xclip

# ------------------------------
# 2. Add Neovim unstable PPA (if not present)
# ------------------------------
if ! grep -Rq "neovim-ppa/unstable" /etc/apt/sources.list /etc/apt/sources.list.d; then
    echo "➕ Adding Neovim unstable PPA..."
    sudo add-apt-repository ppa:neovim-ppa/unstable -y
    sudo apt update
else
    echo "✔ Neovim PPA already added"
fi

# ------------------------------
# 3. Install / upgrade Neovim
# ------------------------------
echo "🚀 Installing Neovim..."
sudo apt install -y neovim

# ------------------------------
# 4. Link Neovim config
# ------------------------------
echo "🔗 Linking Neovim config..."
mkdir -p "$HOME/.config"
ln -sf "$PWD/nvim" "$HOME/.config/nvim"

# ------------------------------
# 5. Verify install
# ------------------------------
echo "🧪 Neovim version:"
nvim --version | head -n 1

echo "✅ Neovim setup complete"
