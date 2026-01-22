#!/usr/bin/env bash
set -e

echo "📦 Installing common development dependencies (Node, Python venv)..."

# ------------------------------
# 1. Base packages
# ------------------------------
echo "🔧 Installing base packages..."
sudo apt update
sudo apt install -y \
    curl \
    python3 \
    python3-venv \
    python3-pip

# ------------------------------
# 2. Install NVM (Node Version Manager)
# ------------------------------
export NVM_DIR="$HOME/.nvm"

if [ ! -d "$NVM_DIR" ]; then
    echo "⬇ Installing NVM..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
else
    echo "✔ NVM already installed"
fi

# ------------------------------
# 3. Load NVM into current shell
# ------------------------------
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# ------------------------------
# 4. Install Node.js LTS
# ------------------------------
if command -v nvm >/dev/null 2>&1; then
    if ! nvm ls --no-colors | grep -q "lts"; then
        echo "⬇ Installing Node.js LTS..."
        nvm install --lts
    else
        echo "✔ Node.js LTS already installed"
    fi

    nvm use --lts
else
    echo "❌ NVM not found after install"
    exit 1
fi

# ------------------------------
# 5. Verify installs
# ------------------------------
echo "🧪 Verifying versions..."
node --version
npm --version
python3 --version

echo "✅ Dependency setup complete"
