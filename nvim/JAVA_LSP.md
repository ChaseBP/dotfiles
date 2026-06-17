# Java LSP (jdtls)

Java language support is provided by [eclipse.jdt.ls](https://github.com/eclipse-jdtls/eclipse.jdt.ls)
driven through [`mfussenegger/nvim-jdtls`](https://github.com/mfussenegger/nvim-jdtls). The goal
is full LSP capabilities — including on **standalone, non-project files** (a lone
`HelloWorld.java`), matching VS Code's RedHat extension behaviour.

## How it's wired

| File | Role |
|------|------|
| `lua/plugins/jdtls.lua` | Lazy spec for `nvim-jdtls` (loads `ft = 'java'`). |
| `ftplugin/java.lua` | Starts/attaches jdtls per Java buffer (root + launch config). |
| `lua/plugins/lsp.lua` | `jdtls` added to `mason-tool-installer` so it auto-installs. |
| `init.lua` | One `require 'plugins.jdtls'` line registers the plugin. |

jdtls is **not** in the `servers` table in `lsp.lua` and `mason-lspconfig` has
`automatic_enable = false`, so it never double-starts. Keymaps come from the global
`LspAttach` autocmd in `lsp.lua` — they apply to the jdtls client automatically.

## Prerequisite: a JDK (21+)

Mason installs the **server**, not a Java runtime. Each machine needs **JDK 21 or newer**
available either on `PATH` or via `JAVA_HOME` (or `JDTLS_JAVA_HOME` to pin a specific JDK
just for jdtls). If none is runnable, `ftplugin/java.lua` warns and does nothing.

Everything else is plug-and-play: clone → launch nvim → `mason-tool-installer` pulls `jdtls`
→ open a `.java` file and it attaches. The launch config auto-selects the right
OS/arch variant (`config_linux` / `config_mac[_arm]` / `config_win`).

## Full diagnostics on standalone files

eclipse.jdt.ls only gives **full** features (semantic diagnostics, type errors) when it can
build an "invisible project", and it only does that when the source root is a **subdirectory**
of the workspace root — conventionally a `src/` folder. A `.java` file sitting *directly* in a
folder falls back to standalone mode: `non-project file, only syntax errors are reported`.

So for scratch Java, use a `src/` layout:

```
~/java-scratch/
└── src/
    └── Test.java
```

Open `~/java-scratch/src/Test.java` → `ftplugin/java.lua` resolves the root to
`~/java-scratch`, jdtls treats `src/` as a source root, and you get full diagnostics.
A file with no `src/` folder still works but is **syntax-only** (a jdtls limitation).

## Troubleshooting

- **Stale workspace** after moving/renaming projects: `rm -rf ~/.local/share/nvim/jdtls-workspace`
  then restart nvim.
- **Check the attach**: `:LspInfo` should show `jdtls` with the expected `root_dir`
  (the `src/` parent for scratch projects, not the file's own directory).
- **jdtls won't install**: run `:Mason` and confirm `jdtls`; ensure a JDK 21+ is on `PATH`.
