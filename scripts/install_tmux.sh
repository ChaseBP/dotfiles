#!/usr/bin/env bash
# tmux >= 3.6 (built from source into ~/.local when the system one is older),
# fzf, TPM, config + helper-script symlinks, and the tmux-sessions launcher.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

info "🧩 Setting up tmux..."

# ------------------------------
# 1. Install tmux (>= 3.6, built from source if needed)
# ------------------------------
# tmux 3.6 added "do not close popups on resize, instead adjust them to fit",
# so the saved-sessions popup follows the terminal size. Distro packages lag
# (Ubuntu 24.04 ships 3.4), so build from source into ~/.local when the
# installed tmux is older. No root for the build itself — only to install any
# missing build deps; without them we keep the current tmux and warn instead
# of failing the step. Idempotent: skips entirely if tmux is already >= 3.6.
TMUX_VERSION="3.6b"                 # bump to install a newer tmux
LIBEVENT_VERSION="2.1.12-stable"
TMUX_MIN_MAJOR=3; TMUX_MIN_MINOR=6
PREFIX="$HOME/.local"

tmux_ge_min() {
  command -v tmux >/dev/null 2>&1 || return 1
  local v major minor
  v="$(tmux -V | grep -oE '[0-9]+\.[0-9]+' | head -1)"   # "tmux 3.6b" -> "3.6"
  major="${v%%.*}"; minor="${v#*.}"
  [ "${major:-0}" -gt "$TMUX_MIN_MAJOR" ] && return 0
  [ "${major:-0}" -eq "$TMUX_MIN_MAJOR" ] && [ "${minor:-0}" -ge "$TMUX_MIN_MINOR" ]
}

build_deps_ok() {
  local b
  for b in gcc make bison pkg-config curl tar; do
    command -v "$b" >/dev/null 2>&1 || return 1
  done
  [ -f /usr/include/ncurses.h ] || [ -f /usr/include/ncursesw/ncurses.h ]
}

if tmux_ge_min; then
  ok "tmux $(tmux -V) already >= ${TMUX_MIN_MAJOR}.${TMUX_MIN_MINOR}"
elif dry; then
  info "   [dry-run] would build tmux ${TMUX_VERSION} (+libevent if needed) into ${PREFIX}"
else
  cur="$(command -v tmux >/dev/null 2>&1 && tmux -V || echo 'tmux not found')"
  info "📦 ${cur} is older than ${TMUX_MIN_MAJOR}.${TMUX_MIN_MINOR} — building ${TMUX_VERSION} into ${PREFIX} ..."

  if ! build_deps_ok; then
    info "   installing build dependencies..."
    pkg_install build-essential bison pkg-config curl tar ncurses-dev || true
  fi
  if ! build_deps_ok; then
    warn "build deps unavailable — keeping '${cur}'; popups may not auto-fit on resize"
  else
    BD="$(mktemp -d)"
    (
      cd "$BD"
      # libevent — build into ~/.local only if it isn't available anywhere.
      if ! pkg-config --exists libevent 2>/dev/null \
         && [ ! -f "$PREFIX/include/event2/event.h" ] \
         && [ ! -f /usr/include/event2/event.h ]; then
        echo "   building libevent ${LIBEVENT_VERSION} ..."
        curl -fsSL -o le.tgz "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}/libevent-${LIBEVENT_VERSION}.tar.gz"
        tar xzf le.tgz
        cd "libevent-${LIBEVENT_VERSION}"
        ./configure --prefix="$PREFIX" --disable-openssl --disable-debug-mode --disable-samples
        make -j"$(nproc)" && make install
        cd ..
      fi
      echo "   building tmux ${TMUX_VERSION} ..."
      curl -fsSL -o tm.tgz "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz"
      tar xzf tm.tgz
      cd "tmux-${TMUX_VERSION}"
      ./configure --prefix="$PREFIX" \
        PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
        CPPFLAGS="-I$PREFIX/include" \
        LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
      make -j"$(nproc)" && make install
    )
    rm -rf "$BD"
    hash -r 2>/dev/null || true
    ok "installed $("$PREFIX/bin/tmux" -V) to ${PREFIX}/bin"
    case ":$PATH:" in
      *":$PREFIX/bin:"*) ;;
      *) warn "add ${PREFIX}/bin to PATH (ahead of /usr/bin) so the new tmux is used" ;;
    esac
  fi
fi

# ------------------------------
# 2. fzf (powers the pickers) — distro package, or the static GitHub binary
#    into ~/.local/bin when there's no package manager / no sudo.
# ------------------------------
FZF_VERSION="${FZF_VERSION:-0.70.0}"
if command -v fzf >/dev/null 2>&1; then
  ok "fzf already installed"
else
  pkg_install fzf || true
  if ! command -v fzf >/dev/null 2>&1; then
    case "$(uname -m)" in
      x86_64 | amd64) fzf_arch=amd64 ;;
      aarch64 | arm64) fzf_arch=arm64 ;;
      *) fzf_arch="" ;;
    esac
    if [ -z "$fzf_arch" ]; then
      warn "fzf unavailable — the session pickers won't work until it's installed"
    elif dry; then
      info "   [dry-run] would download the fzf ${FZF_VERSION} binary to ${PREFIX}/bin"
    else
      info "📦 Installing fzf ${FZF_VERSION} binary into ${PREFIX}/bin..."
      mkdir -p "$PREFIX/bin"
      curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${fzf_arch}.tar.gz" \
        | tar -xz -C "$PREFIX/bin" fzf
    fi
  fi
fi

# ------------------------------
# 3. Install TPM
# ------------------------------
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ -d "$TPM_DIR" ]; then
  ok "TPM already installed"
else
  info "🔌 Installing TPM..."
  run git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

# ------------------------------
# 4. Link tmux config
# ------------------------------
info "🔗 Linking tmux config..."
link_file "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"

# ------------------------------
# 5. Link helper scripts
# ------------------------------
info "🔗 Linking tmux helper scripts..."
run mkdir -p "$HOME/.tmux/scripts"
run chmod +x "$DOTFILES_DIR/tmux/scripts/"*.sh
for f in "$DOTFILES_DIR/tmux/scripts/"*.sh; do
  run ln -sf "$f" "$HOME/.tmux/scripts/$(basename "$f")"
done

# ------------------------------
# 6. Expose the launcher on PATH
# ------------------------------
# `tmux-sessions` opens the session/profile picker BEFORE attaching, so a
# session is created only when you choose one (no throwaway session left
# behind). Type it from a plain shell; inside tmux it mirrors prefix + G.
info "🔗 Linking tmux-sessions command..."
run mkdir -p "$HOME/.local/bin"
run ln -sf "$DOTFILES_DIR/tmux/scripts/tmux-sessions.sh" "$HOME/.local/bin/tmux-sessions"

ok "tmux setup complete"
info "👉 Start tmux and press Prefix + I to install plugins"
