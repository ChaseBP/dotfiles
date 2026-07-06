#!/usr/bin/env bash
# Shared helpers for the install scripts. Source it, don't execute:
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Environment knobs (set by install.sh flags, or exported manually):
#   DRY_RUN=1   narrate mutating commands instead of running them
#   NO_SUDO=1   never invoke sudo — system packages are skipped with a
#               warning and binaries fall back to ~/.local
#
# Targets Linux with bash >= 4 and apt, dnf or pacman. macOS is out of scope
# (ships bash 3.2 + BSD userland — the repo's scripts assume GNU tools).

[ -n "${DOTFILES_LIB_LOADED:-}" ] && return 0
DOTFILES_LIB_LOADED=1

# Repo root — every path in the step scripts hangs off this, so they work
# from any CWD (linking from $PWD was how half-installs used to happen).
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info() { printf '%s\n' "$*"; }
ok()   { printf '✔  %s\n' "$*"; }
warn() { printf '⚠  %s\n' "$*" >&2; }
die()  { printf '❌ %s\n' "$*" >&2; exit 1; }

dry() { [ -n "${DRY_RUN:-}" ]; }

# Run a mutating command, or narrate it under --dry-run. Only wrap commands
# that change state — checks and reads should run unconditionally so dry runs
# still take the real branches.
run() {
  if dry; then printf '   [dry-run] %s\n' "$*"; else "$@"; fi
}

# Run as root: directly when already root, via sudo when allowed + available,
# otherwise fail (rc 1) so callers can degrade instead of aborting the step.
as_root() {
  if [ "$(id -u)" = 0 ]; then run "$@"
  elif [ -n "${NO_SUDO:-}" ]; then return 1
  elif command -v sudo >/dev/null 2>&1; then run sudo "$@"
  else return 1
  fi
}

# True when system-wide installs are on the table (root now, or sudo usable).
can_root() {
  [ "$(id -u)" = 0 ] && return 0
  [ -z "${NO_SUDO:-}" ] && command -v sudo >/dev/null 2>&1
}

# ----------------------------------------------------------------- packages
PKG_MGR=none
if   command -v apt-get >/dev/null 2>&1; then PKG_MGR=apt
elif command -v dnf     >/dev/null 2>&1; then PKG_MGR=dnf
elif command -v pacman  >/dev/null 2>&1; then PKG_MGR=pacman
fi

# Canonical package name -> native name(s) for $PKG_MGR. Empty output means
# nothing to install (e.g. venv ships inside python on Fedora/Arch). Names
# with no mapping pass through unchanged.
pkg_map() {
  case "$PKG_MGR:$1" in
    apt:ncurses-dev)                      echo libncurses-dev ;;
    dnf:ncurses-dev)                      echo ncurses-devel ;;
    pacman:ncurses-dev)                   echo ncurses ;;
    dnf:build-essential)                  echo gcc gcc-c++ make ;;
    pacman:build-essential)               echo base-devel ;;
    dnf:pkg-config|pacman:pkg-config)     echo pkgconf ;;
    dnf:python3-venv|pacman:python3-venv) ;;
    pacman:python3)                       echo python ;;
    pacman:python3-pip)                   echo python-pip ;;
    *)                                    echo "$1" ;;
  esac
}

# Install canonical packages, best effort. Returns 1 when nothing could be
# installed (no known package manager, or root unavailable) so callers can
# warn-and-continue rather than kill a whole step.
pkg_install() {
  local p mapped pkgs=()
  for p in "$@"; do
    mapped="$(pkg_map "$p")"
    # shellcheck disable=SC2206  # intentional word split: multi-package maps
    [ -n "$mapped" ] && pkgs+=($mapped)
  done
  [ "${#pkgs[@]}" -gt 0 ] || return 0
  case "$PKG_MGR" in
    apt)
      # One metadata refresh per run; a failed refresh (flaky mirror) isn't
      # fatal — the install below may still work from cache.
      if [ -z "${_APT_UPDATED:-}" ]; then
        as_root apt-get update -qq || warn "apt-get update failed — trying install anyway"
        _APT_UPDATED=1
      fi
      as_root apt-get install -y "${pkgs[@]}" ;;
    dnf)    as_root dnf install -y "${pkgs[@]}" ;;
    pacman) as_root pacman -S --noconfirm --needed "${pkgs[@]}" ;;
    none)
      warn "no supported package manager (apt/dnf/pacman) — install manually: ${pkgs[*]}"
      return 1 ;;
  esac || { warn "could not install (${PKG_MGR}${NO_SUDO:+, --no-sudo}): ${pkgs[*]}"; return 1; }
}

# Symlink $1 -> $2, moving a pre-existing REAL file/dir aside first. Never
# deletes user data: the first backup takes <dst>.pre-dotfiles, later ones get
# a timestamp suffix. (A plain `ln -sfn` into an existing real directory would
# silently create the link *inside* it instead.)
link_file() { # $1=src $2=dst
  local src="$1" dst="$2" bak
  [ -e "$src" ] || die "link source missing: $src"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    bak="$dst.pre-dotfiles"
    [ -e "$bak" ] && bak="$bak.$(date +%Y%m%d-%H%M%S)"
    info "📦 backing up $dst → $bak"
    run mv "$dst" "$bak"
  fi
  run mkdir -p "$(dirname "$dst")"
  run ln -sfn "$src" "$dst"
}
