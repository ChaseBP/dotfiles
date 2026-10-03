# Personal workflows

Configured in Caelestia's supported `hypr-vars.lua`, `hypr-user.lua`, and
`cli.json`. The helper is `scripts/workflows.py`. No managed Hyprland files
are changed.

| Shortcut | Action |
| --- | --- |
| Super+K | Search shortcuts/actions; press again to dismiss |
| Super+Ctrl+K | Show all Caelestia panels (moved from Super+K) |
| Super+Space | Open Ghostty with the existing tmux-revive session/profile picker |
| Super+Tab | Return to the previously focused window |
| Super+/ | Search open windows by title, app, and workspace |
| Super+C | Open Neovim inside Ghostty |
| Super+R | Hide visible notes; resume notes already in the scratchpad; otherwise choose typed or pen notes |
| Super+Shift+R | Always show the two-option notes chooser |
| Super+Shift+O | Select a screen region, recognize English text, and copy it |

Super+M is disabled. Todoist is disabled in the scratchpad configuration.
Application window opacity is 1.0.

## Shortcut palette and note search

Super+K opens the native Quickshell command panel. It has a short Common list,
Recent actions, category filters, and a **Browse all** button. Type an action,
shortcut, category, or synonym (for example `scan`, `ocr`, `clipboard`, or
`notes`). Exact names and shortcuts rank ahead of synonyms. Numbered workspace
actions are grouped into choosers; searching a number finds individual actions.

- Arrow keys select results; Enter runs or opens the selected item.
- Ctrl+I or **Details** explains the action and shows its shortcuts.
- Escape / Alt+Left go back, preserving the previous query, selection and scroll.
- Escape on the home view, **Close**, clicking outside, or Super+K dismisses it.
- Tab keeps normal control focus navigation. **Larger rows** enlarges targets
  for the current session. Categories scroll horizontally when needed.
- Destructive actions show a specific confirmation, with Cancel focused first.
  Window actions use the window captured when the panel opened; the target is
  rechecked before execution. Unavailable actions explain why.
- Gestures, mouse actions and uncatalogued shortcuts are marked **Guide** and
  open instructions. The panel does not execute opaque compositor callbacks.

Custom shortcuts and descriptions share `actions.json`. Stock shortcut keys
are resolved from Caelestia defaults plus user overrides and checked against
live bindings. Descriptions and explicit action adapters live in
`palette/Engine.js` (`stockActions`). Any other live bind appears as a Guide,
labelled by its own Hyprland `description`; upstream's `Category: Description`
format also sets its category. Upstream changes to existing command behavior
still require a manual catalog review; live key matching alone cannot verify
that behavior.

Colors follow Caelestia's `scheme.json`, including light/dark mode, the moment
it changes (the file is watched; a half-written file keeps the current colors).
Its surface is opaque. Text colors are checked
against their background for at least 4.5:1 contrast; selection and outline
colors use a 3:1 minimum. Unsafe colors fall back to readable alternatives.
The panel needs no compositor reload after wallpaper changes.

Choose **Search saved notes** to search filenames and text under
`~/Documents/Notes` (`.md`, `.markdown`, `.txt`, `.org`). Each file appears once,
with a highlighted context preview and matching-line count. Enter opens the
first matched line in a read-only Neovim window in the notes workspace; close
it with `:q`. A filename-only match opens line 1. **Refresh** reloads the index.
Narrow panels place the preview beneath the results.

Search excludes Rnote handwriting, hidden files and folders, and symlinks. Limits are 2 MB per file, 500 files, and 20 MB total; omissions caused by
size, access, or indexing limits are disclosed. Note contents and queries are
not persisted. The five most recent safe command IDs are saved locally.

Implementation is QML-native, no Python: `palette/shell.qml` renders the panel
and does all I/O (live binds via `hyprctl`, variables via
`scripts/palette-vars.lua`, the scheme and notes via Quickshell's `FileView`);
`palette/Engine.js` holds the catalog, search ranking, navigation stack and
action safety. Tests: `node --test palette/test_palette.mjs`. Engine.js runs in
Qt's V4 engine, which lacks `flat`/`flatMap`/`replaceAll` and object spread, has
an unstable `sort`, and silently fails Unicode property classes; the tests guard
against these. `scripts/palette.py` only opens and dismisses the panel for
`workflows.py`.

Shortcut hints appear only in the palette. Routine window actions remain
silent; custom failures and OCR progress/completion use Caelestia toasts with
a fullscreen/failure fallback. Project launching keeps its original behavior.

## Notes

The notes scratchpad reuses Caelestia's `special:todo` workspace. Choosing
either option reuses an existing matching window instead of creating duplicates.
Both kinds of notes can coexist there; Super+R resumes the most recently focused.
Super+Shift+R lets you choose the other kind. Escape cancels the chooser without
moving windows.

- Typed notes: `~/Documents/Notes/Inbox.md`, created on first use. Neovim saves
  edits automatically for this buffer, including when leaving it. Normal
  editor sessions are unaffected.
- Pen notes: reuse the most recently focused Rnote window, moving it into the
  scratchpad with its current document intact. When no Rnote window exists,
  create/open `~/Documents/Notes/Pen notes.rnote`. Rnote's own save/autosave
  settings apply; an existing untitled document still needs its first save.

Hiding the scratchpad keeps the applications running. Closing a window is a
different operation.

## OCR

English model: `~/.local/share/tessdata/eng.traineddata`, from
https://github.com/tesseract-ocr/tessdata_fast/tree/4.1.0 (Apache-2.0).
Recognition is local. Temporary screenshots are removed after recognition.
The clipboard changes only when recognition returns nonempty text; Escape,
empty recognition, and errors leave it unchanged. Text is never auto-pasted.
Normal clipboard-history rules still apply to copied OCR text.

## Recovery

Original user configs are backed up in
`backups/workflows-20260926-152846/`. After editing user configuration, run
`hyprctl reload` and inspect `hyprctl configerrors`.
