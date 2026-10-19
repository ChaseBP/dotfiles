# New machine: CachyOS + Caelestia, from zero

The whole desktop — packages, Caelestia, the personal layer, hardware bits — comes
back from this repo with one command. Budget ~45 minutes, mostly AUR builds.

## 1. Install CachyOS — pick **KDE Plasma**, not Hyprland

In the CachyOS installer choose the **KDE Plasma** desktop. GPU drivers, kernel,
bootloader and snapshots are all the installer's job; this repo never touches them.

Why not the Hyprland edition: it ships the Noctalia shell on the same
`~/.config/hypr` that Caelestia replaces, so there is no second desktop. When
Caelestia broke on the Latitude (2026-09-09) the only way back was a TTY. With
Plasma installed, Hyprland + Caelestia become a *second* session: if an update
breaks it, pick **Plasma** at the login screen and fix it from a working desktop.

Use the same username (`raven`) — a couple of launcher entries assume it.

## 2. Run the installer from Konsole (inside Plasma)

```bash
sudo pacman -S --needed git
curl -fsSL https://raw.githubusercontent.com/ChaseBP/dotfiles/cachyos/bootstrap.sh | bash
```

It asks for your password once, up front, and keeps sudo alive through the
AUR builds. What happens, in order (`./install.sh --list`):

| step | does |
| --- | --- |
| zsh / deps / nvim / tmux | the cross-distro dev setup (same as on WSL) |
| desktop | repo + AUR packages, **real `quickshell-git` first**, `caelestia install`, /etc tweaks, groups, services |
| caelestia | personal layer: config, palette, forks (guarded), app configs, `host.lua`, OCR model |

Re-running is always safe; a failed step is retried with `./install.sh --only <step>`.

## 3. Log out, pick **Hyprland (uwsm-managed)** at the login screen

The login screen remembers the last session. Then:

```bash
# wallpapers live in a private repo — after adding this machine's SSH key to GitHub:
git clone git@github.com:ChaseBP/dotfiles-wallpaper.git ~/Pictures/Wallpapers && wall refresh
caelestia-doctor          # should be all green
```

Set monitor layout/scale in **HyprMod** (it writes `~/.config/hypr/hyprland-gui.lua`;
the repo seeds it without monitors, so you start on preferred/auto/scale 1).

---

## What the installer deals with, so you don't

**The Quickshell trap (the original breakage).** `caelestia-shell` depends on
`quickshell-git`. The CachyOS repo package `noctalia-qs` *provides* that name, and
paru prefers a repo provider over building from the AUR — so Caelestia ended up
on Noctalia's Quickshell and died at startup (`Unrecognized pragma "DefaultEnv"`),
leaving a black screen. The desktop step builds the real `quickshell-git` before
anything can depend on it. (The Latitude still runs on `noctalia-qs`, held together by
the forked `shell.qml`; the step prints how to switch.)

**Hand-forked shell QML.** The network-UI and background forks are pinned against
caelestia-shell 2.5.0; a newer version may not load them. `caelestia-shell-guard`
runs at every login: if the shell doesn't come up while forks are linked, it swaps
them back to stock, restarts the shell and tells you (toast). Your desktop stays up;
`caelestia-doctor` shows the drift, `caelestia-shell-guard restore` re-enables them.

**Hardware.** `scripts/detect_hw.sh` (read-only) writes `~/.config/caelestia/host.lua`
once: internal panel, built-in pen/touch devices, 2-in-1 hinge, accelerometer,
NVIDIA-only GPU, XP-Pen. `hypr-user.lua` turns blocks on from it, so the same
tracked config works on a desktop, a laptop and the 2-in-1. Edit `host.lua` freely
(it is not tracked); `REDETECT=1 ./install.sh --only caelestia` regenerates it.
2-in-1 packages (auto-rotate, on-screen keyboard) and the XP-Pen driver are only
installed when that hardware is found — `WITH_XPPEN=1` forces the tablet bits when
it isn't plugged in during install.

**Edits that used to live in upstream-managed files** (`~/.config/hypr/*`, Thunar's
`uca.xml`): moved into `hypr-user.lua` / `hypr-vars.lua` / `cli.json`, or patched by
the caelestia step (Thunar's "open terminal here" → ghostty). Nothing in
`~/.config/hypr` needs hand-editing, so `caelestia update` can't conflict with it.

**Not carried over** (by design): SSH/GPG keys, Wi-Fi passwords, browser profiles,
Discord/Vencord data, the kernel cmdline. In particular, don't re-add
`mem_sleep_default=deep`: on the Latitude it meant "dead after lid close"; the
desktop step warns if it sees it.

## Files

| repo | lands at | how |
| --- | --- | --- |
| `caelestia/config/` | `~/.config/caelestia/` | symlink per file |
| `caelestia/home/` | `~` (ghostty, atuin, mise, uwsm env) | symlink per file |
| `caelestia/seed/` | `~` (HyprMod settings, mimeapps, locale, cursor) | copied once; the app owns it after |
| `caelestia/bin/` | `~/.local/bin/` | symlink |
| `caelestia/quickshell/` | over `~/.config/quickshell/caelestia/` | symlink, guarded |
| `caelestia/system/` | `/etc/...` drop-ins | copied (DNS-over-TLS, journal cap, MAC privacy, XP-Pen) |
| `caelestia/packages/` | — | package lists: `repo`, `aur`, `2in1`, `xppen` |
| — | `~/.config/caelestia/host.lua` | generated per machine |
