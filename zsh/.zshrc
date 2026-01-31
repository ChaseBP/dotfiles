# ==========================================================
# Oh My Zsh
# ==========================================================

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"


# ==========================================================
# User paths
# ==========================================================

[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"


# ==========================================================
# Node / NVM
# ==========================================================

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
