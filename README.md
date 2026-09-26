# 🛠 Dotfiles (WSL Ubuntu)

Personal dotfiles for my **WSL Ubuntu** development environment.

This repository focuses on a clean, reproducible setup with:

- Zsh + Oh My Zsh
- Neovim (Kickstart-based config)
- tmux + TPM
- Caelestia (Hyprland + Quickshell) personal layer, incl. a Super+K shortcut palette
- Node.js (via NVM) and Python venv for editor tooling

Designed to be safe, minimal, and easy to reuse across machines.

---

## ✨ What’s Included

### Shell

- Zsh as default shell
- Oh My Zsh
- `zsh-autosuggestions`
- `zsh-syntax-highlighting`
- NVM auto-loaded

### Neovim

- Kickstart-style Lua configuration
- LSP, Treesitter, Telescope, etc.
- Plugin versions locked via `lazy-lock.json`
- Config managed via symlink

### tmux

- TPM (Tmux Plugin Manager)
- [tmux-revive](https://github.com/ChaseBP/tmux-revive) — named session
  profiles, my own plugin (it started life in this repo, then moved out)
- Session restore & continuum
- Rose Pine (moon) theme
- Mouse support + Vim-style navigation
- Config managed via symlink

### Caelestia (Arch / CachyOS desktop)

Layered on top of an existing `caelestia install`; never touches `~/.config/hypr`.

- `hypr-vars.lua` / `hypr-user.lua` / `shell.json` / `cli.json` overrides
- **Super+K shortcut palette**: a native Quickshell panel styled with Caelestia's
  own design tokens and the wallpaper's colour scheme (contrast-checked). It lists
  every live keybind, lets you search it, and runs your workflows.
  Personal actions live in `actions.json`, which feeds both the Hyprland binds and
  the palette.
- Hand-forked shell QML (network UI, background) overlaid on the symlink farm
- Helper scripts (`wall`, `osk`, `xppen-tablet`, `cliphist-store`) and XP-Pen
  Deco 640 fixes (tray shim, libinput-ignore udev rule)
- Everything symlinked per file; originals kept as `*.pre-dotfiles`

### Tooling Dependencies

- Node.js (LTS via NVM)
- npm
- Python 3 + `python3-venv`

These are included primarily for Neovim LSPs and tooling.

---

## 📁 Repository Structure

```text
dotfiles/
├── install.sh
├── README.md
├── .gitignore
│
├── zsh/
│   └── .zshrc
│
├── nvim/
│   ├── init.lua
│   ├── lua/
│   └── lazy-lock.json
│
├── tmux/
│   └── tmux.conf
│
├── caelestia/
│   ├── config/        # → ~/.config/caelestia
│   ├── quickshell/    # → ~/.config/quickshell/caelestia (forks only)
│   ├── bin/           # → ~/.local/bin
│   ├── xppen-tray/    # close-to-tray LD_PRELOAD shim
│   └── system/        # udev rule (copied to /etc)
│
├── scripts/
│   ├── install_zsh.sh
│   ├── install_deps.sh
│   ├── install_nvim.sh
│   ├── install_tmux.sh
│   └── install_caelestia.sh
│
└── docs/
    ├── screenshots/
    └── wsl-notes.md
```

---

## 🚀 Installation (Linux: apt / dnf / pacman)

One-liner on a fresh machine (clones to `~/dotfiles`, then installs):

```bash
curl -fsSL https://raw.githubusercontent.com/ChaseBP/dotfiles/main/bootstrap.sh | bash
```

Or manually:

```bash
git clone git@github.com:<your-username>/dotfiles.git
cd dotfiles
./install.sh
```

Useful flags:

```bash
./install.sh --dry-run          # show what would change, touch nothing
./install.sh --only zsh,tmux    # run a subset of steps
./install.sh --skip nvim        # run everything except a step
./install.sh --no-sudo          # no sudo: skip system packages, install to ~/.local
./install.sh --list             # list the steps (zsh deps nvim tmux caelestia)
```

The installer detects apt/dnf/pacman, backs up any real config file it
replaces (`*.pre-dotfiles`), and a failed step doesn't abort the rest —
the summary tells you what to retry. Existing configs are symlinked, so
re-running is always safe. macOS isn't supported (the scripts assume
bash ≥ 4 and GNU tools).

Machine-specific shell config (JAVA_HOME, extra PATHs, ssh-agent, …)
belongs in `~/.zshrc.local` — sourced by the tracked `.zshrc`, never
touched by the installer.

After installation, **restart your terminal**
or run:

```bash
source ~/.zshrc
```

---

## 🔁 tmux Plugins

After launching tmux for the first time:

```
Prefix + I
```

This installs all tmux plugins via TPM. `install_tmux.sh` already clones
[tmux-revive](https://github.com/ChaseBP/tmux-revive) so its bindings work
before you get to that.

### Session profiles

`tmux-revive` gives every project its own named session snapshot:

| Key | Does |
| --- | --- |
| `Prefix + G` | browse saved profiles (filter, preview, restore, pin, diff) |
| `Prefix + S` / `Prefix + R` | save the current session / restore one by name |
| `Prefix + W` | write-back — re-save the current profile from live state |
| `Prefix + L` / `Prefix + D` | restore the most recent / delete a profile |

Detaching auto-saves the current profile when the live state has drifted, so
closing a terminal can't lose a session. From a plain shell, `tmux-revive`
picks a session or profile and attaches — creating one only once you choose.
Full docs in [the plugin's README](https://github.com/ChaseBP/tmux-revive).

---

## 📝 Notes

- Node.js is installed via **NVM**, not system packages
- Windows Terminal theming is configured manually
- Neovim, tmux and Caelestia configs are symlinked from this repo

---

## 🧹 Rollback / Recovery

Configs are easy to revert.

Example (Neovim):

```bash
rm ~/.config/nvim
mv ~/.config/nvim.bak ~/.config/nvim
```

Similar backups can be used for tmux and other tools.

---

## 📌 Purpose

The goal of this repository is:

- One-command environment setup
- Minimal assumptions
- Clean separation of concerns
- Easy reproducibility across machines

---

## 🎨 Optional Background

If you want to replicate the exact look of the terminal environment, you can use the following background image. This is particularly useful for **Windows Terminal** configuration.

![Terminal Background](https://github.com/user-attachments/assets/3739ff9e-29e3-441e-a167-33eb3698ce98)

---
