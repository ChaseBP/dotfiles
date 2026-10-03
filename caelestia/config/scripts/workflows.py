#!/usr/bin/env python3
"""Personal Caelestia workflows; invoked only through supported user bindings."""
import fcntl
import json
import os
from datetime import datetime
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

HOME = Path.home()
NOTES = HOME / "Documents" / "Notes"
WORKSPACE = "special:todo"
TYPED_CLASS = "local.caelestia.typed-notes"
NOTE_CLASS = "local.caelestia.note"  # editable notes other than the inbox
PEN_CLASSES = {"com.github.flxzt.rnote", "rnote"}
NOTE_SUFFIXES = (".md", ".markdown", ".txt", ".org")
# Buffer-local saves keep normal editor behavior untouched elsewhere.
AUTOSAVE = ("lua vim.api.nvim_create_autocmd({'TextChanged','TextChangedI','InsertLeave',"
            "'FocusLost','BufLeave'},{buffer=0,callback=function() "
            "if vim.bo.modified and vim.bo.modifiable and not vim.bo.readonly then "
            "vim.cmd('silent update') end end})")


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, check=True, **kwargs)


def notify(message, error=False):
    ocr_status(message, "error" if error else "info", title="Notes & tools")


def ocr_status(message, stage="info", title="OCR"):
    # Normal shell toasts may be hidden in fullscreen. Use the compositor's
    # overlay there, and also as a fallback if shell IPC is unavailable.
    try:
        fullscreen = bool(ipc("activewindow").get("fullscreen", 0))
        if not fullscreen:
            run(["qs", "-c", "caelestia", "ipc", "call", "toaster", stage,
                 title, message, {"info": "document_scanner", "success": "content_copy",
                                   "warn": "info", "error": "error"}[stage]], timeout=2)
            return
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    try:
        run(["hyprctl", "notify", "-1", "5000", "rgb(89b4fa)", title + ": " + message], timeout=2)
    except (OSError, subprocess.SubprocessError):
        pass


def ipc(query):
    return json.loads(run(["hyprctl", "-j", query]).stdout)


def lua_string(value):
    # Long strings keep quotes, Unicode, and shell metacharacters inert.
    equals = ""
    while "]" + equals + "]" in value:
        equals += "="
    return "[" + equals + "[" + value + "]" + equals + "]"


def dispatch(expression):
    result = run(["hyprctl", "eval", "hl.dispatch(" + expression + ")"])
    if result.stdout.strip() != "ok":
        raise RuntimeError(result.stdout.strip() or result.stderr.strip())


def focus(client):
    dispatch("hl.dsp.focus({window = " + lua_string("address:" + client["address"]) + "})")


def recent(clients):
    return sorted(clients, key=lambda c: c.get("focusHistoryID", 999999)
                  if c.get("focusHistoryID", -1) >= 0 else 999999)


def previous():
    active = ipc("activewindow").get("address")
    if not active:
        return
    candidates = recent([c for c in ipc("clients")
                         if c.get("mapped", False) and not c.get("hidden", False)
                         and c.get("address") != active and c.get("focusHistoryID", -1) >= 0])
    if candidates:
        focus(candidates[0])


def picker(rows, prompt):
    result = subprocess.run(
        ["fuzzel", "--dmenu", "--index", "--only-match", "--no-sort",
         "--lines", str(min(12, len(rows))), "--width", "65", "--prompt", prompt],
        input="\n".join(rows) + "\n", capture_output=True, text=True)
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        index = int(result.stdout.strip())
    except ValueError:
        return None
    return index if 0 <= index < len(rows) else None


def clean_label(text):
    return " ".join(str(text).split())


def windows():
    clients = recent([c for c in ipc("clients") if c.get("mapped", True)])
    if not clients:
        notify("No open windows.")
        return
    rows = [f"{clean_label(c.get('title') or c['class'])}  —  "
            f"{clean_label(c['class'])} · {clean_label(c['workspace']['name'])}"
            for c in clients]
    index = picker(rows, "Windows > ")
    if index is None:
        return
    # The window may have closed while the chooser was open.
    selected = next((c for c in ipc("clients")
                     if c["address"] == clients[index]["address"]), None)
    if selected:
        focus(selected)
    else:
        notify("That window has closed.")


def show_notes(client):
    if client["workspace"]["name"] != WORKSPACE:
        dispatch("hl.dsp.window.move({window = " + lua_string("address:" + client["address"])
                 + ", workspace = " + lua_string(WORKSPACE) + ", follow = false})")
    dispatch("hl.dsp.focus({workspace = " + lua_string(WORKSPACE) + "})")
    focus(client)


def spawn(args):
    if args[0] == "ghostty" and "-e" in args:
        executable = args[args.index("-e") + 1]
        if executable.startswith("/") and not os.access(executable, os.X_OK):
            raise RuntimeError("Executable is missing or cannot run: " + executable)
    child = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(0.1)
    if child.poll() not in (None, 0):
        raise RuntimeError("Could not launch " + args[0])
    return child


def note_filename(title, existing, now=None):
    """File name for a new note titled `title`, never one of `existing`.

    Slashes and control characters become dashes, leading dots go (no hidden
    files), and a missing note extension becomes .md. An empty title gets a
    dated name. Clashes count up: "Idea.md", "Idea 2.md", "Idea 3.md".
    """
    title = " ".join(re.sub(r"[/\\\x00-\x1f\x7f]", "-", title).split()).lstrip(".").strip(" .-")
    if not title:
        title = (now or datetime.now()).strftime("Note %Y-%m-%d %H.%M")
    stem, suffix = title, ".md"
    for ending in NOTE_SUFFIXES:
        if title.lower().endswith(ending) and len(title) > len(ending):
            stem, suffix = title[:-len(ending)].rstrip(" ."), title[-len(ending):]
            break
    stem = stem[:80].rstrip(" .") or "Note"
    taken = {name.casefold() for name in existing}
    name, number = stem + suffix, 1
    while name.casefold() in taken:
        number += 1
        name = f"{stem} {number}{suffix}"
    return name


def note_heading(name):
    stem = name.rsplit(".", 1)[0]
    return f"# {stem}\n\n"


def open_note_window(args, is_kind, clients):
    """Spawn args, then move the first new window that is_kind accepts into the
    notes workspace. Only claims windows created by this call."""
    before = {c["address"] for c in clients}
    spawn(args)
    for _ in range(60):
        for client in ipc("clients"):
            if is_kind(client) and client["address"] not in before:
                show_notes(client)
                return
        time.sleep(0.1)
    notify("Notes did not open in time. Try again.", error=True)


def edit_note(path, line=None, extra=()):
    """Editable Neovim on a note in the notes workspace, autosaving. A window
    already showing this note is reused (no duplicate editors or swap prompts)."""
    path = Path(path).resolve()
    clients = recent(ipc("clients"))
    inbox = path == (NOTES / "Inbox.md").resolve()
    title = "Typed notes" if inbox else "Note — " + str(path.relative_to(NOTES.resolve()))
    klass = TYPED_CLASS if inbox else NOTE_CLASS
    existing = [c for c in clients if c["class"] == klass and (inbox or c.get("title") == title)]
    if existing:
        show_notes(existing[0])
        return
    position = ["+" + str(line)] if line else []
    open_note_window(["ghostty", "--class=" + klass, "--title=" + title, "-e",
                      str(HOME / ".local/bin/nvim"), "-c", AUTOSAVE, *extra, *position, "--", str(path)],
                     lambda c: c["class"] == klass, clients)


def notes_new():
    """Ask for a title, create the note, and open it ready to type."""
    result = subprocess.run(
        ["fuzzel", "--dmenu", "--prompt-only=New note  ",
         "--placeholder=Title — Enter alone makes a dated note", "--width", "52"],
        input="", capture_output=True, text=True)
    if result.returncode != 0:
        return  # Escape cancels without creating anything.
    NOTES.mkdir(parents=True, exist_ok=True)
    name = note_filename(result.stdout.strip(), [p.name for p in NOTES.iterdir()])
    path = NOTES / name
    with path.open("x") as handle:  # never overwrite, even if a file appeared meanwhile
        handle.write(note_heading(name))
    # Cursor on the empty line under the heading, already in insert mode.
    edit_note(path, line=2, extra=("-c", "startinsert"))


def notes_open(path, line):
    """Open an existing note for editing (from the palette's note search)."""
    path = Path(path)
    if (not path.is_file() or path.is_symlink()
            or not path.resolve().is_relative_to(NOTES.resolve())
            or path.suffix.lower() not in NOTE_SUFFIXES):
        raise ValueError("That note moved or is not in Documents/Notes.")
    edit_note(path, line=max(1, int(line)))


NOTE_CHOICES = ["Typed notes  —  Markdown inbox",
                "New note  —  name a fresh Markdown file",
                "Pen notes  —  Rnote notebook"]


def notes(force_choose=False):
    clients = recent(ipc("clients"))
    if not force_choose:
        monitor = next((m for m in ipc("monitors") if m.get("focused")), {})
        if monitor.get("specialWorkspace", {}).get("name") == WORKSPACE:
            dispatch('hl.dsp.workspace.toggle_special("todo")')
            return
        existing = [c for c in clients if c["workspace"]["name"] == WORKSPACE
                    and (c["class"] in (TYPED_CLASS, NOTE_CLASS) or c["class"] in PEN_CLASSES)]
        if existing:
            show_notes(existing[0])
            return

    choice = picker(NOTE_CHOICES, "Notes > ")
    if choice is None:
        return
    if choice == 1:
        notes_new()
        return
    pen = choice == 2
    is_kind = (lambda c: c["class"] in PEN_CLASSES) if pen else (lambda c: c["class"] == TYPED_CLASS)
    # Refresh after the chooser; use the most recently focused matching window.
    matches = recent([c for c in ipc("clients") if is_kind(c)])
    if matches:
        show_notes(matches[0])
        return

    NOTES.mkdir(parents=True, exist_ok=True)
    if not pen:
        inbox = NOTES / "Inbox.md"
        if not inbox.exists():
            inbox.write_text("# Inbox\n\n")
        open_note_window(["ghostty", "--class=" + TYPED_CLASS, "--title=Typed notes", "-e",
                          str(HOME / ".local/bin/nvim"), "-c", AUTOSAVE, str(inbox)], is_kind, clients)
    else:
        notebook = NOTES / "Pen notes.rnote"
        if not notebook.exists():
            run(["rnote-cli", "create", str(notebook)])
        open_note_window(["rnote", str(notebook)], is_kind, clients)


def ocr():
    selection = subprocess.run(["slurp"], capture_output=True, text=True)
    if selection.returncode != 0:
        return
    geometry = selection.stdout.strip()
    if not re.fullmatch(r"-?\d+,-?\d+ \d+x\d+", geometry):
        return
    data = HOME / ".local/share/tessdata"
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="caelestia-ocr-") as directory:
        screenshot = str(Path(directory) / "region.png")
        run(["grim", "-g", geometry, screenshot])
        ocr_status("Reading selected text…")
        text = run(["tesseract", screenshot, "stdout", "--tessdata-dir", str(data),
                    "-l", "eng", "--psm", "3"], timeout=60,
                   env={**os.environ, "OMP_THREAD_LIMIT": "1"}).stdout.strip()
    if not text:
        ocr_status("No text found. Clipboard unchanged.", "warn")
        return
    # wl-copy leaves a background clipboard owner. Do not capture output pipes:
    # an inherited pipe can delay completion until ownership changes.
    subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"], input=text,
                   text=True, check=True, timeout=5, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    elapsed = time.monotonic() - started
    ocr_status(f"Copied {len(text):,} characters in {elapsed:.1f}s. Ready to paste.", "success")


def main():
    import palette
    this = sys.modules[__name__]
    actions = {"windows": windows, "previous": previous, "notes": notes,
               "notes-choose": lambda: notes(True), "notes-new": notes_new,
               "notes-open": lambda: notes_open(*sys.argv[2:4]), "ocr": ocr,
               "projects": lambda: spawn(["ghostty", "-e", str(HOME/".local/bin/tmux-revive")]),
               "palette": lambda: palette.palette(this),
               "notes-search": lambda: palette.search_notes(this)}
    # notes-open takes a note path and line; every other action takes nothing.
    arity = 4 if len(sys.argv) > 1 and sys.argv[1] == "notes-open" else 2
    if len(sys.argv) != arity or sys.argv[1] not in actions:
        raise SystemExit("Usage: workflows.py {" + "|".join(actions) + "} (notes-open PATH LINE)")
    action = sys.argv[1]
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
    lock_name = "notes" if action.startswith("notes") else action
    if action in ("palette", "notes-search"):
        lock_name = "palette-ui"
    # Suppress repeated presses while a picker, launch, or OCR is in progress.
    with (runtime / f"caelestia-workflow-{os.getuid()}-{lock_name}.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            if action == "palette":
                palette.dismiss()
            if action == "ocr":
                ocr_status("An OCR selection or recognition is already in progress.")
            return
        try:
            followup = actions[action]()
        except (OSError, ValueError, subprocess.SubprocessError, RuntimeError) as error:
            if action == "ocr":
                ocr_status("Could not finish recognition/copying. Try a smaller region.", "error")
            else:
                notify("Action failed: " + str(error)[:250], error=True)
            raise SystemExit(1)
    # Release the palette lock before opening the chosen workflow's own UI.
    if isinstance(followup, str) and followup in actions:
        spawn([sys.executable, str(Path(__file__).resolve()), followup])


if __name__ == "__main__":
    main()
