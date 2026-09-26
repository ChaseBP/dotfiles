"""Searchable action palette and read-only note retrieval."""
import json
import os
from pathlib import Path
import subprocess

from palette_catalog import stock_actions

BASE = Path(__file__).resolve().parent.parent
NAMESPACE = "caelestia-palette"


def dismiss():
    try:
        subprocess.run(['qs', '-p', str(BASE/'palette'), 'ipc', 'call', 'palette', 'close'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
    except (OSError, subprocess.SubprocessError):
        pass


def open_panel(w, view='commands'):
    result = subprocess.run(['qs', '-p', str(BASE/'palette'), '--no-color'],
                            env={**os.environ, 'CAELESTIA_PALETTE_VIEW': view},
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        raise RuntimeError('Could not open command panel: ' + result.stdout[-250:])


def chord(key):
    parts = [p.strip().lower() for p in key.split("+")]
    mask = sum({"super": 64, "ctrl": 4, "control": 4, "alt": 8, "shift": 1}.get(p, 0) for p in parts[:-1])
    return mask, parts[-1]


def live_chord(bind):
    return bind["modmask"], bind["key"].lower()


def display_keys(keys):
    def pretty(key):
        if key == "SUPER + SUPER_L":
            return "Super (tap)"
        return key.replace("SUPER", "Super").replace("SHIFT", "Shift").replace("CTRL", "Ctrl").replace("ALT", "Alt").replace(" + ", "+").replace("Slash", "/").replace("mouse:272", "left-drag").replace("mouse:273", "right-drag")
    return " / ".join(pretty(k) for k in keys) or "Palette action"


def catalog(w):
    v = json.loads(w.run(["lua", str(BASE / "scripts/palette-vars.lua")]).stdout)
    live = w.ipc("binds")
    enabled = {live_chord(b) for b in live if not b.get("submap")}
    custom = json.loads((BASE / "actions.json").read_text())
    result, covered = [], set()
    for item in custom + stock_actions(v):
        configured = item.get("keys", [])
        if not configured and not item.get("workflow"):
            continue
        keys = [key for key in configured if chord(key) in enabled]
        if configured and not keys:
            continue
        item = dict(item, keys=keys)
        item.setdefault("group", "Your workflows")
        covered.update(chord(key) for key in keys)
        result.append(item)
    for b in live:
        if live_chord(b) in covered and not b.get("submap"):
            continue
        mods = [name for bit, name in [(4, "CTRL"), (64, "SUPER"), (8, "ALT"), (1, "SHIFT")] if b["modmask"] & bit]
        key = " + ".join(mods + [b["key"] or "code:" + str(b["keycode"])])
        result.append(dict(id="unknown:"+key, label=b.get("description") or "Uncatalogued shortcut — use its key combination", group="Other", keys=[key], keywords=b.get("submap", "")))
    for fingers, direction, label in [
        (v['workspaceSwipeFingers'], 'horizontal', 'Change workspace'),
        (v['gestureFingers'], 'up', 'Show scratchpad'),
        (v['gestureFingers'], 'down', 'Hide or show scratchpad'),
        (v['gestureFingersMore'], 'down', 'Suspend computer'),
    ]:
        result.append(dict(id=f'gesture:{fingers}:{direction}',label=label,group='Gestures',keys=[f'{fingers}-finger swipe {direction}'],keywords='touchpad gesture swipe'))
    return result


def state_path():
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home()/".local/state"))) / "caelestia/palette-recent.json"


def palette(w):
    open_panel(w)


def note_rows(root):
    results = []
    if not root.exists():
        return results
    for path in sorted(root.rglob('*')):
        if path.suffix.lower() not in ('.md', '.txt', '.org', '.markdown') or not path.is_file():
            continue
        if not path.resolve().is_relative_to(root.resolve()) or any(p.startswith('.') for p in path.relative_to(root).parts):
            continue
        if path.stat().st_size > 2_000_000:
            continue
        name = str(path.relative_to(root))
        results.append((path, 1, name, name))
        for line, text in enumerate(path.read_text(errors='replace').splitlines(), 1):
            if text.strip():
                results.append((path, line, f'{name}:{line}  —  {text.strip()[:160]}', text[:4000]))
            if len(results) >= 20000:
                return results
    return results


def search_notes(w):
    open_panel(w, 'notes')
