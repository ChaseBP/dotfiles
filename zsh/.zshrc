# ==========================================================
# Locale
#   LANG only — setting LC_ALL overrides every other LC_*
#   category and breaks sorting/number parsing in scripts.
# ==========================================================
export LANG="en_IN.UTF-8"

# ==========================================================
# Editor
# ==========================================================
export EDITOR="nvim"
export VISUAL="nvim"

# ==========================================================
# Path
# ==========================================================
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

# ==========================================================
# History
#   HISTSIZE is what's kept in memory, SAVEHIST what's written
#   to disk — they were 50000/10000, so 80% was discarded.
# ==========================================================
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS      # drop older duplicate of a repeated command
setopt HIST_SAVE_NO_DUPS         # never write a duplicate
setopt HIST_REDUCE_BLANKS
setopt HIST_IGNORE_SPACE         # leading space keeps a command out of history
setopt HIST_VERIFY               # expand !! for review instead of running it
setopt SHARE_HISTORY             # live sync across open shells
setopt EXTENDED_HISTORY          # record timestamps

# ==========================================================
# Oh My Zsh
#   robbyrussell — starship is installed but deliberately left off below.
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
# Tools
#   All of these were installed but only ever initialised in
#   config.fish, which never ran — zsh is the login shell.
# ==========================================================
# starship disabled — using oh-my-zsh robbyrussell instead (they conflict; whichever
# runs last wins, and starship init comes after oh-my-zsh.sh)
# command -v starship >/dev/null && eval "$(starship init zsh)"
command -v zoxide   >/dev/null && eval "$(zoxide init zsh --cmd cd)"
command -v direnv   >/dev/null && eval "$(direnv hook zsh)"
command -v mise     >/dev/null && eval "$(mise activate zsh)"

# fzf first, then atuin — atuin takes over Ctrl-R.
if command -v fzf >/dev/null; then
  source <(fzf --zsh) 2>/dev/null
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
  export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always --line-range :200 {}'"
fi
command -v atuin >/dev/null && eval "$(atuin init zsh --disable-up-arrow)"

# ==========================================================
# Aliases
# ==========================================================
if command -v eza >/dev/null; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -l --icons --group-directories-first --git'
  alias la='eza -la --icons --group-directories-first --git'
  alias lt='eza --tree --level=2 --icons'
fi
command -v bat        >/dev/null && alias cat='bat --paging=never'
command -v trash-put  >/dev/null && alias rm='trash-put'
command -v duf        >/dev/null && alias df='duf'
alias tmux="tmux -u"
alias sudo='sudo '               # trailing space: expands aliases after sudo

# bat as the man pager
command -v bat >/dev/null && export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# ==========================================================
# Machine-local overrides (not tracked in git)
# ==========================================================
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
