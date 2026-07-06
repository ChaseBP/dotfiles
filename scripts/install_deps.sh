#!/usr/bin/env bash
# Common dev dependencies: python3 (+pip/venv) via the system package manager,
# Node LTS via nvm (user-local, never needs sudo).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Pinned — installing nvm from `master` means an unreviewed script each run.
NVM_VERSION="${NVM_VERSION:-v0.40.3}"

info "📦 Installing common development dependencies (Node, Python)..."

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
# 2. Install NVM (pinned version)
# ------------------------------
export NVM_DIR="$HOME/.nvm"
if [ -d "$NVM_DIR" ]; then
  ok "NVM already installed"
elif dry; then
  info "   [dry-run] would install nvm $NVM_VERSION"
else
  info "⬇  Installing NVM $NVM_VERSION..."
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | bash
fi

# ------------------------------
# 3. Load NVM + install Node.js LTS
# ------------------------------
# nvm.sh trips over `set -u` (unbound vars internally), so relax around it.
set +u
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
set -u

if command -v nvm >/dev/null 2>&1; then
  if nvm ls --no-colors 2>/dev/null | grep -q "lts"; then
    ok "Node.js LTS already installed"
  elif dry; then
    info "   [dry-run] would install Node.js LTS"
  else
    info "⬇  Installing Node.js LTS..."
    set +u; nvm install --lts; set -u
  fi
  if ! dry; then set +u; nvm use --lts >/dev/null; set -u; fi
elif ! dry; then
  die "nvm not found after install"
fi

# ------------------------------
# 4. Verify (best effort — some may be dry-run / no-sudo skips)
# ------------------------------
info "🧪 Versions:"
for c in node npm python3; do
  printf '   %-8s %s\n' "$c" "$("$c" --version 2>/dev/null | head -1 || echo 'not installed')"
done

ok "dependency setup complete"
