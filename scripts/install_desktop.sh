#!/usr/bin/env bash
# CachyOS desktop: packages, Caelestia itself, system tweaks. Runs as the normal
# user on a fresh CachyOS install; the `caelestia` step then layers the personal
# config on top.
#
# Recommended base: CachyOS with **KDE Plasma** chosen in the installer, and this
# run from Konsole inside Plasma. Hyprland + Caelestia get added as a second
# session, so when an update breaks Caelestia you pick Plasma at the login screen
# and fix it from a working desktop. (The Latitude went Hyprland-edition-only: when
# `caelestia install` replaced ~/.config/hypr, Noctalia went with it, and the only
# way back was a TTY.)
#
# Order matters, and is the whole point of this script:
#   1. paru + the repo packages
#   2. quickshell-git from the AUR, BEFORE anything depends on it. caelestia-shell
#      depends on `quickshell-git`, and the CachyOS repo package noctalia-qs claims
#      to provide that name. Left to resolve the dependency itself, paru prefers the
#      repo provider, and caelestia-shell then dies on startup with
#      'Unrecognized pragma "DefaultEnv"' -> black screen. (This happened on the
#      Latitude, 2026-09-09.)
#   3. `caelestia install` (upstream: caelestia-shell/cli + its dots), non-interactive
#   4. AUR extras + hardware extras (2-in-1, XP-Pen) chosen by detect_hw.sh
#   5. /etc tweaks, groups, services
#
# GPU drivers are deliberately absent: the CachyOS installer (chwd) owns them.
# Nothing here touches the bootloader, kernel cmdline, fstab or mkinitcpio.
#
# Env: WITH_XPPEN=1 forces the XP-Pen bits when the tablet is not plugged in.
#      SKIP_UPGRADE=1 skips the initial pacman -Syu (e.g. re-runs on a daily driver).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PKG="$DOTFILES_DIR/caelestia/packages"
SYS="$DOTFILES_DIR/caelestia/system"

# Caelestia's optional + default components as enabled on the Latitude
# (~/.local/state/caelestia/dots-state.json).
CAELESTIA_COMPONENTS="hypr,fish,foot,fastfetch,btop,micro,thunar,starship,firefox,gtk,qt,auth,network,bluetooth,pipewire,clipboard,fonts,tools"

info "🖥  Setting up the CachyOS desktop..."

if [ "$PKG_MGR" != pacman ]; then
  warn "not an Arch/CachyOS system — skipping the desktop step"
  exit 0
fi
[ "$(id -u)" != 0 ] || die "run as your normal user (paru refuses root); sudo is used where needed"
can_root || die "the desktop step needs sudo"
grep -qi cachyos /etc/os-release || warn "not CachyOS — continuing, but only CachyOS is tested"

# A second, independent desktop session is the safety net. Hyprland sessions don't
# count: Noctalia and Caelestia both live in the same ~/.config/hypr.
# (|| true: under pipefail, grep finding no other session would end the script here)
fallback=$(find /usr/share/wayland-sessions /usr/share/xsessions -name '*.desktop' 2>/dev/null \
  | grep -viE 'hyprland|uwsm' | head -1 || true)
if [ -n "$fallback" ]; then
  ok "fallback session available: $(sed -n 's/^Name=//p' "$fallback" | head -1)"
else
  warn "no fallback desktop session — if Caelestia breaks, you're down to a TTY."
  warn "recommended: install CachyOS with KDE Plasma and run this from there; or add one now:"
  warn "    sudo pacman -S plasma-desktop konsole dolphin"
fi

eval "$("$DOTFILES_DIR/scripts/detect_hw.sh")"
[ "${WITH_XPPEN:-0}" = 1 ] && HW_XPPEN=1
info "   hardware: ${HW_PRODUCT} · gpu: ${HW_GPUS:-?} · laptop=$HW_LAPTOP touch=$HW_TOUCH accel=$HW_ACCEL hinge=${HW_TABLET_SWITCH:+yes} xppen=$HW_XPPEN"

# Package lists: one name per line, '#' comments. Read into arrays (names never
# contain spaces, but word-splitting command output is how lists get mangled).
list() { grep -hv '^\s*#' "$@" | awk 'NF { print $1 }'; }
mapfile -t PKGS_REPO  < <(list "$PKG/repo.txt")
mapfile -t PKGS_AUR   < <(list "$PKG/aur.txt")
mapfile -t PKGS_2IN1  < <(list "$PKG/2in1.txt")
mapfile -t PKGS_XPPEN < <(list "$PKG/xppen.txt")

# One sudo prompt for the whole run: long AUR builds otherwise outlive sudo's
# timestamp and stop mid-way to ask again. PARU_CONF also reaches the paru calls
# that `caelestia install` makes, since it inherits our environment.
PARU_TMP="$(mktemp -d)"
trap 'rm -rf "$PARU_TMP"' EXIT
{ cat /etc/paru.conf 2>/dev/null || echo "[options]"; } \
  | sed '/^\[options\]/a SudoLoop\nSkipReview' >"$PARU_TMP/paru.conf"
export PARU_CONF="$PARU_TMP/paru.conf"
# Retried once: AUR builds download sources from all over (GitHub, sourceforge, ...)
# and one dropped connection shouldn't fail the whole step.
paru_s() { retry 2 run paru -S --needed --noconfirm "$@"; }

# Ask for the password now, while the user is still watching the terminal.
dry || sudo -v

# ------------------------------
# 1. Full upgrade, paru, repo packages
# ------------------------------
# Never install against a stale package database: CachyOS rebuilds often and drops
# old files from the mirrors (404s mid-install), and AUR builds must link against
# current libraries. -Syu, never a partial -Sy. SKIP_UPGRADE=1 to opt out.
if [ -n "${DOTFILES_UPGRADED:-}" ]; then
  ok "system already upgraded by install.sh"
elif [ -z "${SKIP_UPGRADE:-}" ]; then
  info "⬆  Full system upgrade first..."
  retry 2 as_root pacman -Syu --noconfirm
fi
if ! command -v paru >/dev/null 2>&1; then
  info "📦 Installing paru (CachyOS repo)..."
  as_root pacman -S --needed --noconfirm paru
fi
info "📦 Repo packages..."
paru_s --repo "${PKGS_REPO[@]}"

# AUR signing keys, fetched over HTTPS before paru needs them: gpg's own keyserver
# fetch times out on some networks, and under --noconfirm that kills the install.
aur_wanted=(quickshell-git caelestia-cli "${PKGS_AUR[@]}")
{ [ -n "$HW_TABLET_SWITCH" ] || [ "$HW_ACCEL" = 1 ]; } && aur_wanted+=("${PKGS_2IN1[@]}")
[ "$HW_XPPEN" = 1 ] && aur_wanted+=("${PKGS_XPPEN[@]}")
if dry; then
  info "   [dry-run] would pre-import AUR signing keys for: ${aur_wanted[*]} + Caelestia's components"
else
  info "🔑 AUR signing keys..."
  python3 "$DOTFILES_DIR/scripts/aur_keys.py" --caelestia "$CAELESTIA_COMPONENTS" "${aur_wanted[@]}" \
    || warn "key pre-import failed — paru will try itself"
fi

# ------------------------------
# 2. The real Quickshell, before caelestia-shell can resolve to noctalia-qs
# ------------------------------
if pacman -Qq noctalia-qs >/dev/null 2>&1; then
  # Only on a machine that already went down the wrong path. Swapping it removes
  # the running shell's binary, so leave it to the user, in a quiet moment.
  warn "noctalia-qs provides Quickshell here, not quickshell-git. Caelestia runs on it only"
  warn "thanks to the forked shell.qml. To switch (then log out and back in):"
  warn "    paru -S quickshell-git     # answer y to remove noctalia-qs"
elif pacman -Qq quickshell-git >/dev/null 2>&1; then
  ok "quickshell-git already installed"
else
  info "🧱 Building quickshell-git from the AUR (takes a few minutes)..."
  paru_s --aur quickshell-git
fi

# ------------------------------
# 3. Caelestia (upstream installer)
# ------------------------------
if [ -f "$HOME/.local/state/caelestia/dots-state.json" ]; then
  ok "Caelestia already installed — update it with: caelestia update"
else
  info "🌌 Installing Caelestia..."
  # KDE Plasma ships jack2; Caelestia's pipewire component wants pipewire-jack, and
  # the two conflict (both provide `jack`). --noconfirm answers "no" to pacman's
  # "Remove jack2?" and the whole caelestia install aborts. Swap them in one
  # transaction first — the standard PipeWire switch; `--ask 4` answers yes to
  # exactly that conflict-removal question. Found by the KDE VM test.
  if pacman -Qq jack2 >/dev/null 2>&1 && ! pacman -Qq pipewire-jack >/dev/null 2>&1; then
    as_root pacman -S --noconfirm --ask 4 pipewire-jack
  fi
  paru_s --aur caelestia-cli
  # --noconfirm: backs up ~/.config to ~/.config.bak first (default yes), takes the
  # components listed above, and never stops to ask. It replaces the CachyOS
  # Hyprland config in ~/.config/hypr — expected; the personal layer goes on top.
  # Its post-install hooks reload Hyprland / start the shell, which only works
  # inside a session; from a TTY they warn and the next login picks it all up.
  if dry; then
    info "   [dry-run] caelestia install --noconfirm --aur-helper paru --enable-components $CAELESTIA_COMPONENTS"
  else
    # Outside Hyprland (Konsole in Plasma, a TTY), its hooks would start the Caelestia
    # bar on top of Plasma; with the display hidden, Qt aborts instead and leaves core
    # dumps. So hide the display and stand in no-op qs/hyprctl for the hooks — the
    # first Hyprland login starts the shell anyway.
    hide=()
    if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
      mkdir -p "$PARU_TMP/nohooks"
      printf '#!/bin/sh\nexit 0\n' >"$PARU_TMP/nohooks/qs"
      cp "$PARU_TMP/nohooks/qs" "$PARU_TMP/nohooks/hyprctl"
      chmod +x "$PARU_TMP/nohooks/qs" "$PARU_TMP/nohooks/hyprctl"
      hide=(env -u WAYLAND_DISPLAY -u DISPLAY PATH="$PARU_TMP/nohooks:$PATH")
    fi
    "${hide[@]}" caelestia install --noconfirm --aur-helper paru --enable-components "$CAELESTIA_COMPONENTS" \
      || die "caelestia install failed — fix the error above, then re-run: ./install.sh --only desktop,caelestia"
  fi
fi

# ------------------------------
# 4. AUR extras + hardware extras
# ------------------------------
info "📦 AUR packages..."
paru_s --aur "${PKGS_AUR[@]}"

if [ -n "$HW_TABLET_SWITCH" ] || [ "$HW_ACCEL" = 1 ]; then
  info "🔄 2-in-1 hardware: auto-rotate + on-screen keyboard"
  paru_s "${PKGS_2IN1[@]}"
fi

if [ "$HW_XPPEN" = 1 ]; then
  if [ -d /usr/lib/pentablet ] && ! pacman -Qqo /usr/lib/pentablet >/dev/null 2>&1; then
    # Installed by hand from XP-Pen's tarball: the package would abort on file conflicts.
    ok "XP-Pen driver already installed by hand (/usr/lib/pentablet) — leaving it"
  else
    info "🖊  XP-Pen tablet: official driver"
    paru_s --aur "${PKGS_XPPEN[@]}"
  fi
fi

# ------------------------------
# 5. /etc tweaks, groups, services
# ------------------------------
# Copied, not linked: /etc is read before $HOME is mounted. Each is a drop-in, so
# package updates never conflict with them.
put_etc() { # $1=repo file $2=destination
  if cmp -s "$1" "$2"; then return 0; fi
  as_root install -Dm644 "$1" "$2"
  ok "installed $2"
}
put_etc "$SYS/resolved-99-dot.conf"          /etc/systemd/resolved.conf.d/99-dot.conf
put_etc "$SYS/journald-99-size.conf"         /etc/systemd/journald.conf.d/99-size.conf
put_etc "$SYS/networkmanager-99-privacy.conf" /etc/NetworkManager/conf.d/99-privacy.conf

if [ "$HW_XPPEN" = 1 ]; then
  # Driver injects its pointer through /dev/uinput: load the module at boot and keep
  # libinput off the raw tablet so the two never fight over the cursor.
  put_etc "$SYS/modules-load-uinput.conf"       /etc/modules-load.d/uinput.conf
  put_etc "$SYS/tmpfiles-xppen-lock.conf"       /etc/tmpfiles.d/xppen-lock.conf
  put_etc "$SYS/99-xppen-libinput-ignore.rules" /etc/udev/rules.d/99-xppen-libinput-ignore.rules
  as_root udevadm control --reload-rules || true
fi

# ~/.config/environment.d/10-locale.conf (seeded by the caelestia step) sets
# LANG/LC_ALL=en_IN.UTF-8; a locale that isn't generated breaks every app's
# locale setup, and the CachyOS installer only generates the one you picked.
locales="$(locale -a 2>/dev/null || true)"
if ! grep -qix 'en_IN.utf8' <<<"$locales"; then
  as_root sed -i 's/^#\s*en_IN UTF-8/en_IN UTF-8/' /etc/locale.gen
  grep -q '^en_IN UTF-8' /etc/locale.gen || as_root sh -c 'echo "en_IN UTF-8" >> /etc/locale.gen'
  as_root locale-gen >/dev/null
  ok "generated the en_IN.UTF-8 locale"
fi

# input group: ydotool (Caelestia "tools") and the XP-Pen driver both write /dev/uinput.
if [[ " $(id -nG "$USER") " == *" input "* ]]; then
  ok "$USER already in the input group"
else
  as_root usermod -aG input "$USER"
  ok "added $USER to the input group (takes effect at next login)"
fi

if [ "$HW_INTEL_CPU" = 1 ]; then
  paru_s --repo thermald
  as_root systemctl enable thermald.service
fi
run systemctl --user enable ydotool.service 2>/dev/null || warn "could not enable ydotool.service (enable it after first login)"

# The Latitude's S3 sleep never resumed (2026-09); s2idle did. Don't let it come back.
if grep -qw 'mem_sleep_default=deep' /proc/cmdline; then
  warn "kernel cmdline has mem_sleep_default=deep — on the Latitude that meant 'dead after lid close'."
  warn "remove it from /etc/default/limine unless you've verified S3 resumes on this machine."
fi

ok "desktop setup complete — reboot (or log out and in) once the caelestia step has run"
