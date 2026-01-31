# 🛠 Dotfiles (WSL Ubuntu)

Personal dotfiles for my **WSL Ubuntu** development environment.

This repository focuses on a clean, reproducible setup with:

- Zsh + Oh My Zsh
- Neovim (Kickstart-based config)
- tmux + TPM
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
- Session restore & continuum
- Rose Pine (moon) theme
- Mouse support + Vim-style navigation
- Config managed via symlink

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
├── scripts/
│   ├── install_zsh.sh
│   ├── install_deps.sh
│   ├── install_nvim.sh
│   └── install_tmux.sh
│
└── docs/
    ├── screenshots/
    └── wsl-notes.md
```

---

## 🚀 Installation (WSL Ubuntu)

> ⚠️ Run this only on a **fresh or trusted WSL Ubuntu install**.
> The scripts use `apt` and `sudo`.

```bash
git clone git@github.com:<your-username>/dotfiles.git
cd dotfiles
chmod +x install.sh scripts/*.sh
./install.sh
```

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

This installs all tmux plugins via TPM.

---

## 📝 Notes

- Node.js is installed via **NVM**, not system packages
- Windows Terminal theming is configured manually
- Neovim and tmux configs are symlinked from this repo

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

![Terminal Background](https://private-user-images.githubusercontent.com/144347555/543269380-3739ff9e-29e3-441e-a167-33eb3698ce98.jpg?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3Njk4NjcwODUsIm5iZiI6MTc2OTg2Njc4NSwicGF0aCI6Ii8xNDQzNDc1NTUvNTQzMjY5MzgwLTM3MzlmZjllLTI5ZTMtNDQxZS1hMTY3LTMzZWIzNjk4Y2U5OC5qcGc_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjYwMTMxJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI2MDEzMVQxMzM5NDVaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT00OGNiOWU2MjU2N2RiMTFiMjliZjc1MGNhMGZlMzhiMTY1YjFkYTU5ODNmYzFmNjIwNTMzMzc0MmVhYThlYTZjJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.4DiVSKvH_dmu4jkT1KTRzZ-NswcbOScxObUn0gFLK5Y)

---
