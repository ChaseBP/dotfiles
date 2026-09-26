"""Local command-panel model. QML sends structured requests over stdin."""
import copy
import html
import json
import os
from pathlib import Path
import re
import sys

import palette
import palette_theme
import workflows as w

COMMON = ['notes', 'windows', 'ocr', 'notes-search', 'projects', 'kbClipboard']
FAMILIES = {
    'kbGoToWs': 'Go to workspace', 'kbMoveWinToWs': 'Send window to workspace',
    'kbGoToWsGroup': 'Go to workspace group', 'kbMoveWinToWsGroup': 'Send window to workspace group',
}
DETAILS = {
    'notes': 'Show or hide your notes workspace. If no notes are open there, choose typed or pen notes. Hiding keeps your work open.',
    'notes-choose': 'Choose typed notes or pen notes. Existing note windows are reused; choosing Rnote brings its current document into the notes workspace.',
    'notes-search': 'Search typed notes by filename and content. Results open read-only at the matched line. Handwriting inside Rnote notebooks is not indexed.',
    'ocr': 'Select a screen region. English text is recognized locally and copied without auto-pasting. Progress and copied-character count appear in a toast. Escape cancels selection.',
    'projects': 'Open your tmux-revive session and profile picker in a new terminal. Attaching a session that is already open creates another synchronized view of that session.',
    'previous': 'Focus the most recently used eligible window across workspaces. This does not create or duplicate windows.',
    'windows': 'Find an existing window by its title, application, or workspace, then focus it.',
    'kbClipboard': 'Choose an earlier clipboard entry to copy again.',
    'kbMoveWindow': 'Hold Super and drag with the left mouse button. Alternatively, hold Super+Z while dragging with the left button.',
    'kbResizeWindow': 'Hold Super and drag with the right mouse button. Alternatively, hold Super+X while dragging with the left button.',
    'kbClipboardPasteLatest': 'Use the displayed shortcut in the destination window. It types the latest saved clipboard-history entry, which may differ from the current clipboard.',
}
SUMMARIES = {
    'notes': 'Capture a thought or return to your notebook',
    'windows': 'Search window titles and applications',
    'ocr': 'Read text from an image and copy it',
    'notes-search': 'Find a filename or something you wrote',
    'projects': 'Resume a tmux session or saved profile',
    'previous': 'Return to your last window across workspaces',
    'notes-choose': 'Choose Markdown or handwriting',
}


def normalized(text):
    return ' '.join(re.findall(r'\w+', str(text).casefold()))


def rank(query, entry):
    q = normalized(query)
    if not q:
        return 0
    title = normalized(entry['label'])
    keys = normalized(' '.join(entry.get('keys', [])))
    words = q.split()
    if q == title or q.replace(' ', '') == keys.replace(' ', ''):
        return 0
    if title.startswith(q):
        return 1
    if all(word in title for word in words):
        return 2
    if all(word in title + ' ' + keys for word in words):
        return 3
    extra = normalized(entry.get('keywords', '') + ' ' + entry.get('group', ''))
    if all(word in title + ' ' + keys + ' ' + extra for word in words):
        return 4
    # A small subsequence fallback handles omitted characters without outranking
    # direct words or synonyms.
    if len(q) >= 3 and ' ' not in q:
        it = iter(title)
        if all(any(c == item for item in it) for c in q):
            return 5
    return None


def marked(text, query):
    """Escape note content before marking literal search terms for QML."""
    terms = sorted(set(normalized(query).split()), key=len, reverse=True)
    if not terms:
        return html.escape(text)
    pattern = re.compile('(' + '|'.join(re.escape(t) for t in terms) + ')', re.I)
    return ''.join('<b><u>' + html.escape(part) + '</u></b>' if i % 2 else html.escape(part)
                   for i, part in enumerate(pattern.split(text)))


class Model:
    def __init__(self, entries=None, active=None, clients=None, start='commands', notes_root=None):
        self.entries = [dict(e) for e in (palette.catalog(w) if entries is None else entries) if e['id'] != 'palette']
        self.lookup = {e['id']: e for e in self.entries}
        self.active = w.ipc('activewindow') if active is None else active
        self.clients = w.ipc('clients') if clients is None else clients
        self.notes_root = notes_root or w.NOTES
        self.notes = None
        self.note_warning = ''
        self.stack = []
        self.state = dict(view='commands', query='', category='All', selected='', scroll=0)
        self.pending = None
        self.last_rows = []
        self.message = ''
        self.recent = self.read_recent()
        if start == 'notes':
            self.push('notes')

    @staticmethod
    def read_recent():
        try:
            data = json.loads(palette.state_path().read_text())
            return [x for x in data if isinstance(x, str)][:5] if isinstance(data, list) else []
        except (OSError, ValueError):
            return []

    def push(self, view, **extra):
        self.stack.append(copy.deepcopy(self.state))
        self.state = dict(view=view, query='', category='All', selected='', scroll=0, **extra)

    def family(self, e):
        for prefix in FAMILIES:
            if re.fullmatch(re.escape(prefix) + r'\d+', e['id']):
                return prefix
        return None

    def unavailable(self, e):
        if e['id'] == 'previous':
            if not any(c.get('mapped') and not c.get('hidden') and c.get('address') != self.active.get('address') and c.get('focusHistoryID', -1) >= 0 for c in self.clients):
                return 'No previous window is available.'
        needs_window = e.get('group') == 'Windows' or e['id'].startswith('kbMoveWin')
        if needs_window and not self.active.get('address'):
            return 'Focus a window first.'
        return ''

    def row(self, e, section=''):
        reference = not (e.get('lua') or e.get('workflow'))
        kind = e.get('kind') or ('guide' if reference else 'confirm' if e.get('confirm') else 'action')
        why = self.unavailable(e)
        keys = e.get('keys', [])
        return dict(id=e['id'], title=e['label'], titleHtml=marked(e['label'], self.state['query']),
                    subtitle=why or ('Shortcut instructions' if kind == 'guide' else SUMMARIES.get(e['id'],e.get('group', ''))),
                    key=palette.display_keys(keys[:1]) if keys else '', section=section, group=e.get('group', ''),
                    kind=kind, disabled=bool(why), reason=why, detail=DETAILS.get(e['id'], ''),
                    badge='Guide' if kind == 'guide' else 'Confirm' if kind == 'confirm' else 'Choose' if kind in ('family', 'browse') else '')

    def command_rows(self):
        q, category = self.state['query'], self.state['category']
        base = self.entries
        if self.state['view'] == 'family':
            base = [e for e in base if self.family(e) == self.state['family']]
        elif not re.search(r'\d', q):
            base = [e for e in base if not self.family(e)]
            for prefix, label in FAMILIES.items():
                if any(self.family(e) == prefix for e in self.entries):
                    base.append(dict(id='family:'+prefix, label=label+'…', group='Workspaces', kind='family', keys=[], keywords='number desktop destination'))
        if category == 'Guides':
            base = [e for e in base if not(e.get('lua') or e.get('workflow') or e.get('kind') == 'family')]
        elif category not in ('All', 'Browse all'):
            base = [e for e in base if e.get('group') == category]
        if not q.strip() and category == 'All' and self.state['view'] == 'commands':
            rows = [self.row(self.lookup[i], 'Common') for i in COMMON if i in self.lookup]
            rows += [self.row(self.lookup[i], 'Recent') for i in self.recent if i in self.lookup and i not in COMMON and not self.lookup[i].get('confirm')]
            rows.append(dict(id='browse',title='Browse all commands and shortcuts',titleHtml='Browse all commands and shortcuts',subtitle='Explore by category',key='',section='Explore',kind='browse',disabled=False,badge='Browse'))
            return rows
        ranked = [(rank(q, e), e) for e in base]
        ranked = [(score, e) for score, e in ranked if score is not None]
        ranked.sort(key=lambda p: (p[0], self.recent.index(p[1]['id']) if q and p[1]['id'] in self.recent else 99, p[1]['label'].casefold()))
        return [self.row(e, 'Results' if q else e.get('group', 'Commands')) for _, e in ranked]

    def load_notes(self):
        self.notes = []
        skipped = 0
        used = 0
        for path in sorted(self.notes_root.rglob('*')) if self.notes_root.exists() else []:
            if path.suffix.lower() not in ('.md', '.txt', '.org', '.markdown') or not path.is_file():
                continue
            if any(p.startswith('.') for p in path.relative_to(self.notes_root).parts) or not path.resolve().is_relative_to(self.notes_root.resolve()):
                continue
            try:
                size = path.stat().st_size
                if size > 2_000_000 or used + size > 20_000_000 or len(self.notes) >= 500:
                    skipped += 1
                    continue
                text = path.read_text(errors='replace')
                used += size
                self.notes.append(dict(path=path, name=str(path.relative_to(self.notes_root)), lines=text.splitlines()))
            except OSError:
                skipped += 1
        self.note_warning = f'{skipped} files omitted because of size, access, or indexing limits.' if skipped else ''

    def note_rows(self):
        if self.notes is None:
            self.load_notes()
        q = self.state['query']
        terms = normalized(q).split()
        results = []
        for i, note in enumerate(self.notes):
            name_match = all(t in normalized(note['name']) for t in terms)
            hits = [j for j,line in enumerate(note['lines']) if terms and all(t in normalized(line) for t in terms)]
            if terms and not name_match and not hits:
                continue
            line = hits[0] if hits else 0
            excerpt = '\n'.join(note['lines'][max(0,line-1):line+3])[:1800]
            results.append(dict(id=f'note:{i}:{line+1}', title=note['name'], titleHtml=marked(note['name'], q),
                                subtitle=f'{len(hits)} matching lines · line {line+1}' if terms else 'Read-only reference',
                                key='', section='Notes', kind='note', disabled=False, badge='Open',
                                preview=marked(excerpt or 'Empty note', q).replace('\n','<br>'), previewPlain=excerpt,
                                hits=[j+1 for j in hits[:100]], detail=f'Opens line {line+1} in a read-only notes window.'))
        results.sort(key=lambda r: (0 if normalized(q) in normalized(r['title']) else 1, r['title'].casefold()))
        return results

    def detail(self, ident):
        e = self.lookup.get(ident)
        if not e:
            return {}
        why = self.unavailable(e)
        reference = not(e.get('lua') or e.get('workflow'))
        target = self.active.get('title') or self.active.get('class') or 'No focused window'
        explanation = DETAILS.get(ident, 'Use the displayed input to perform this action.' if reference else e['label']+'.')
        if ident.startswith('unknown:'):
            explanation = 'This binding is active but its behavior has not been verified in the catalog. Use its original shortcut; the panel will not execute it.'
        return dict(id=ident,title=e['label'],body=explanation,keys=[palette.display_keys([k]) for k in e.get('keys',[])],
                    group=e.get('group',''),disabled=bool(why),reason=why,reference=reference,
                    target=target if e.get('group') == 'Windows' or ident.startswith('kbMoveWin') else '',
                    confirmation=self.confirmation(e),button=e['label'])

    def confirmation(self, e):
        if e['id'] == 'kbCloseWindow':
            return 'Close '+(self.active.get('title') or self.active.get('class') or 'the focused window')+'? Unsaved work will depend on the application’s own save prompt.'
        return {
            'kbSleep':'Suspend this computer? Running calls and network connections may be interrupted.',
            'kbClearNotifs':'Clear all desktop notifications?',
            'killShell':'Stop Caelestia? Its panels and notifications will disappear.',
            'restartShell':'Restart Caelestia? Its panels will briefly disappear.',
            'kbRestoreLock':'Restart the shell if needed and lock the screen?',
        }.get(e['id'], e['label']+'?')

    def snapshot(self):
        view=self.state['view']
        rows=self.note_rows() if view=='notes' else [] if view in ('details','confirm') else self.command_rows()
        self.last_rows=rows
        detail=self.detail(self.state.get('entry','')) if view in ('details','confirm') else {}
        title={'commands':'Commands','notes':'Search notes','details':'Shortcut details','confirm':'Confirm action','family':'Choose workspace'}[view]
        return dict(kind='state',view=view,title=title,query=self.state['query'],category=self.state['category'],
                    rows=rows,detail=detail,selected=self.state.get('selected',''),scroll=self.state.get('scroll',0),
                    back=bool(self.stack),message=self.message,
                    notice=(self.note_warning+' ' if self.note_warning else '')+'Typed notes in Documents/Notes · Rnote handwriting is not indexed.' if view=='notes' else '',
                    theme=palette_theme.theme_colors(palette_theme.load_scheme()))

    def handle(self, request):
        op=request.get('op')
        self.message=''
        if op=='theme':
            return dict(kind='theme',theme=palette_theme.theme_colors(palette_theme.load_scheme()))
        if op=='query':
            self.state.update(query=str(request.get('query',''))[:500],category=request.get('category','All'),selected='',scroll=0)
            if request.get('enter'):
                snapshot=self.snapshot()
                if snapshot['rows']:
                    return self.handle(dict(op='activate',id=snapshot['rows'][0]['id']))
        elif op=='back':
            if self.stack:
                self.state=self.stack.pop()
            else:
                return dict(kind='quit')
        elif op=='refresh':
            self.notes=None
        elif op in ('details','activate'):
            ident=request.get('id','')
            visible={r['id']:r for r in self.last_rows}
            if self.state['view'] in ('details','confirm'):
                if ident != self.state.get('entry'):
                    raise ValueError('Action is no longer selected.')
            elif ident not in visible:
                raise ValueError('That result is no longer visible. Search again.')
            self.state.update(selected=ident,scroll=request.get('scroll',0))
            if ident=='browse':
                self.state['category']='Browse all'
            elif ident.startswith('family:'):
                self.push('family',family=ident.split(':',1)[1])
            elif ident=='notes-search' and op=='activate':
                self.push('notes')
            elif ident.startswith('note:'):
                self.pending=ident
                return dict(kind='execute',id=ident)
            else:
                e=self.lookup[ident]
                why=self.unavailable(e)
                if why and op=='activate':
                    self.message=why
                elif op=='details' or not(e.get('workflow') or e.get('lua')):
                    self.push('details',entry=ident)
                elif e.get('confirm') and self.state['view']!='confirm':
                    self.push('confirm',entry=ident)
                elif e.get('confirm') and request.get('confirmed') is not True:
                    self.message='Choose Cancel or confirm this action explicitly.'
                else:
                    self.pending=ident
                    return dict(kind='execute',id=ident)
        elif op=='execute':
            ident=request.get('id')
            if not self.pending or ident != self.pending:
                raise ValueError('No action is pending.')
            self.pending=None
            self.execute(ident)
            return dict(kind='quit')
        return self.snapshot()

    def execute(self, ident):
        if ident.startswith('note:'):
            _, index, line=ident.split(':')
            path=self.notes[int(index)]['path']
            if not path.is_file() or not path.resolve().is_relative_to(self.notes_root.resolve()):
                raise ValueError('This note moved or is no longer available.')
            w.spawn(['ghostty','--class=local.caelestia.note-search','--title=Note reference','-e',str(w.HOME/'.local/bin/nvim'),'-R','-n','+'+line,'--',str(path)])
            return
        e=self.lookup[ident]
        if e.get('group') in ('Windows','Workspaces') and self.active.get('address'):
            current=next((c for c in w.ipc('clients') if c['address']==self.active['address']),None)
            if current is None:
                raise ValueError('The original window closed. No action was taken.')
            w.focus(current)
        if e.get('workflow'):
            w.spawn([sys.executable,str(palette.BASE/'scripts/workflows.py'),e['workflow']])
        else:
            output=w.run(['hyprctl','eval','local v=require("variables");local fn=require("utils.functions");'+e['lua']]).stdout.strip()
            if output!='ok':
                raise RuntimeError(output)
        if not e.get('confirm'):
            try:
                palette.state_path().parent.mkdir(parents=True,exist_ok=True)
                palette.state_path().write_text(json.dumps([ident]+[i for i in self.recent if i!=ident][:4]))
            except OSError:
                pass


def main():
    model=None
    for line in sys.stdin:
        try:
            request=json.loads(line)
            if model is None:
                model=Model(start=os.environ.get('CAELESTIA_PALETTE_VIEW','commands'))
            result=model.handle(request)
        except Exception as error:
            result=dict(kind='error',message=str(error)[:350])
        print(json.dumps(result,ensure_ascii=False),flush=True)


if __name__=='__main__':
    main()
