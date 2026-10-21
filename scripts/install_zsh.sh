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
# 2. Install Oh My Zsh — a plain clone. Its online installer writes its own
#    ~/.zshrc template (moved aside again below) and, if the download fails,
#    exits 0 having installed nothing, leaving .zshrc sourcing a missing file.
# --------------------------------------------------
if [ -d "$HOME/.oh-my-zsh" ]; then
  ok "Oh My Zsh already installed"
elif ! command -v zsh >/dev/null 2>&1; then
  warn "skipping Oh My Zsh (needs zsh)"
else
  info "✨ Installing Oh My Zsh..."
  retry 3 run git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" \
    || die "could not clone Oh My Zsh (network?) — re-run: ./install.sh --only zsh"
fi

# --------------------------------------------------
# 3. Normalize line endings (repo may be checked out on Windows/WSL)
# --------------------------------------------------
if command -v dos2unix >/dev/null 2>&1; then
  dos2unix "$ZSHRC_SOURCE" >/dev/null 2>&1 || true
fi

# --------------------------------------------------
# 4. Link .zshrc & .zshenv (backs up pre-existing real files)
# --------------------------------------------------
info "🔗 Linking .zshrc"
link_file "$ZSHRC_SOURCE" "$HOME/.zshrc"
ZSHENV_SOURCE="$DOTFILES_DIR/zsh/.zshenv"
if [ -f "$ZSHENV_SOURCE" ]; then
  info "🔗 Linking .zshenv"
  link_file "$ZSHENV_SOURCE" "$HOME/.zshenv"
fi

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
      retry 3 run git clone --depth 1 "${plugins[$plugin]}" "$ZSH_CUSTOM/plugins/$plugin" \
        || warn "could not clone $plugin — zsh works without it; re-run ./install.sh --only zsh later"
    fi
  done
fi

# --------------------------------------------------
# 6. Make zsh the login shell. Compare against the user database, not $SHELL:
#    a running desktop session keeps the old value until the next login. Via sudo
#    when available (already unlocked by install.sh — no second password prompt);
#    plain chsh asks for your password. Non-fatal either way (e.g. containers).
# --------------------------------------------------
ZSH_BIN="$(command -v zsh 2>/dev/null || true)"
LOGIN_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
if [ -z "$ZSH_BIN" ]; then
  :
elif [ "$LOGIN_SHELL" = "$ZSH_BIN" ] || [ "$(readlink -f "$LOGIN_SHELL" 2>/dev/null)" = "$(readlink -f "$ZSH_BIN")" ]; then
  ok "zsh already the login shell"
else
  info "🔁 Setting zsh as the login shell (was: ${LOGIN_SHELL:-unknown})"
  if can_root; then
    as_root chsh -s "$ZSH_BIN" "$USER" || warn "chsh failed — run manually: chsh -s $ZSH_BIN"
  else
    run chsh -s "$ZSH_BIN" || warn "chsh failed — run manually: chsh -s $ZSH_BIN"
  fi
fi

ok "Zsh setup complete"
info "👉 Restart terminal or run: source ~/.zshrc"
