"""Open and dismiss the Super+K palette (palette/shell.qml) for workflows.py."""
import os
from pathlib import Path
import subprocess

BASE = Path(__file__).resolve().parent.parent


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


def palette(w):
    open_panel(w)


def search_notes(w):
    open_panel(w, 'notes')
