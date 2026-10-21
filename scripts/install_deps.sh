#!/usr/bin/env bash
# Common dev dependencies: python3 (+pip/venv) via the system package manager,
# and Node LTS via mise — the version manager the tracked .zshrc activates.
# (This step used to install nvm, which .zshrc stopped loading on 2026-09-13, so
# node was never on PATH on a fresh machine.)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

info "📦 Installing common development dependencies (Node via mise, Python)..."

# ------------------------------
# 1. Base packages — only touch the package manager when something is missing
# ------------------------------
need=()
command -v curl >/dev/null 2>&1 || need+=(curl)
command -v git  >/dev/null 2>&1 || need+=(git)
if command -v python3 >/dev/null 2>&1; then
  python3 -m pip --version >/dev/null 2>&1 || need+=(python3-pip)
  python3 -c 'import venv' 2>/dev/null || need+=(python3-venv)
else
  need+=(python3 python3-pip python3-venv)
fi
if [ "${#need[@]}" -gt 0 ]; then
  info "🔧 Installing: ${need[*]}"
  pkg_install "${need[@]}" || warn "some base packages missing — continuing"
else
  ok "base packages present"
fi

# ------------------------------
# 2. mise — the distro package where there is one (pacman), otherwise mise's own
#    installer into ~/.local/bin (no sudo; apt/dnf don't ship it by default)
# ------------------------------
if command -v mise >/dev/null 2>&1; then
  ok "mise already installed ($(mise --version 2>/dev/null | head -1))"
else
  [ "$PKG_MGR" = pacman ] && can_root && { pkg_install mise || true; }
  if command -v mise >/dev/null 2>&1; then
    ok "installed mise from the package manager"
  elif dry; then
    info "   [dry-run] would install mise into ~/.local/bin (https://mise.run)"
  else
    info "⬇  Installing mise into ~/.local/bin..."
    mkdir -p "$HOME/.local/bin"
    retry 3 bash -c 'curl -fsSL https://mise.run | MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh' \
      || die "could not install mise (network?) — re-run: ./install.sh --only deps"
  fi
fi

# ------------------------------
# 3. Tools from the tracked config (node = "lts")
# ------------------------------
info "🔗 Linking mise config..."
link_file "$DOTFILES_DIR/mise/config.toml" "$HOME/.config/mise/config.toml"
if dry; then
  info "   [dry-run] would run: mise install (Node LTS)"
elif command -v mise >/dev/null 2>&1; then
  info "⬇  Installing Node LTS with mise..."
  retry 2 mise install --yes || warn "mise install failed — run it again later: mise install"
fi
if [ -d "$HOME/.nvm" ]; then
  info "   (~/.nvm from an older install is unused now — remove it whenever you like)"
fi

# ------------------------------
# 4. Verify (best effort — some may be dry-run / no-sudo skips)
# ------------------------------
info "🧪 Versions:"
for c in mise node npm python3; do
  printf '   %-8s %s\n' "$c" "$("$c" --version 2>/dev/null | head -1 || echo 'not installed')"
done

ok "dependency setup complete"
