# ==============================
# User Local Binaries
# ==============================
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

# ==============================
# NVM (Node Version Manager)
# ==============================
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
