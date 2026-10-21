#!/usr/bin/env bash
# Installs the latest *stable* Neovim from the official GitHub release, plus
# everything the config needs at runtime — notably the tree-sitter CLI, which
# the nvim-treesitter `main` branch uses to compile parsers. Re-running
# upgrades in place (idempotent).
#
# Layout: /opt + /usr/local/bin when sudo is available, ~/.local otherwise.
# Override the Neovim release with:  NVIM_VERSION=v0.12.2 ./install_nvim.sh
# (defaults to the rolling `stable` tag, i.e. whatever the newest stable is).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NVIM_VERSION="${NVIM_VERSION:-stable}"

info "📝 Setting up Neovim ($NVIM_VERSION)..."

# ------------------------------------------------------------------
# 0. Resolve architecture -> release asset names
# ------------------------------------------------------------------
case "$(uname -m)" in
  x86_64 | amd64) NVIM_ARCH="x86_64"; TS_ARCH="x64" ;;
  aarch64 | arm64) NVIM_ARCH="arm64"; TS_ARCH="arm64" ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

# 0b. Install layout — system-wide with root/sudo, ~/.local without.
if can_root; then
  OPT_DIR="/opt"; BIN_DIR="/usr/local/bin"
  priv() { as_root "$@"; }
else
  OPT_DIR="$HOME/.local/opt"; BIN_DIR="$HOME/.local/bin"
  priv() { run "$@"; }
  info "   (no root — installing into ~/.local)"
fi

# ------------------------------------------------------------------
# 1. System dependencies (best effort — a box that already has a compiler,
#    ripgrep etc. works fine without a package manager)
#    - gcc/make: compile tree-sitter parsers; ripgrep: Telescope live-grep;
#      xclip: system clipboard; curl/tar/gzip: the tarballs below
# ------------------------------------------------------------------
need=()
for c in gcc make git curl tar gzip unzip; do
  command -v "$c" >/dev/null 2>&1 || need+=("$c")
done
command -v rg    >/dev/null 2>&1 || need+=(ripgrep)
command -v xclip >/dev/null 2>&1 || need+=(xclip)
if [ "${#need[@]}" -gt 0 ]; then
  pkgs=()
  for p in "${need[@]}"; do
    case "$p" in gcc | make) pkgs+=(build-essential) ;; *) pkgs+=("$p") ;; esac
  done
  mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
  info "📦 Installing system dependencies: ${pkgs[*]}"
  pkg_install "${pkgs[@]}" ca-certificates \
    || warn "missing: ${need[*]} — nvim will run, but treesitter/Telescope may not fully work"
else
  ok "system dependencies present"
fi

# ------------------------------------------------------------------
# 2. Neovim (official tarball -> $OPT_DIR, symlinked into $BIN_DIR)
#    Prebuilt release rather than the distro package so we track the real
#    latest stable instead of a lagging apt/dnf version.
# ------------------------------------------------------------------
NVIM_TGZ="nvim-linux-${NVIM_ARCH}.tar.gz"
NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_TGZ}"
if dry; then
  info "   [dry-run] would install Neovim $NVIM_VERSION to $OPT_DIR, link into $BIN_DIR"
else
  info "🚀 Installing Neovim ${NVIM_VERSION} (${NVIM_ARCH}) to ${OPT_DIR}..."
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fL --retry 3 -o "$tmp/$NVIM_TGZ" "$NVIM_URL"
  # Replace any previous install of the same layout, then extract fresh.
  priv rm -rf "$OPT_DIR/nvim-linux-${NVIM_ARCH}"
  priv mkdir -p "$OPT_DIR" "$BIN_DIR"
  priv tar -C "$OPT_DIR" -xzf "$tmp/$NVIM_TGZ"
  priv ln -sfn "$OPT_DIR/nvim-linux-${NVIM_ARCH}/bin/nvim" "$BIN_DIR/nvim"
fi

# If another nvim shadows ours on PATH, point it out. (A link to this one is the
# same nvim.)
if command -v nvim >/dev/null 2>&1 \
   && [ "$(readlink -f "$(command -v nvim)")" != "$(readlink -f "$BIN_DIR/nvim")" ]; then
  warn "another nvim is first on PATH: $(command -v nvim) (this one: $BIN_DIR/nvim)"
fi

# ------------------------------------------------------------------
# 3. tree-sitter CLI (required by nvim-treesitter `main` to build parsers)
# ------------------------------------------------------------------
if dry; then
  info "   [dry-run] would install the tree-sitter CLI to $BIN_DIR"
else
  info "🌳 Installing tree-sitter CLI..."
  TS_GZ="tree-sitter-linux-${TS_ARCH}.gz"
  TS_URL="https://github.com/tree-sitter/tree-sitter/releases/latest/download/${TS_GZ}"
  curl -fL --retry 3 -o "$tmp/$TS_GZ" "$TS_URL"
  gunzip -f "$tmp/$TS_GZ"
  priv install -m 0755 "$tmp/tree-sitter-linux-${TS_ARCH}" "$BIN_DIR/tree-sitter"
fi

# ------------------------------------------------------------------
# 4. Link the Neovim config (backs up a real ~/.config/nvim dir — a plain
#    ln -sfn would nest the link inside it instead of replacing it)
# ------------------------------------------------------------------
info "🔗 Linking Neovim config..."
link_file "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"

# ------------------------------------------------------------------
# 5. Bootstrap plugins + parsers (best effort; needs network)
#    restore, not sync: install exactly the commits in the tracked lazy-lock.json.
#    sync would update past them (an untested plugin set on a new machine) and
#    rewrite the lockfile, leaving the repo dirty.
# ------------------------------------------------------------------
NVIM_BIN="$BIN_DIR/nvim"
[ -x "$NVIM_BIN" ] || NVIM_BIN="$(command -v nvim || true)"
# init.lua bootstraps lazy.nvim from its latest release, past the commit the lockfile
# pins (and restore leaves lazy.nvim itself alone). Clone it at that commit first.
LAZY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim"
lazy_rev="$(sed -n 's/.*"lazy\.nvim": {[^}]*"commit": "\([0-9a-f]*\)".*/\1/p' "$DOTFILES_DIR/nvim/lazy-lock.json")"
if ! dry && [ -n "$NVIM_BIN" ] && [ ! -d "$LAZY_DIR" ] && [ -n "$lazy_rev" ]; then
  if retry 3 git clone --quiet --filter=blob:none https://github.com/folke/lazy.nvim.git "$LAZY_DIR"; then
    git -C "$LAZY_DIR" checkout --quiet "$lazy_rev" || warn "lazy.nvim: locked commit $lazy_rev not found — using its latest"
  fi
fi
if dry; then
  info "   [dry-run] would bootstrap plugins (Lazy restore + TSUpdate)"
elif [ -n "$NVIM_BIN" ] && "$NVIM_BIN" --headless "+Lazy! restore" +qa 2>/dev/null; then
  "$NVIM_BIN" --headless "+TSUpdate" "+sleep 5" +qa 2>/dev/null || true
else
  warn "plugin bootstrap skipped (offline?). Run inside nvim:  :Lazy restore  then  :TSUpdate"
fi

# ------------------------------------------------------------------
# 6. Verify
# ------------------------------------------------------------------
info "🧪 Versions:"
info "   $("${NVIM_BIN:-nvim}" --version 2>/dev/null | head -n 1 || echo 'nvim: not found')"
info "   tree-sitter: $(tree-sitter --version 2>/dev/null || echo 'not found')"

ok "Neovim setup complete"
