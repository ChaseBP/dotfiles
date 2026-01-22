# ==============================
# User Local Binaries
# ==============================
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

# ==============================
# Neovim (installed manually or via script)
# ==============================
[ -d "/opt/nvim-linux-x86_64/bin" ] && export PATH="/opt/nvim-linux-x86_64/bin:$PATH"

# ==============================
# NVM (Node Version Manager)
# ==============================
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
