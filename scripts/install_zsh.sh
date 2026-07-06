#!/usr/bin/env bash
# Zsh + Oh My Zsh + plugins, and the repo .zshrc symlink. Degrades gracefully:
# if zsh can't be installed (no sudo / unknown distro) the config still gets
# linked so the machine is ready the moment zsh appears.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ZSHRC_SOURCE="$DOTFILES_DIR/zsh/.zshrc"

info "🐚 Setting up Zsh (dotfiles: $DOTFILES_DIR)"

[ -f "$ZSHRC_SOURCE" ] || die "missing $ZSHRC_SOURCE — add your .zshrc to dotfiles/zsh/ first"

# --------------------------------------------------
# 1. Install zsh if missing
# --------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
  ok "zsh already installed"
else
  pkg_install zsh || warn "zsh not installed — linking config anyway; install zsh manually"
fi

# --------------------------------------------------
# 2. Install Oh My Zsh (clone-only, no auto-run)
# --------------------------------------------------
if [ -d "$HOME/.oh-my-zsh" ]; then
  ok "Oh My Zsh already installed"
elif ! command -v zsh >/dev/null 2>&1; then
  warn "skipping Oh My Zsh (needs zsh)"
elif dry; then
  info "   [dry-run] would install Oh My Zsh"
else
  info "✨ Installing Oh My Zsh..."
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# --------------------------------------------------
# 3. Normalize line endings (repo may be checked out on Windows/WSL)
# --------------------------------------------------
if command -v dos2unix >/dev/null 2>&1; then
  dos2unix "$ZSHRC_SOURCE" >/dev/null 2>&1 || true
fi

# --------------------------------------------------
# 4. Link .zshrc (backs up a pre-existing real file)
# --------------------------------------------------
info "🔗 Linking .zshrc"
link_file "$ZSHRC_SOURCE" "$HOME/.zshrc"

# --------------------------------------------------
# 5. Install Oh My Zsh plugins
# --------------------------------------------------
if [ -d "$HOME/.oh-my-zsh" ]; then
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  declare -A plugins=(
    [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions.git"
    [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
  )
  run mkdir -p "$ZSH_CUSTOM/plugins"
  for plugin in "${!plugins[@]}"; do
    if [ -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
      ok "$plugin already installed"
    else
      info "🔌 Installing $plugin..."
      run git clone --depth 1 "${plugins[$plugin]}" "$ZSH_CUSTOM/plugins/$plugin"
    fi
  done
fi

# --------------------------------------------------
# 6. Set zsh as default shell (chsh asks for the user's own password;
#    failing is non-fatal — e.g. containers without a real login shell)
# --------------------------------------------------
if ! command -v zsh >/dev/null 2>&1; then
  :
elif [ "${SHELL:-}" != "$(command -v zsh)" ]; then
  info "🔁 Setting zsh as default shell"
  run chsh -s "$(command -v zsh)" || warn "chsh failed — run manually: chsh -s $(command -v zsh)"
else
  ok "zsh already the default shell"
fi

ok "Zsh setup complete"
info "👉 Restart terminal or run: source ~/.zshrc"
