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

# ==========================================================
# Machine-local overrides (not tracked in git)
# Put host-specific exports (JAVA_HOME, extra PATH entries,
# ssh-agent, tool hooks, …) in ~/.zshrc.local — the installer
# never touches it, so it survives re-installs on any machine.
# ==========================================================
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
