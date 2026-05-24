────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# READY-TO-SAVE MARKDOWN

# Neovim Configuration Feature Overview

This document summarizes the features provided by this Neovim setup.

## 1. Core Startup and Plugin Management

- Uses `lazy.nvim` as the plugin manager and bootstraps it automatically if not installed: `init.lua:29-37`
- Loads core config modules for:
  - options: `init.lua:25`
  - keymaps: `init.lua:26`
  - autocommands: `init.lua:27`
- Loads plugin modules for UI, editor behavior, LSP, completion, formatting, Git, AI, SQL, and quality-of-life tooling: `init.lua:39-56`

### Compatibility patches

- Patches `vim.fs.find` to flatten nested root marker tables for compatibility with newer `nvim-lspconfig` behavior: `init.lua:1-18`
- Replaces deprecated `vim.tbl_flatten` usage for older plugins: `init.lua:20-23`

---

## 2. General Editor Behavior

### Display and editing defaults

- Line numbers and relative numbers enabled: `lua/core/options.lua:3-4`
- System clipboard integration enabled: `lua/core/options.lua:5`
- Mouse support enabled: `lua/core/options.lua:8`
- No line wrapping by default: `lua/core/options.lua:6`
- Autoindent and smartindent enabled: `lua/core/options.lua:9`, `lua/core/options.lua:28`
- Case-insensitive search with smartcase: `lua/core/options.lua:10-11`
- 2-space indentation defaults with spaces instead of tabs: `lua/core/options.lua:12-15`
- Persistent undo enabled: `lua/core/options.lua:41`
- Swapfile, backup, and writebackup disabled: `lua/core/options.lua:27`, `lua/core/options.lua:39-40`

### Window and split behavior

- Splits open below/right: `lua/core/options.lua:20-21`
- Keeps screen stable during splits and commands: `lua/core/options.lua:44-45`
- Rounded borders for floating windows: `lua/core/options.lua:48`

### Scrolling and movement

- Scroll offsets configured for context visibility: `lua/core/options.lua:16-17`
- Smooth scrolling enabled: `lua/core/options.lua:47`

### Whitespace, folds, and UI characters

- Visible whitespace configured via `listchars`: `lua/core/options.lua:50-57`
- Custom fill characters for folds and end-of-buffer: `lua/core/options.lua:58-64`
- Tree-sitter-powered folding enabled by default: `lua/core/options.lua:65-69`

### Search and grep

- Uses ripgrep for grep if available, including hidden files and smart-case: `lua/core/options.lua:79-82`

---

## 3. Core Keymaps

### File and session actions

- Save: `<C-s>`: `lua/core/keymaps.lua:9`
- Save without formatting/autocmds: `<leader>sn`: `lua/core/keymaps.lua:10`
- Quit window: `<C-q>`: `lua/core/keymaps.lua:11`

### Editing ergonomics

- Delete char without yanking: `x`: `lua/core/keymaps.lua:13`
- Scroll and center cursor: `<C-d>`, `<C-u>`: `lua/core/keymaps.lua:14-15`
- Keep search results centered: `n`, `N`: `lua/core/keymaps.lua:16-17`
- Visual indent keeps selection: `<`, `>`: `lua/core/keymaps.lua:42-43`
- Paste without overwriting unnamed register: `p` in visual mode: `lua/core/keymaps.lua:44`

### Window and tab management

- Resize windows with arrow keys: `lua/core/keymaps.lua:19-22`
- Split windows: `<leader>wv`, `<leader>ws`: `lua/core/keymaps.lua:31-32`
- Equalize window sizes: `<leader>we`: `lua/core/keymaps.lua:33`
- Close window: `<leader>wq`: `lua/core/keymaps.lua:34`
- New/close/next/previous tabs: `lua/core/keymaps.lua:36-39`

### Buffer management

- Next/previous buffer: `<Tab>`, `<S-Tab>`: `lua/core/keymaps.lua:24-25`
- Delete current buffer safely: `<leader>bd`: `lua/core/keymaps.lua:26-28`
- New buffer: `<leader>bn`: `lua/core/keymaps.lua:29`

### Diagnostics and quickfix

- Previous/next diagnostic: `[d`, `]d`: `lua/core/keymaps.lua:46-51`
- Open diagnostic float: `<leader>d`: `lua/core/keymaps.lua:52`
- Send diagnostics to location list: `<leader>q`: `lua/core/keymaps.lua:53`
- Quickfix navigation: `[q`, `]q`: `lua/core/keymaps.lua:54-55`

---

## 4. Autocommands and Automation

### Diagnostics UI defaults

- Sorted diagnostics, virtual text, rounded floats, and custom icons: `lua/core/autocmds.lua:5-25`

### Automatic behaviors

- Highlight yanked text: `lua/core/autocmds.lua:27-32`
- Restore cursor position when reopening files: `lua/core/autocmds.lua:34-43`
- Equalize splits on terminal resize: `lua/core/autocmds.lua:45-48`
- Allow `q` to close help/utility buffers: `lua/core/autocmds.lua:50-67`
- Auto-create missing parent directories before save: `lua/core/autocmds.lua:69-82`

---

## 5. Theme and Visual Appearance

### Colorscheme

- Uses `rose-pine` as the main colorscheme: `lua/plugins/colortheme.lua:1-5`, `lua/plugins/colortheme.lua:69`
- Auto variant selection with `moon` as dark variant: `lua/plugins/colortheme.lua:20-24`
- Enables bold and italic styling: `lua/plugins/colortheme.lua:32-36`

### Transparency toggle

- Toggle background transparency with `<leader>bg`: `lua/plugins/colortheme.lua:8-18`

### Statusline

- Uses `lualine.nvim`: `lua/plugins/lualine.lua:1-3`
- Displays mode, branch, filename, diagnostics, diff, encoding, filetype, location, progress: `lua/plugins/lualine.lua:22-39`, `lua/plugins/
lualine.lua:52-59`
- Disables lualine in `alpha` and `neo-tree`: `lua/plugins/lualine.lua:41-51`

### Bufferline

- Uses `bufferline.nvim` with icons, close buttons, modified markers, and custom separators: `lua/plugins/bufferline.lua:8-43`

### Indentation guides

- Uses `indent-blankline.nvim` via `ibl`: `lua/plugins/indent-blankline.lua:1-24`

### Startup dashboard

- Uses `alpha-nvim` with a custom ASCII header: `lua/plugins/alpha.lua:1-24`

---

## 6. File Explorer and Navigation

### Neo-tree

- Uses `neo-tree.nvim` as the file explorer: `lua/plugins/neotree.lua:1-4`
- Toggle explorer with `<leader>e`: `lua/plugins/neotree.lua:5-8`
- Reveal current file with `\\`: `lua/plugins/neotree.lua:5-8`
- Open floating git status tree with `<leader>ngs`: `lua/plugins/neotree.lua:5-8`

### Neo-tree capabilities

- Git status integration enabled: `lua/plugins/neotree.lua:35-40`
- Diagnostics integration enabled: `lua/plugins/neotree.lua:35-40`
- Rich file metadata columns such as size, type, timestamps: `lua/plugins/neotree.lua:73-77`
- File operations:
  - add/add directory/delete/rename/copy/move/paste: `lua/plugins/neotree.lua:97-107`
- Split/tab/window opening options: `lua/plugins/neotree.lua:88-95`
- Filtering, fuzzy finding, root changes, git-modified navigation: `lua/plugins/neotree.lua:138-150`
- Buffer source support with buffer deletion: `lua/plugins/neotree.lua:153-166`
- Git status source supports add/unstage/revert/commit/push: `lua/plugins/neotree.lua:168-180`

### Harpoon

- Add file: `<leader>ha`: `lua/plugins/qol.lua:29-35`
- Toggle quick menu: `<leader>hl`: `lua/plugins/qol.lua:36-42`
- Jump to slots 1-4 with `<C-1>` through `<C-4>`: `lua/plugins/qol.lua:43-70`

### Tmux navigation

- Seamless navigation between tmux panes and Vim splits using `<C-h/j/k/l>`: `lua/plugins/misc.lua:2-10`

### Flash motion

- Jump motion with `s`: `lua/plugins/misc.lua:107-115`
- Treesitter-based jump with `S`: `lua/plugins/misc.lua:116-123`
- Remote operator-pending flash with `r`: `lua/plugins/misc.lua:124-131`

---

## 7. Search and Discovery

### Telescope

- Uses `telescope.nvim`: `lua/plugins/telescope.lua:11-14`
- Search shortcuts:
  - help: `<leader>sh`: `lua/plugins/telescope.lua:16`
  - keymaps: `<leader>sk`: `lua/plugins/telescope.lua:17`
  - files: `<leader>sf`: `lua/plugins/telescope.lua:18`
  - telescope pickers: `<leader>ss`: `lua/plugins/telescope.lua:19`
  - current word grep: `<leader>sw`: `lua/plugins/telescope.lua:20`
  - live grep: `<leader>sg`: `lua/plugins/telescope.lua:21`
  - diagnostics: `<leader>sd`: `lua/plugins/telescope.lua:22`
  - resume: `<leader>sr`: `lua/plugins/telescope.lua:23`
  - old files: `<leader>s.`: `lua/plugins/telescope.lua:24`
  - buffers: `<leader><leader>`: `lua/plugins/telescope.lua:25`
  - current buffer fuzzy search: `<leader>/`: `lua/plugins/telescope.lua:26-35`
  - grep open files: `<leader>s/`: `lua/plugins/telescope.lua:36-45`
- Includes:
  - `telescope-fzf-native.nvim` for faster fuzzy finding if `make` exists: `lua/plugins/telescope.lua:47-55`
  - `telescope-ui-select.nvim` for better UI select prompts: `lua/plugins/telescope.lua:56`, `lua/plugins/telescope.lua:84-92`
- Configured to:
  - ignore common large/generated directories: `lua/plugins/telescope.lua:63-73`
  - include hidden files for file search and grep: `lua/plugins/telescope.lua:74-83`

### Search and replace

- Uses `grug-far.nvim` for project-wide search/replace: `lua/plugins/qol.lua:2-9`
- Keymap: `<leader>sR`: `lua/plugins/qol.lua:6-8`

### TODO comment discovery

- Uses `todo-comments.nvim`: `lua/plugins/misc.lua:55-77`
- Jump next/previous TODO with `]t` and `[t`: `lua/plugins/misc.lua:60-74`
- Search TODOs with `<leader>st`: `lua/plugins/misc.lua:75`

---

## 8. Syntax, Parsing, and Code Structure

### Treesitter

- Uses `nvim-treesitter`: `lua/plugins/treesitter.lua:2-7`
- Ensures parsers for many languages including:
  - Bash, CMake, CSS, Dockerfile, Git formats, Go, GraphQL, Groovy, HTML, Java, JavaScript, JSON, Lua, Markdown, Python, SQL, Terraform, TOM
    L, TSX, TypeScript, Vim, YAML: `lua/plugins/treesitter.lua:8-41`
- Enables:
  - syntax highlighting: `lua/plugins/treesitter.lua:43-46`
  - indentation: `lua/plugins/treesitter.lua:47`
  - incremental selection: `lua/plugins/treesitter.lua:48-56`

### Treesitter context

- Uses `nvim-treesitter-context`: `lua/plugins/treesitter.lua:59-68`
- Toggle context window with `<leader>tc`: `lua/plugins/treesitter.lua:69-77`

### Mini.nvim text objects and editing enhancements

- `mini.ai`: enhanced text objects: `lua/plugins/misc.lua:146-148`
- `mini.move`: moving selections/lines: `lua/plugins/misc.lua:149`
- `mini.splitjoin`: split/join structures: `lua/plugins/misc.lua:150`
- `mini.surround`: surround operations with `gs*` mappings: `lua/plugins/misc.lua:151-160`

---

## 9. Completion, Snippets, and Typing Assistance

### Completion engine

- Uses `blink.cmp`: `lua/plugins/autocompletion.lua:2-6`
- Loads on insert and command line entry: `lua/plugins/autocompletion.lua:3-5`

### Completion features

- Super-tab preset keymaps: `lua/plugins/autocompletion.lua:38-44`
- Manual completion/doc toggle with `<C-Space>`: `lua/plugins/autocompletion.lua:39-44`
- Snippet jumping with `<C-l>` and `<C-h>`: `lua/plugins/autocompletion.lua:41-43`
- Auto-bracket insertion on accept: `lua/plugins/autocompletion.lua:78-80`
- Rounded completion/documentation windows: `lua/plugins/autocompletion.lua:81-91`
- Ghost text enabled: `lua/plugins/autocompletion.lua:92`
- Signature help enabled: `lua/plugins/autocompletion.lua:95-98`
- Command-line completion enabled: `lua/plugins/autocompletion.lua:138-141`

### Completion sources

- Default sources:
  - lazydev
  - LSP
  - snippets
  - path
  - buffer
  - Copilot
  - `lua/plugins/autocompletion.lua:100-102`
- SQL filetypes use Dadbod completion: `lua/plugins/autocompletion.lua:102-106`
- Includes Copilot completion source integration: `lua/plugins/autocompletion.lua:113-127`

### Snippets

- Uses `LuaSnip`: `lua/plugins/autocompletion.lua:7-16`
- Loads `friendly-snippets`: `lua/plugins/autocompletion.lua:16-23`

### Lua development support

- Uses `lazydev.nvim` for improved Lua/Nvim API completion: `lua/plugins/autocompletion.lua:25-33`

### Autopairs

- Uses `nvim-autopairs`: `lua/plugins/misc.lua:50-54`

### Indentation detection

- Uses `vim-sleuth` for automatic indentation detection per file: `lua/plugins/misc.lua:11-14`

---

## 10. LSP and Language Intelligence

### LSP framework

- Uses `nvim-lspconfig`: `lua/plugins/lsp.lua:1-3`
- Uses Mason ecosystem for installation and management:
  - `mason.nvim`: `lua/plugins/lsp.lua:4-8`
  - `mason-lspconfig.nvim`: `lua/plugins/lsp.lua:4-8`
  - `mason-tool-installer.nvim`: `lua/plugins/lsp.lua:4-8`
- Uses `fidget.nvim` for LSP status/progress: `lua/plugins/lsp.lua:4-9`

### LSP keymaps on attach

- Go to definition: `gd`: `lua/plugins/lsp.lua:29`
- References: `gr`: `lua/plugins/lsp.lua:30`
- Implementations: `gI`: `lua/plugins/lsp.lua:31`
- Declaration: `gD`: `lua/plugins/lsp.lua:32`
- Type definition: `<leader>D`: `lua/plugins/lsp.lua:33`
- Document symbols: `<leader>ds`: `lua/plugins/lsp.lua:34`
- Workspace symbols: `<leader>ws`: `lua/plugins/lsp.lua:35`
- Rename: `<leader>rn`: `lua/plugins/lsp.lua:36`
- Code actions: `<leader>ca`: `lua/plugins/lsp.lua:37`
- Hover docs: `K`: `lua/plugins/lsp.lua:38`
- Signature help: `<leader>k`: `lua/plugins/lsp.lua:39`

### LSP niceties

- Document highlight on cursor hold when supported: `lua/plugins/lsp.lua:41-61`
- Toggle inlay hints when supported with `<leader>th`: `lua/plugins/lsp.lua:63-67`

### Configured language servers

- Bash: `bashls`: `lua/plugins/lsp.lua:71-72`
- CSS: `cssls`: `lua/plugins/lsp.lua:72-73`
- Docker Compose: `docker_compose_language_service`: `lua/plugins/lsp.lua:73-74`
- Docker: `dockerls`: `lua/plugins/lsp.lua:74-75`
- Go: `gopls`: `lua/plugins/lsp.lua:75-76`
- HTML: `html`: `lua/plugins/lsp.lua:77`
- JSON with SchemaStore schemas: `lua/plugins/lsp.lua:78-85`
- Markdown: `marksman`: `lua/plugins/lsp.lua:86`
- Python: `pyright` and `ruff`: `lua/plugins/lsp.lua:87-93`
- SQL: `sqlls`: `lua/plugins/lsp.lua:94`
- TOML: `taplo`: `lua/plugins/lsp.lua:95`
- Tailwind: `tailwindcss`: `lua/plugins/lsp.lua:96`
- Terraform: `terraformls`: `lua/plugins/lsp.lua:97`
- TypeScript/JavaScript: `ts_ls`: `lua/plugins/lsp.lua:98`
- YAML with SchemaStore schemas: `lua/plugins/lsp.lua:99-109`
- Lua: `lua_ls`: `lua/plugins/lsp.lua:110-123`

### Special custom LSP

- Custom AutoHotkey v2 language server (`ahk2`) via Node adapter and Windows interpreter path: `lua/plugins/lsp.lua:126-139`, `lua/plugins/l
sp.lua:165-170`

### Tool auto-installation

- Ensures language servers plus tools like:
  - `checkmake`
  - `eslint_d`
  - `prettier`
  - `ruff`
  - `shellcheck`
  - `shfmt`
  - `stylua`
  - `lua/plugins/lsp.lua:143-153`

---

## 11. Formatting and Linting

### Formatting

- Uses `conform.nvim`: `lua/plugins/autoformatting.lua:2-5`
- Manual format keymap: `<leader>cf`: `lua/plugins/autoformatting.lua:6-14`
- Autoformat on save unless disabled: `lua/plugins/autoformatting.lua:40-46`

### Configured formatters

- Lua: `stylua`: `lua/plugins/autoformatting.lua:17-18`
- Python: `ruff_organize_imports`, `ruff_format`: `lua/plugins/autoformatting.lua:19`
- JS/TS/React/HTML/CSS/SCSS/JSON/YAML/Markdown/MDX: `prettier`: `lua/plugins/autoformatting.lua:20-31`
- Shell: `shfmt`: `lua/plugins/autoformatting.lua:32-34`
- Terraform: `terraform_fmt`: `lua/plugins/autoformatting.lua:35-37`
- TOML: `taplo`: `lua/plugins/autoformatting.lua:38`

### Format toggles

- Disable autoformat globally or per-buffer: `FormatDisable[!]`: `lua/plugins/autoformatting.lua:51-58`
- Re-enable formatting: `FormatEnable`: `lua/plugins/autoformatting.lua:59-62`

### Linting

- Uses `nvim-lint`: `lua/plugins/autoformatting.lua:65-68`
- Automatically lints on read, write, and insert leave: `lua/plugins/autoformatting.lua:83-89`
- Manual lint keymap: `<leader>cl`: `lua/plugins/autoformatting.lua:91-93`
- `LintInfo` user command shows configured linters for current filetype: `lua/plugins/autoformatting.lua:95-99`

### Configured linters

- Python: `ruff`: `lua/plugins/autoformatting.lua:71-72`
- JavaScript/TypeScript/React: `eslint_d`: `lua/plugins/autoformatting.lua:73-76`
- Makefiles: `checkmake`: `lua/plugins/autoformatting.lua:77`
- Shell: `shellcheck`: `lua/plugins/autoformatting.lua:78-80`

---

## 12. Git Features

### Gitsigns

- Uses `gitsigns.nvim`: `lua/plugins/gitsigns.lua:1-4`
- Sign column markers for add/change/delete: `lua/plugins/gitsigns.lua:5-18`
- Hunk navigation: `]c`, `[c`: `lua/plugins/gitsigns.lua:25-39`
- Stage/reset hunks in normal and visual mode: `lua/plugins/gitsigns.lua:41-48`
- Stage/reset whole buffer: `lua/plugins/gitsigns.lua:49-51`
- Undo staged hunk: `lua/plugins/gitsigns.lua:50`
- Preview hunk: `<leader>hp`: `lua/plugins/gitsigns.lua:52`
- Blame current line: `<leader>hb`: `lua/plugins/gitsigns.lua:53-55`
- Diff current/previous: `<leader>hd`, `<leader>hD`: `lua/plugins/gitsigns.lua:56-59`
- Toggle current line blame: `<leader>tb`: `lua/plugins/gitsigns.lua:60`
- Toggle word diff: `<leader>tw`: `lua/plugins/gitsigns.lua:61`

### Fugitive + Rhubarb

- Git status: `<leader>gs`: `lua/plugins/misc.lua:16-24`
- Git commit: `<leader>gc`: `lua/plugins/misc.lua:19-23`
- Git push: `<leader>gp`: `lua/plugins/misc.lua:19-23`
- Git log: `<leader>gl`: `lua/plugins/misc.lua:19-23`
- `GBrowse` support via `vim-rhubarb`: `lua/plugins/misc.lua:25-29`

---

## 13. Database / SQL Workflow

### Dadbod ecosystem

- `vim-dadbod`: base DB integration: `lua/plugins/sql-plugins.lua:2-5`
- `vim-dadbod-ui`: database explorer/UI: `lua/plugins/sql-plugins.lua:6-17`
- `vim-dadbod-completion`: SQL completion source: `lua/plugins/sql-plugins.lua:18-22`

### Database keymaps

- Toggle DB UI: `<leader>du`: `lua/plugins/sql-plugins.lua:13-16`
- Find DB buffer: `<leader>df`: `lua/plugins/sql-plugins.lua:13-16`

### SQL completion integration

- SQL/MySQL/PLSQL completion wired into Blink completion: `lua/plugins/autocompletion.lua:102-106`, `lua/plugins/autocompletion.lua:128-132`

---

## 14. AI Features

### GitHub Copilot

- Uses `copilot.lua`: `lua/plugins/ai.lua:2-19`
- Copilot filetype configuration allows most filetypes, with some exclusions like `gitcommit`, `gitrebase`, and `help`: `lua/plugins/ai.lua:
6-18`
- Copilot suggestions/panel disabled in favor of completion-source usage: `lua/plugins/ai.lua:6-8`

### CodeCompanion

- Uses `codecompanion.nvim` with Copilot adapters for chat, inline, and command workflows: `lua/plugins/ai.lua:21-46`
- Keymaps:
  - AI actions: `<leader>aa`: `lua/plugins/ai.lua:47-48`
  - AI chat toggle: `<leader>ac`: `lua/plugins/ai.lua:49`
  - Inline AI prompt: `<leader>ai`: `lua/plugins/ai.lua:50`
  - Send visual selection to chat: `<leader>ap`: `lua/plugins/ai.lua:51`
- Adds command-line abbreviation `cc` → `CodeCompanion`: `lua/plugins/ai.lua:53-55`

### Markdown rendering for AI buffers

- `render-markdown.nvim` is enabled for both `markdown` and `codecompanion` filetypes: `lua/plugins/qol.lua:11-20`

---

## 15. Utility / Discoverability Plugins

### Which-key

- Uses `which-key.nvim` to label leader-key groups: `lua/plugins/misc.lua:30-49`

### Markdown rendering

- `render-markdown.nvim` improves Markdown and CodeCompanion buffer presentation: `lua/plugins/qol.lua:11-20`

### Color visualization

- `nvim-colorizer.lua` previews color codes inline: `lua/plugins/misc.lua:78-84`

---

## 16. Plugin Inventory

This setup includes the following major plugin categories, as visible from the plugin definitions and lockfile:

- Plugin manager: `lazy.nvim`: `init.lua:29-39`, `lazy-lock.json:18`
- File explorer: Neo-tree: `init.lua:40`, `lazy-lock.json:25`
- Buffer/tab UI: Bufferline: `init.lua:41`, `lazy-lock.json:7`
- Theme: Rose Pine: `init.lua:42`, `lazy-lock.json:37`
- Statusline: Lualine: `init.lua:43`, `lazy-lock.json:20`
- Syntax parsing: Treesitter and context: `init.lua:44`, `lazy-lock.json:31-32`
- Search: Telescope and extensions: `init.lua:45`, `lazy-lock.json:39-41`
- LSP stack: `init.lua:46`, `lazy-lock.json:11`, `lazy-lock.json:19`, `lazy-lock.json:21-23`, `lazy-lock.json:29-30`, `lazy-lock.json:38`
- Completion/snippets: `init.lua:47`, `lazy-lock.json:2`, `lazy-lock.json:4-6`, `lazy-lock.json:13`, `lazy-lock.json:19`
- Formatting/linting: `init.lua:48`, `lazy-lock.json:9`, `lazy-lock.json:29`
- Git tooling: `init.lua:49`, `lazy-lock.json:14`, `lazy-lock.json:48-49`
- Startup screen: `init.lua:50`, `lazy-lock.json:3`
- Indent guides: `init.lua:51`, `lazy-lock.json:17`
- Utilities/QoL: `init.lua:52`, `init.lua:55`, `lazy-lock.json:12`, `lazy-lock.json:15-16`, `lazy-lock.json:24`, `lazy-lock.json:27-28`, `la
zy-lock.json:36`, `lazy-lock.json:42-43`, `lazy-lock.json:44`, `lazy-lock.json:50-52`
- SQL/database tools: `init.lua:53`, `lazy-lock.json:45-47`
- AI tools: `init.lua:54`, `lazy-lock.json:8`, `lazy-lock.json:10`

---

## 17. Overall Character of the Setup

This Neovim setup is focused on:

- modern IDE-like language support
- fast fuzzy searching and navigation
- Git-heavy workflows
- SQL/database interaction
- AI-assisted coding using Copilot and CodeCompanion
- polished UI with file explorer, statusline, bufferline, dashboard, and markdown rendering
- sensible defaults for formatting, linting, diagnostics, and code exploration

It is especially strong for:

- Lua
- Python
- JavaScript / TypeScript
- Terraform
- Shell scripting
- SQL
- Markdown
- YAML / JSON / TOML
- Go
- Docker-related workflows

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# KEY FINDINGS

## 1. This is a full IDE-style Neovim setup

The configuration is not minimal; it covers editing, file navigation, search, LSP, completion, formatting, linting, Git, SQL tooling, and AI tooling through explicit plugin modules loaded in init.lua:39-56.

## 2. It is optimized around modern Lua-based Neovim plugins

The setup uses lazy.nvim for plugin management and modular plugin specs under lua/plugins/\*, which is a modern pattern for maintainability and lazy loading: init.lua:29-39, init.lua:40-56.

## 3. It emphasizes discoverability and smooth workflows

Features like which-key, Telescope, Trouble, Neo-tree, Harpoon, and Flash work together to improve navigation and discoverability: lua/plugins/misc.lua:30-49, lua/plugins/telescope.lua:15-46, lua/plugins/neotree.lua:35-182, lua/plugins/qol.lua:22-76, lua/plugins/misc.lua:99-140.

## 4. It supports a broad multi-language development workflow

Treesitter parsers, LSP servers, formatters, and linters cover many common languages: lua/plugins/treesitter.lua:8-41, lua/plugins/lsp.lua:71-124, lua/plugins/autoformatting.lua:17-39, lua/plugins/autoformatting.lua:71-81.

## 5. AI and database workflows are first-class concerns

This is notable because many configs treat these as optional extras. Here, Copilot, CodeCompanion, Dadbod UI, Dadbod completion, and SQL-specific completion are all wired in directly: lua/plugins/ai.lua:1-57, lua/plugins/sql-plugins.lua:1-23, lua/plugins/autocompletion.lua:100-133.

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# TECHNICAL DETAILS

## Startup structure

• Core settings come first via core.options, core.keymaps, and core.autocmds: init.lua:25-27.
• Plugin bootstrap happens immediately after: init.lua:29-37.
• All feature areas are split into themed modules, improving readability and separation of concerns: init.lua:39-56.

## Lazy loading patterns

Many plugins are loaded on demand using:
• event triggers for insert/buffer activity
• cmd triggers for command-driven tools
• keys for keymap-driven lazy loading

Examples:
• Telescope only on command or mapped search keys: lua/plugins/telescope.lua:12-16
• Neo-tree only on command/key: lua/plugins/neotree.lua:2-9
• Copilot only on insert/command usage: lua/plugins/ai.lua:2-6
• LSP on file open/new file: lua/plugins/lsp.lua:2-3

## Diagnostics philosophy

Diagnostics are configured centrally with custom icons and rounded floats, then reused across:
• global diagnostic UX: lua/core/autocmds.lua:5-25
• Neo-tree diagnostics display: lua/plugins/neotree.lua:35-40
• Lualine diagnostics summary: lua/plugins/lualine.lua:22-31
• Trouble diagnostics panel: lua/plugins/misc.lua:86-97

## Completion architecture

The completion stack is layered:
• blink.cmp as the engine: lua/plugins/autocompletion.lua:2-6
• LuaSnip for snippets: lua/plugins/autocompletion.lua:7-24
• friendly-snippets for snippet content: lua/plugins/autocompletion.lua:16-23
• lazydev for Neovim/Lua development intelligence: lua/plugins/autocompletion.lua:25-33
• Copilot as a completion source, not direct inline suggestion UI: lua/plugins/ai.lua:6-8, lua/plugins/autocompletion.lua:113-127

This is a deliberate design choice: AI suggestions are integrated into the normal completion menu rather than being rendered separately.

## LSP architecture

LSP setup uses:
• Mason for installation: lua/plugins/lsp.lua:141-158
• shared completion capabilities from Blink: lua/plugins/lsp.lua:13-17
• per-server overrides for JSON, YAML, Python, Lua, and HTML: lua/plugins/lsp.lua:77-123
• explicit enabling rather than automatic default behavior: lua/plugins/lsp.lua:155-170

This gives the setup tighter control over LSP initialization.

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# INSIGHTS AND CONTEXT

## Why this config feels “practical” rather than experimental

Although it includes modern plugins, most choices are stable and workflow-driven:
• Telescope for search
• Neo-tree for file browsing
• Gitsigns + Fugitive for Git
• Mason + LSPConfig for language servers
• Conform + nvim-lint for formatting/linting

These are common, proven patterns in advanced Neovim configs: init.lua:39-56, lazy-lock.json:1-53.

## Strong emphasis on code navigation

Navigation is supported at several layers:
• buffers/tabs/windows: lua/core/keymaps.lua:24-39
• file explorer: lua/plugins/neotree.lua:35-182
• fuzzy search: lua/plugins/telescope.lua:15-46
• quick file marks: lua/plugins/qol.lua:22-76
• motion jump plugin: lua/plugins/misc.lua:99-140
• LSP go-to actions: lua/plugins/lsp.lua:29-39

This suggests the setup is optimized for moving around medium-to-large codebases efficiently.

## Strong full-stack/web/backend orientation

The language/tooling coverage especially favors:
• Python
• JS/TS
• HTML/CSS
• Terraform
• Shell
• SQL
• YAML/JSON/TOML
• Go
• Docker

Evidence: lua/plugins/treesitter.lua:8-41, lua/plugins/lsp.lua:71-124, lua/plugins/autoformatting.lua:17-39, lua/plugins/autoformatting.lua:71-81.

## AI integration is intentionally secondary to standard editing workflows

Copilot’s own suggestion panel is disabled: lua/plugins/ai.lua:6-8.
Instead, AI is exposed through:
• completion source integration: lua/plugins/autocompletion.lua:113-127
• CodeCompanion chat/actions/inline prompts: lua/plugins/ai.lua:33-55

That usually indicates a preference for AI assistance that stays inside the normal editor UX rather than dominating it.

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# FOLLOW-UP SUGGESTIONS

## If you want a true “everything documented” file

You could save the Markdown block above as:

• NEOVIM_FEATURES.md
• or NVIM_CONFIG_OVERVIEW.md

## Good next research directions

If useful, I can next produce one of these:

1. A keymap reference only
   Focused cheat sheet of every custom mapping with categories.

1. A plugin-by-plugin breakdown
   One section per plugin including purpose, lazy-loading trigger, keymaps, and config.

1. A language support matrix
   Filetype → Treesitter parser → LSP server → formatter → linter.

1. A startup architecture overview
   How config bootstraps, load order, and plugin dependency relationships.

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# NOTE

I could not directly create the Markdown file because I’m restricted to read-only analysis in this environment. If you want, I can still help by refining the Markdown content into a shorter, cleaner, or more user-facing version before you save it.
