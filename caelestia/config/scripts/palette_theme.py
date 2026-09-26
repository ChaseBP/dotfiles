"""Use Caelestia's current wallpaper scheme with opaque, readable colors."""
import json
import os
from pathlib import Path
import re
import time

DEFAULT = {
    'surfaceContainerLow': '101216', 'onSurface': 'f1f3f5',
    'onSurfaceVariant': 'aeb8ca', 'primary': '89b4fa',
    'onPrimary': '101216', 'outline': '8996ad',
    'surface': '101216', 'surfaceContainer': '181a1f', 'surfaceContainerHigh': '22252b',
    'surfaceContainerHighest': '2c2f36', 'outlineVariant': '44474f',
    'primaryContainer': '284777', 'onPrimaryContainer': 'd6e3ff',
    'secondaryContainer': '3e4759', 'onSecondaryContainer': 'dae2f9',
    'tertiaryContainer': '573e5c', 'onTertiaryContainer': 'fbd7fc',
    'errorContainer': '93000a', 'onErrorContainer': 'ffdad6', 'error': 'ffb4ab', 'onError': '690005',
    'shadow': '000000',
}


def luminance(color):
    rgb = [int(color[i:i+2], 16)/255 for i in (0, 2, 4)]
    linear = [x/12.92 if x <= .04045 else ((x+.055)/1.055)**2.4 for x in rgb]
    return sum(x*y for x,y in zip(linear, (.2126, .7152, .0722)))


def contrast(a, b):
    light, dark = sorted((luminance(a), luminance(b)), reverse=True)
    return (light+.05)/(dark+.05)


def readable(preferred, background, fallback, minimum=4.5):
    for color in (preferred, fallback):
        if contrast(color, background) >= minimum:
            return color
    return max(('000000', 'ffffff'), key=lambda c: contrast(c, background))


def load_scheme(path=None):
    if path is None:
        path = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))) / 'caelestia/scheme.json'
    for attempt in range(3):
        try:
            raw = json.loads(path.read_text()).get('colours', {})
            if not isinstance(raw, dict):
                break
            colors = {k: v.lower() for k,v in raw.items()
                      if isinstance(v, str) and re.fullmatch(r'[0-9a-fA-F]{6}', v)}
            if colors:
                return {**DEFAULT, **colors}
        except (OSError, ValueError, AttributeError):
            pass
        if attempt < 2:
            time.sleep(.02)
    return DEFAULT.copy()


def theme_colors(scheme):
    background = scheme['surfaceContainerLow']
    text = readable(scheme['onSurface'], background, 'ffffff')
    secondary = readable(scheme['onSurfaceVariant'], background, text)
    accent = readable(scheme['primary'], background, text)
    selection = readable(scheme['primary'], background, text, minimum=3)
    selected_text = readable(scheme['onPrimary'], selection, text)
    border = readable(scheme['outline'], background, accent, minimum=3)
    return {
        'background': background, 'text': text, 'input': text,
        'prompt': accent, 'placeholder': secondary, 'message': secondary,
        'counter': secondary, 'match': accent, 'selection': selection,
        'selection-text': selected_text, 'selection-match': selected_text,
        'border': border,
        **material_roles(scheme, text),
    }


def material_roles(scheme, text):
    """Caelestia's M3 surface/container roles for the QML panel, each 'on' colour
    held to 4.5:1 on its own container and the indicator colours to 3:1 on the panel."""
    surface = scheme['surface']
    roles = {k: scheme[k] for k in ('surface', 'surfaceContainer', 'surfaceContainerHigh',
                                    'surfaceContainerHighest', 'outlineVariant', 'shadow')}
    body = readable(scheme['onSurface'], surface, 'ffffff')
    roles.update(onSurface=body,
                 onSurfaceVariant=readable(scheme['onSurfaceVariant'], scheme['surfaceContainerHigh'], body),
                 primary=readable(scheme['primary'], surface, text, minimum=3),
                 error=readable(scheme['error'], surface, text, minimum=3))
    roles['onPrimary'] = readable(scheme['onPrimary'], roles['primary'], body)
    roles['onError'] = readable(scheme['onError'], roles['error'], body)
    for name in ('primary', 'secondary', 'tertiary', 'error'):
        container = scheme[name + 'Container']
        cap = name[0].upper() + name[1:]
        roles[name + 'Container'] = container
        roles['on' + cap + 'Container'] = readable(scheme['on' + cap + 'Container'], container, body)
    return roles


def arguments():
    # Called for every opening, including confirmation and note-search panels.
    return [f'--{name}-color={color}ff' for name,color in theme_colors(load_scheme()).items()]
