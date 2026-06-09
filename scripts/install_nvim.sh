#!/usr/bin/env bash
set -euo pipefail

# Installs the latest *stable* Neovim (0.12.x at time of writing) from the
# official GitHub release, plus everything the config needs at runtime —
# notably the tree-sitter CLI, which the nvim-treesitter `main` branch uses to
# compile parsers. Re-running upgrades in place (idempotent).
#
# Override the Neovim release with:  NVIM_VERSION=v0.12.2 ./install_nvim.sh
# (defaults to the rolling `stable` tag, i.e. whatever the newest stable is).

NVIM_VERSION="${NVIM_VERSION:-stable}"

echo "📝 Setting up Neovim ($NVIM_VERSION)..."

# ------------------------------------------------------------------
# 0. Resolve architecture -> release asset names
# ------------------------------------------------------------------
case "$(uname -m)" in
  x86_64 | amd64) NVIM_ARCH="x86_64"; TS_ARCH="x64" ;;
  aarch64 | arm64) NVIM_ARCH="arm64"; TS_ARCH="arm64" ;;
  *) echo "❌ Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# ------------------------------------------------------------------
# 1. System dependencies
#    - build-essential / gcc: C compiler, required to compile tree-sitter
#      parsers and some plugins
#    - ripgrep: Telescope live-grep; xclip: system clipboard; curl/tar/gzip:
#      fetching the release tarballs below
# ------------------------------------------------------------------
echo "📦 Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  gcc \
  make \
  git \
  curl \
  tar \
  gzip \
  unzip \
  ripgrep \
  xclip \
  ca-certificates

# ------------------------------------------------------------------
# 2. Neovim (official stable tarball -> /opt, symlinked onto PATH)
#    We use the prebuilt release rather than the distro/PPA package so we
#    track the real latest stable instead of a lagging apt version.
# ------------------------------------------------------------------
echo "🚀 Installing Neovim ${NVIM_VERSION} (${NVIM_ARCH})..."
NVIM_TGZ="nvim-linux-${NVIM_ARCH}.tar.gz"
NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_TGZ}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fL --retry 3 -o "$tmp/$NVIM_TGZ" "$NVIM_URL"

# Replace any previous install of the same layout, then extract fresh.
sudo rm -rf "/opt/nvim-linux-${NVIM_ARCH}"
sudo tar -C /opt -xzf "$tmp/$NVIM_TGZ"
sudo ln -sf "/opt/nvim-linux-${NVIM_ARCH}/bin/nvim" /usr/local/bin/nvim

# If an older apt-based Neovim is shadowing ours, point it out.
if command -v nvim >/dev/null && [ "$(command -v nvim)" != "/usr/local/bin/nvim" ]; then
  echo "⚠  Another nvim is first on PATH: $(command -v nvim)"
  echo "   Consider 'sudo apt remove neovim' or fixing PATH so /usr/local/bin wins."
fi

# ------------------------------------------------------------------
# 3. tree-sitter CLI (required by nvim-treesitter `main` to build parsers)
#    The main branch compiles grammars locally and needs the CLI (>= 0.26.1).
# ------------------------------------------------------------------
echo "🌳 Installing tree-sitter CLI..."
TS_GZ="tree-sitter-linux-${TS_ARCH}.gz"
TS_URL="https://github.com/tree-sitter/tree-sitter/releases/latest/download/${TS_GZ}"
curl -fL --retry 3 -o "$tmp/$TS_GZ" "$TS_URL"
gunzip -f "$tmp/$TS_GZ"
sudo install -m 0755 "$tmp/tree-sitter-linux-${TS_ARCH}" /usr/local/bin/tree-sitter

ts_ver="$(tree-sitter --version 2>/dev/null | awk '{print $2}' || echo '?')"
echo "   tree-sitter $ts_ver"

# ------------------------------------------------------------------
# 4. Link the Neovim config
# ------------------------------------------------------------------
echo "🔗 Linking Neovim config..."
mkdir -p "$HOME/.config"
ln -sfn "$PWD/nvim" "$HOME/.config/nvim"

# ------------------------------------------------------------------
# 5. Bootstrap plugins + parsers (best effort; needs network)
#    Sync lazy.nvim, then compile the treesitter parsers. Non-fatal so the
#    script still succeeds offline — you can run these later from inside nvim.
# ------------------------------------------------------------------
echo "🔌 Bootstrapping plugins (lazy sync + TSUpdate)..."
if nvim --headless "+Lazy! sync" +qa 2>/dev/null; then
  nvim --headless "+TSUpdate" "+sleep 5" +qa 2>/dev/null || true
else
  echo "⚠  Plugin bootstrap skipped (offline?). Run inside nvim:  :Lazy sync  then  :TSUpdate"
fi

# ------------------------------------------------------------------
# 6. Verify
# ------------------------------------------------------------------
echo "🧪 Versions:"
nvim --version | head -n 1
echo "   tree-sitter: $(tree-sitter --version 2>/dev/null || echo 'not found')"

echo "✅ Neovim setup complete"
