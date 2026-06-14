#!/usr/bin/env bash
set -e

echo "🧩 Setting up tmux..."

# ------------------------------
# 1. Install tmux (>= 3.6, built from source if needed)
# ------------------------------
# tmux 3.6 added "do not close popups on resize, instead adjust them to fit",
# so the saved-sessions popup follows the terminal size. Distro packages lag
# (Ubuntu 24.04 ships 3.4), so build from source into ~/.local when the
# installed tmux is older. No sudo for the build itself — only to install any
# missing build deps. Idempotent: skips entirely if tmux is already >= 3.6.
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

if tmux_ge_min; then
    echo "✔  tmux $(tmux -V) already >= ${TMUX_MIN_MAJOR}.${TMUX_MIN_MINOR}"
else
    cur="$(command -v tmux >/dev/null 2>&1 && tmux -V || echo 'tmux not found')"
    echo "📦 ${cur} is older than ${TMUX_MIN_MAJOR}.${TMUX_MIN_MINOR} — building ${TMUX_VERSION} into ${PREFIX} ..."

    # Build prerequisites — only apt (sudo) if something is actually missing.
    deps_ok=1
    for b in gcc make bison pkg-config curl tar; do command -v "$b" >/dev/null 2>&1 || deps_ok=0; done
    { [ -f /usr/include/ncurses.h ] || [ -f /usr/include/ncursesw/ncurses.h ]; } || deps_ok=0
    if [ "$deps_ok" -eq 0 ]; then
        echo "   installing build dependencies (sudo apt) ..."
        sudo apt-get update -qq
        sudo apt-get install -y build-essential bison pkg-config curl libncurses-dev
    fi

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
    echo "✔  installed $("$PREFIX/bin/tmux" -V) to ${PREFIX}/bin"
    case ":$PATH:" in
        *":$PREFIX/bin:"*) ;;
        *) echo "⚠  add ${PREFIX}/bin to PATH (ahead of /usr/bin) so the new tmux is used" ;;
    esac
fi

# fzf powers the saved-session popup (prefix + G)
if ! command -v fzf >/dev/null 2>&1; then
    echo "📦 Installing fzf..."
    sudo apt install -y fzf
else
    echo "✔  fzf already installed"
fi

# ------------------------------
# 2. Install TPM
# ------------------------------
TPM_DIR="$HOME/.tmux/plugins/tpm"

if [ ! -d "$TPM_DIR" ]; then
    echo "🔌 Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    echo "✔  TPM already installed"
fi

# ------------------------------
# 3. Link tmux config
# ------------------------------
echo "🔗 Linking tmux config..."
ln -sf "$PWD/tmux/tmux.conf" "$HOME/.tmux.conf"

# ------------------------------
# 4. Link helper scripts
# ------------------------------
echo "🔗 Linking tmux helper scripts..."
mkdir -p "$HOME/.tmux/scripts"
chmod +x "$PWD/tmux/scripts/"*.sh
for f in "$PWD/tmux/scripts/"*.sh; do
    ln -sf "$f" "$HOME/.tmux/scripts/$(basename "$f")"
done

# ------------------------------
# 5. Expose the launcher on PATH
# ------------------------------
# `tmux-sessions` opens the session/profile picker BEFORE attaching, so a
# session is created only when you choose one (no throwaway session left
# behind). Type it from a plain shell; inside tmux it mirrors prefix + G.
echo "🔗 Linking tmux-sessions command..."
mkdir -p "$HOME/.local/bin"
ln -sf "$PWD/tmux/scripts/tmux-sessions.sh" "$HOME/.local/bin/tmux-sessions"

echo "✅ tmux setup complete"
echo "👉 Start tmux and press Prefix + I to install plugins"
