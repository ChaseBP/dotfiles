.pragma library
// Command-panel model for shell.qml: catalog, ranking, navigation and safety.
// Pure functions and state only — every file, process and Hyprland call lives in
// shell.qml — so this file also runs under Node for tests (test_palette.mjs).
//
// Runs in Qt's V4 engine, which lacks flat/flatMap/replaceAll and object spread,
// and whose Unicode property classes (backslash-p) silently match nothing.
// test_palette.mjs guards against all of these.

const COMMON = ['notes', 'windows', 'ocr', 'notes-search', 'projects', 'kbClipboard'];
const FAMILIES = {
    kbGoToWs: 'Go to workspace', kbMoveWinToWs: 'Send window to workspace',
    kbGoToWsGroup: 'Go to workspace group', kbMoveWinToWsGroup: 'Send window to workspace group',
};
const DETAILS = {
    'notes': 'Show or hide your notes workspace. If no notes are open there, choose typed or pen notes. Hiding keeps your work open.',
    'notes-choose': 'Choose the typed-notes inbox, a new named note, or pen notes. Existing note windows are reused; choosing Rnote brings its current document into the notes workspace.',
    'notes-new': 'Type a title (or press Enter alone for a dated one). A new Markdown file is created in Documents/Notes — never overwriting an existing note — and opens in the notes workspace, ready to type. Edits save automatically.',
    'notes-search': 'Search typed notes by filename and content. Enter opens the matched line read-only; Ctrl+E opens it for editing. Handwriting inside Rnote notebooks is not indexed.',
    'ocr': 'Select a screen region. English text is recognized locally and copied without auto-pasting. Progress and copied-character count appear in a toast. Escape cancels selection.',
    'projects': 'Open your tmux-revive session and profile picker in a new terminal. Attaching a session that is already open creates another synchronized view of that session.',
    'previous': 'Focus the most recently used eligible window across workspaces. This does not create or duplicate windows.',
    'windows': 'Find an existing window by its title, application, or workspace, then focus it.',
    'kbClipboard': 'Choose an earlier clipboard entry to copy again.',
    'kbMoveWindow': 'Hold Super and drag with the left mouse button. Alternatively, hold Super+Z while dragging with the left button.',
    'kbResizeWindow': 'Hold Super and drag with the right mouse button. Alternatively, hold Super+X while dragging with the left button.',
    'kbClipboardPasteLatest': 'Use the displayed shortcut in the destination window. It types the latest saved clipboard-history entry, which may differ from the current clipboard.',
};
const SUMMARIES = {
    'notes': 'Capture a thought or return to your notebook',
    'windows': 'Search window titles and applications',
    'ocr': 'Read text from an image and copy it',
    'notes-search': 'Find a filename or something you wrote',
    'projects': 'Resume a tmux session or saved profile',
    'previous': 'Return to your last window across workspaces',
    'notes-choose': 'Inbox, a new note, or handwriting',
    'notes-new': 'Name a fresh Markdown note and start typing',
};
const CONFIRMATIONS = {
    kbSleep: 'Suspend this computer? Running calls and network connections may be interrupted.',
    kbClearNotifs: 'Clear all desktop notifications?',
    killShell: 'Stop Caelestia? Its panels and notifications will disappear.',
    restartShell: 'Restart Caelestia? Its panels will briefly disappear.',
    kbRestoreLock: 'Restart the shell if needed and lock the screen?',
};
const NOTE_EXTENSIONS = ['.md', '.txt', '.org', '.markdown'];
const NOTE_LIMITS = {fileBytes: 2000000, totalBytes: 20000000, files: 500};
// Prefix for every executed catalog action (see stockActions).
const LUA_PRELUDE = 'local v=require("variables");local fn=require("utils.functions");';

// ── Text helpers ──

// Word characters: everything except whitespace, ASCII punctuation (keeping _),
// and the Unicode punctuation/symbol/emoji blocks — close to Python's re \w.
const WORD = /[^\s!-\/:-@\[-^`{-~\u00a0-\u00bf\u00d7\u00f7\u2000-\u2bff\u2e00-\u2e7f\u3000-\u303f\ufe10-\ufe6f\uff00-\uff0f\ud800-\udfff]+/g;

function normalized(text) {
    return (String(text).toLowerCase().match(WORD) || []).join(' ');
}

function escapeHtml(text) {
    return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#x27;');
}

function escapeRegExp(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Escape note content before marking literal search terms; the UI recolours the marks.
function marked(text, query) {
    const terms = Array.from(new Set(normalized(query).split(' ').filter(Boolean))).sort((a, b) => b.length - a.length);
    if (!terms.length)
        return escapeHtml(text);
    const pattern = new RegExp('(' + terms.map(escapeRegExp).join('|') + ')', 'iu');
    return String(text).split(pattern).map((part, i) => i % 2 ? '<b><u>' + escapeHtml(part) + '</u></b>' : escapeHtml(part)).join('');
}

function isSubsequence(needle, haystack) {
    let i = 0;
    for (const c of haystack)
        if (i < needle.length && c === needle[i]) i++;
    return i === needle.length;
}

// 0 exact title/chord · 1 title prefix · 2 title words · 3 title+chord words ·
// 4 synonyms/group · 5 subsequence fallback · null no match.
function rank(query, entry) {
    const q = normalized(query);
    if (!q)
        return 0;
    const title = normalized(entry.label);
    const keys = normalized((entry.keys || []).join(' '));
    const words = q.split(' ');
    if (q === title || q.replace(/ /g, '') === keys.replace(/ /g, ''))
        return 0;
    if (title.startsWith(q))
        return 1;
    if (words.every(w => title.includes(w)))
        return 2;
    if (words.every(w => (title + ' ' + keys).includes(w)))
        return 3;
    const extra = normalized((entry.keywords || '') + ' ' + (entry.group || ''));
    if (words.every(w => (title + ' ' + keys + ' ' + extra).includes(w)))
        return 4;
    // Tolerates omitted characters without outranking direct words or synonyms.
    if (q.length >= 3 && !q.includes(' ') && isSubsequence(q, title))
        return 5;
    return null;
}

function compareText(a, b) {
    a = a.toLowerCase(); b = b.toLowerCase();
    return a < b ? -1 : a > b ? 1 : 0;
}

// ── Keys and catalog ──

const KEY_NAMES = [['SUPER', 'Super'], ['SHIFT', 'Shift'], ['CTRL', 'Ctrl'], ['ALT', 'Alt'], [' + ', '+'],
                   ['Slash', '/'], ['mouse:272', 'left-drag'], ['mouse:273', 'right-drag']];

function displayKeys(keys) {
    const pretty = key => key === 'SUPER + SUPER_L' ? 'Super (tap)'
        : KEY_NAMES.reduce((text, [from, to]) => text.split(from).join(to), key);
    return keys.map(pretty).join(' / ') || 'Palette action';
}

const MODIFIER_BITS = {super: 64, ctrl: 4, control: 4, alt: 8, shift: 1};

function chord(key) {
    const parts = key.split('+').map(p => p.trim().toLowerCase());
    const mask = parts.slice(0, -1).reduce((sum, p) => sum + (MODIFIER_BITS[p] || 0), 0);
    return mask + '|' + parts[parts.length - 1];
}

function liveChord(bind) {
    return bind.modmask + '|' + String(bind.key).toLowerCase();
}

function flatten(value) {
    if (typeof value === 'string')
        return value.trim() ? [value] : [];
    if (Array.isArray(value))
        return value.reduce((all, item) => all.concat(flatten(item)), []);
    return [];
}

// Labels and Lua for Caelestia's stock bindings. Keys come from variables.lua plus
// hypr-vars.lua overrides (v), so remapped shortcuts follow automatically.
function stockActions(v) {
    const rows = [];
    const add = (id, label, group, expr, opts = {}) => rows.push({
        id, label, group,
        keys: flatten(opts.keys === undefined ? (v[id] === undefined ? [] : v[id]) : opts.keys),
        lua: opts.code || (expr ? 'hl.dispatch(' + expr + ')' : null),
        confirm: !!opts.confirm, keywords: opts.keywords || '',
    });

    for (const [id, label, name] of [
        ['kbLauncher', 'Open application launcher', 'launcher'],
        ['kbSession', 'Open session and power menu', 'session'],
        ['kbShowSidebar', 'Show sidebar', 'sidebar'],
        ['kbClearNotifs', 'Clear notifications', 'clearNotifs'],
        ['kbShowPanels', 'Show all Caelestia panels', 'showall'],
        ['kbLock', 'Lock screen', 'lock'],
    ])
        add(id, label, 'Desktop', `hl.dsp.global("caelestia:${name}")`, {confirm: id === 'kbClearNotifs'});
    add('kbRestoreLock', 'Restart shell and restore lock screen', 'System', null, {code: 'hl.dispatch(hl.dsp.exec_cmd("caelestia shell -d")); hl.dispatch(hl.dsp.global("caelestia:lock"))', confirm: true});
    add('kbSleep', 'Suspend computer', 'System', 'hl.dsp.exec_cmd(v.sleepGestureCmd)', {confirm: true});
    for (const [id, label, command] of [
        ['restartShell', 'Restart Caelestia shell', 'qs -c caelestia kill; sleep .1; caelestia shell -d'],
        ['killShell', 'Stop Caelestia shell', 'qs -c caelestia kill'],
    ])
        add(id, label, 'System', `hl.dsp.exec_cmd("${command}")`, {keys: [id === 'restartShell' ? 'CTRL + SUPER + ALT + R' : 'CTRL + SUPER + SHIFT + R'], confirm: true});

    for (const [id, label, field] of [
        ['kbTerminal', 'Open terminal', 'terminal'], ['kbBrowser', 'Open browser', 'browser'], ['kbEditor', 'Open editor', 'editor'],
        ['kbFileExplorer', 'Open file manager', 'fileExplorer'], ['kbAudioSettings', 'Open audio settings', 'audioSettings'],
    ])
        add(id, label, 'Apps', `hl.dsp.exec_cmd(v.${field})`);
    for (const [id, label, ws] of [
        ['kbSpecialWs', 'Show or hide scratchpad', 'specialws'], ['kbSystemMonitorWs', 'Show system monitor', 'sysmon'],
        ['kbCommunicationWs', 'Show communication apps', 'communication'], ['kbMusicWs', 'Show music apps', 'music'],
        ['kbTodoWs', 'Show task apps', 'todo'],
    ])
        add(id, label, 'Desktop', null, {code: `fn.toggle("${ws}")()`});

    for (const [id, label, expr] of [
        ['kbWindowCycleNext', 'Cycle to next window', 'hl.dsp.window.cycle_next()'],
        ['kbWindowCyclePrev', 'Cycle to previous window', 'hl.dsp.window.cycle_next({next=false})'],
        ['kbWindowGroupCycleNext', 'Next window in group', 'hl.dsp.group.next()'],
        ['kbWindowGroupCyclePrev', 'Previous window in group', 'hl.dsp.group.prev()'],
        ['kbToggleGroup', 'Toggle window group', 'hl.dsp.group.toggle()'],
        ['kbUngroup', 'Remove window from group', 'hl.dsp.window.move({out_of_group=true})'],
        ['kbGroupLockActive', 'Toggle active group lock', 'hl.dsp.group.lock_active()'],
        ['kbCenterWindow', 'Center floating window', 'hl.dsp.window.center()'],
        ['kbPinWindow', 'Pin or unpin floating window', 'hl.dsp.window.pin()'],
        ['kbWindowFullscreen', 'Toggle fullscreen', 'hl.dsp.window.fullscreen({mode="fullscreen"})'],
        ['kbWindowBorderedFullscreen', 'Toggle maximized window', 'hl.dsp.window.fullscreen({mode="maximized"})'],
        ['kbToggleWindowFloating', 'Toggle floating window', 'hl.dsp.window.float()'],
        ['kbCloseWindow', 'Close focused window', 'hl.dsp.window.close()'],
    ])
        add(id, label, 'Windows', expr, {confirm: id === 'kbCloseWindow'});
    for (const direction of ['left', 'right', 'up', 'down']) {
        add('focus' + direction, 'Focus window ' + direction, 'Windows', `hl.dsp.focus({direction="${direction}"})`, {keys: ['SUPER + ' + direction]});
        add('move' + direction, 'Move window ' + direction, 'Windows', `hl.dsp.window.move({direction="${direction}"})`, {keys: ['SUPER + SHIFT + ' + direction]});
    }
    for (const [id, label, x, y] of [
        ['kbWindowDecreaseWidth', 'Decrease window width', -10, 0], ['kbWindowIncreaseWidth', 'Increase window width', 10, 0],
        ['kbWindowDecreaseHeight', 'Decrease window height', 0, -10], ['kbWindowIncreaseHeight', 'Increase window height', 0, 10],
    ])
        add(id, label, 'Windows', null, {code: `fn.resize_active_window(${x},${y})()`});
    add('kbNormalizeWindow', 'Normalize window size and center', 'Windows', null, {code: 'hl.dispatch(hl.dsp.window.resize(fn.resize_by_screen(55,70))); hl.dispatch(hl.dsp.window.center())'});
    add('kbWindowPip', 'Put window in picture-in-picture', 'Windows', null, {code: 'local a=hl.get_active_window(); if a then local p=fn.move_actions(a) or {}; if not a.floating then table.insert(p,1,hl.dsp.window.float()) end; table.insert(p,hl.dsp.window.pin({action="on",window="address:"..a.address})); for _,d in ipairs(p) do hl.dispatch(d) end end', keywords: 'pip video corner'});
    add('kbMoveWindow', 'Drag window — hold shortcut and left-drag', 'Mouse', null, {keys: flatten(v.kbMoveWindow).concat(['SUPER + mouse:272'])});
    add('kbResizeWindow', 'Resize window — hold shortcut and drag', 'Mouse', null, {keys: flatten(v.kbResizeWindow).concat(['SUPER + mouse:273'])});

    for (const [id, label, method, ws] of [
        ['kbPrevWs', 'Previous workspace', 'focus', '-1'], ['kbNextWs', 'Next workspace', 'focus', '+1'],
        ['kbPrevWsGroup', 'Previous workspace group', 'focus', '-10'], ['kbNextWsGroup', 'Next workspace group', 'focus', '+10'],
        ['kbMoveWinToWsNext', 'Send window to next workspace', 'window.move', '+1'], ['kbMoveWinToWsPrev', 'Send window to previous workspace', 'window.move', '-1'],
        ['kbMoveWinToWsSpecial', 'Send window to scratchpad', 'window.move', 'special:special'], ['kbMoveWinFromWsSpecial', 'Bring window out of scratchpad', 'window.move', 'e+0'],
    ])
        add(id, label, 'Workspaces', `hl.dsp.${method}({workspace="${ws}"})`);
    for (const [id, label, action, group] of [
        ['kbGoToWs', 'Go to workspace', 'focus', ''], ['kbMoveWinToWs', 'Send window to workspace', 'move', ''],
        ['kbGoToWsGroup', 'Go to workspace group', 'focus', 'group'], ['kbMoveWinToWsGroup', 'Send window to workspace group', 'move', 'group'],
    ]) {
        const base = v[id];
        if (typeof base === 'string' && base.trim())
            for (let i = 1; i <= 10; i++)
                add(id + i, label + ' ' + i, 'Workspaces', null, {code: `fn.wsaction("${action}","${group}",${i})()`, keys: [base + ' + ' + (i % 10)]});
    }

    for (const [id, label, expr] of [
        ['kbScreenshot', 'Capture screenshot', 'hl.dsp.exec_cmd("caelestia screenshot")'],
        ['kbScreenshotFreeze', 'Capture region with frozen screen', 'hl.dsp.global("caelestia:screenshotFreeze")'],
        ['kbScreenshotRegion', 'Capture screen region', 'hl.dsp.global("caelestia:screenshot")'],
        ['kbRecord', 'Start or stop screen recording', 'hl.dsp.exec_cmd("caelestia record")'],
        ['kbRecordSound', 'Record screen with sound', 'hl.dsp.exec_cmd("caelestia record -s")'],
        ['kbRecordRegion', 'Record screen region', 'hl.dsp.exec_cmd("caelestia record -r")'],
        ['kbColorPicker', 'Pick and copy a screen color', 'hl.dsp.exec_cmd("hyprpicker -a")'],
        ['kbClipboard', 'Open clipboard history', 'hl.dsp.exec_cmd("caelestia clipboard")'],
        ['kbClipboardDel', 'Delete clipboard history entries', 'hl.dsp.exec_cmd("caelestia clipboard -d")'],
        ['kbEmoji', 'Choose an emoji', 'hl.dsp.exec_cmd("caelestia emoji -p")'],
    ])
        add(id, label, /^kb(Screenshot|Record|Color)/.test(id) ? 'Capture' : 'Clipboard', expr, {keywords: id.startsWith('kbScreenshot') ? 'snip image capture' : ''});
    add('kbClipboardPasteLatest', 'Type latest history entry — use shortcut in destination', 'Clipboard', null, {keywords: 'paste typing'});
    for (const [id, label, name, hardware] of [
        ['kbMediaToggle', 'Play or pause media', 'mediaToggle', ['XF86AudioPlay', 'XF86AudioPause']],
        ['kbMediaNext', 'Next media track', 'mediaNext', ['XF86AudioNext']],
        ['kbMediaPrev', 'Previous media track', 'mediaPrev', ['XF86AudioPrev']],
        ['kbMediaStop', 'Stop media', 'mediaStop', ['XF86AudioStop']],
    ])
        add(id, label, 'Media', `hl.dsp.global("caelestia:${name}")`, {keys: flatten(v[id]).concat(hardware)});
    for (const [key, label, name] of [['XF86MonBrightnessUp', 'Increase brightness', 'brightnessUp'], ['XF86MonBrightnessDown', 'Decrease brightness', 'brightnessDown']])
        add(key, label, 'Media', `hl.dsp.global("caelestia:${name}")`, {keys: [key]});
    add('kbVolumeMute', 'Mute or unmute speakers', 'Media', 'hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")', {keys: flatten(v.kbVolumeMute).concat(['XF86AudioMute'])});
    add('micMute', 'Mute or unmute microphone', 'Media', 'hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")', {keys: ['XF86AudioMicMute']});
    add('volumeUp', 'Increase volume', 'Media', 'hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l "..(v.volumeMax/100).." @DEFAULT_AUDIO_SINK@ "..v.volumeStep.."%+")', {keys: ['XF86AudioRaiseVolume']});
    add('volumeDown', 'Decrease volume', 'Media', 'hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ "..v.volumeStep.."%-")', {keys: ['XF86AudioLowerVolume']});
    add('wallpaper', 'Choose wallpaper', 'Desktop', 'hl.dsp.exec_cmd(os.getenv("HOME").."/.local/bin/wall")', {keys: ['SUPER + SHIFT + W']});
    add('wallpaperRandom', 'Choose random wallpaper', 'Desktop', 'hl.dsp.exec_cmd(os.getenv("HOME").."/.local/bin/wall random")', {keys: ['SUPER + ALT + W']});
    add('osk', 'Show or hide on-screen keyboard', 'Desktop', 'hl.dsp.exec_cmd(os.getenv("HOME").."/.local/bin/osk toggle")', {keys: ['SUPER + SHIFT + K'], keywords: 'tablet touch typing'});
    for (const on of ['on', 'off'])
        add('tablet' + on, 'Tablet mode ' + on + ' — automatic hinge switch', 'Hardware', null, {keys: ['switch:' + on + ':Intel Virtual Switches']});
    add('testNotification', 'Send test notification — diagnostic shortcut', 'System', null, {keys: ['SUPER + ALT + F12']});
    return rows;
}

// A bind's own description wins for anything the catalog doesn't know. Upstream's
// "Category: Description" format (caelestia-dots/caelestia#503) also sets the group.
function describedBind(description) {
    const m = /^([^:]{1,30}):\s+(.+)$/.exec(description || '');
    return m ? {group: m[1].trim(), label: m[2].trim()} : {group: 'Other', label: description};
}

// actions.json + stock actions, filtered to chords Hyprland really has bound, then
// every remaining live bind as reference-only, then touchpad gestures.
function buildCatalog(vars, binds, actions) {
    // Malformed files or hyprctl output must not break the palette: treat as empty.
    vars = vars && typeof vars === 'object' && !Array.isArray(vars) ? vars : {};
    binds = Array.isArray(binds) ? binds.filter(b => b && typeof b === 'object' && 'modmask' in b) : [];
    actions = Array.isArray(actions) ? actions.filter(a => a && typeof a.id === 'string' && typeof a.label === 'string') : [];
    const enabled = new Set(binds.filter(b => !b.submap).map(liveChord));
    const covered = new Set();
    const result = [];
    for (const item of actions.concat(stockActions(vars))) {
        const configured = item.keys || [];
        if (!configured.length && !item.workflow)
            continue;
        const keys = configured.filter(k => enabled.has(chord(k)));
        if (configured.length && !keys.length)
            continue;
        const entry = Object.assign({}, item, {keys});
        if (!('group' in entry))
            entry.group = 'Your workflows';
        keys.forEach(k => covered.add(chord(k)));
        result.push(entry);
    }
    for (const b of binds) {
        if (covered.has(liveChord(b)) && !b.submap)
            continue;
        const mods = [[4, 'CTRL'], [64, 'SUPER'], [8, 'ALT'], [1, 'SHIFT']].filter(([bit]) => b.modmask & bit).map(([, name]) => name);
        const key = mods.concat([b.key || 'code:' + b.keycode]).join(' + ');
        const described = b.description ? describedBind(b.description) : {group: 'Other', label: 'Uncatalogued shortcut — use its key combination'};
        result.push({id: 'unknown:' + key, label: described.label, group: described.group, keys: [key], keywords: b.submap || ''});
    }
    for (const [fingers, direction, label] of [
        [vars.workspaceSwipeFingers, 'horizontal', 'Change workspace'],
        [vars.gestureFingers, 'up', 'Show scratchpad'],
        [vars.gestureFingers, 'down', 'Hide or show scratchpad'],
        [vars.gestureFingersMore, 'down', 'Suspend computer'],
    ])
        result.push({id: `gesture:${fingers}:${direction}`, label, group: 'Gestures', keys: [`${fingers}-finger swipe ${direction}`], keywords: 'touchpad gesture swipe'});
    return result;
}

// ── Notes ──

// files: [{path (relative), size}] from `find`. Mirrors the indexing limits.
function selectNoteFiles(files) {
    const accepted = [];
    let skipped = 0, used = 0;
    for (const f of files.slice().sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0)) {
        const lower = f.path.toLowerCase();
        if (!NOTE_EXTENSIONS.some(ext => lower.endsWith(ext)) || f.path.split('/').some(p => p.startsWith('.')))
            continue;
        if (f.size > NOTE_LIMITS.fileBytes || used + f.size > NOTE_LIMITS.totalBytes || accepted.length >= NOTE_LIMITS.files) {
            skipped++;
            continue;
        }
        used += f.size;
        accepted.push(f);
    }
    return {accepted, skipped};
}

function splitLines(text) {
    const lines = String(text).split(/\r\n|\r|\n/);
    if (lines.length && lines[lines.length - 1] === '')
        lines.pop();
    return lines;
}

// ── Panel model ──
// handle(request) returns what the UI renders: {kind: 'state' | 'execute' | 'run' | 'quit'}.
// 'execute' asks the UI to hide first; the follow-up {op: 'execute'} returns a 'run' plan
// whose side effects shell.qml performs. Errors are thrown; the UI shows their message.

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

class Model {
    // env: {entries, active, clients, recent, start, notes?: {files: [{path, text}], skipped}}
    constructor(env) {
        this.entries = env.entries.filter(e => e.id !== 'palette').map(e => Object.assign({}, e));
        this.lookup = {};
        for (const e of this.entries) this.lookup[e.id] = e;
        this.active = env.active || {};
        this.clients = env.clients || [];
        this.recent = (env.recent || []).filter(x => typeof x === 'string').slice(0, 5);
        this.notes = null;
        this.noteWarning = '';
        if (env.notes) this.setNotes(env.notes.files, env.notes.skipped);
        this.stack = [];
        this.state = {view: 'commands', query: '', category: 'All', selected: '', scroll: 0};
        this.pending = null;
        this.lastRows = [];
        this.message = '';
        if (env.start === 'notes') this.push('notes');
    }

    // True while the notes view is waiting for shell.qml to read the notes folder.
    get needsNotes() { return this.state.view === 'notes' && this.notes === null; }

    setNotes(files, skipped) {
        this.notes = files.map(f => ({path: f.path, name: f.path, lines: splitLines(f.text)}));
        this.noteWarning = skipped ? `${skipped} files omitted because of size, access, or indexing limits.` : '';
    }

    push(view, extra) {
        this.stack.push(clone(this.state));
        this.state = Object.assign({view, query: '', category: 'All', selected: '', scroll: 0}, extra || {});
    }

    family(e) {
        for (const prefix in FAMILIES)
            if (new RegExp('^' + prefix + '\\d+$').test(e.id)) return prefix;
        return null;
    }

    unavailable(e) {
        if (e.id === 'previous' && !this.clients.some(c => c.mapped && !c.hidden && c.address !== this.active.address && (c.focusHistoryID === undefined ? -1 : c.focusHistoryID) >= 0))
            return 'No previous window is available.';
        if ((e.group === 'Windows' || e.id.startsWith('kbMoveWin')) && !this.active.address)
            return 'Focus a window first.';
        return '';
    }

    row(e, section) {
        const reference = !(e.lua || e.workflow);
        const kind = e.kind || (reference ? 'guide' : e.confirm ? 'confirm' : 'action');
        const why = this.unavailable(e);
        const keys = e.keys || [];
        return {
            id: e.id, title: e.label, titleHtml: marked(e.label, this.state.query),
            subtitle: why || (kind === 'guide' ? 'Shortcut instructions' : SUMMARIES[e.id] || e.group || ''),
            key: keys.length ? displayKeys(keys.slice(0, 1)) : '', section: section || '', group: e.group || '',
            kind, disabled: !!why, reason: why, detail: DETAILS[e.id] || '',
            badge: kind === 'guide' ? 'Guide' : kind === 'confirm' ? 'Confirm' : kind === 'family' || kind === 'browse' ? 'Choose' : '',
        };
    }

    commandRows() {
        const q = this.state.query, category = this.state.category;
        let base = this.entries;
        if (this.state.view === 'family') {
            base = base.filter(e => this.family(e) === this.state.family);
        } else if (!/\d/.test(q)) {
            base = base.filter(e => !this.family(e));
            for (const prefix in FAMILIES)
                if (this.entries.some(e => this.family(e) === prefix))
                    base.push({id: 'family:' + prefix, label: FAMILIES[prefix] + '…', group: 'Workspaces', kind: 'family', keys: [], keywords: 'number desktop destination'});
        }
        if (category === 'Guides')
            base = base.filter(e => !(e.lua || e.workflow || e.kind === 'family'));
        else if (category !== 'All' && category !== 'Browse all')
            base = base.filter(e => e.group === category);
        if (!q.trim() && category === 'All' && this.state.view === 'commands') {
            const rows = COMMON.filter(i => this.lookup[i]).map(i => this.row(this.lookup[i], 'Common'));
            for (const i of this.recent)
                if (this.lookup[i] && !COMMON.includes(i) && !this.lookup[i].confirm)
                    rows.push(this.row(this.lookup[i], 'Recent'));
            rows.push({id: 'browse', title: 'Browse all commands and shortcuts', titleHtml: 'Browse all commands and shortcuts', subtitle: 'Explore by category', key: '', section: 'Explore', kind: 'browse', disabled: false, badge: 'Browse'});
            return rows;
        }
        const recency = e => q && this.recent.includes(e.id) ? this.recent.indexOf(e.id) : 99;
        // V4's sort is not stable, so ties fall back to catalog order explicitly.
        return base.map((e, i) => [rank(q, e), e, i]).filter(([score]) => score !== null)
            .sort((a, b) => a[0] - b[0] || recency(a[1]) - recency(b[1]) || compareText(a[1].label, b[1].label) || a[2] - b[2])
            .map(([, e]) => this.row(e, q ? 'Results' : e.group || 'Commands'));
    }

    noteRows() {
        if (this.notes === null)
            return [];
        const q = this.state.query;
        const terms = normalized(q).split(' ').filter(Boolean);
        const results = [];
        this.notes.forEach((note, i) => {
            const nameMatch = terms.every(t => normalized(note.name).includes(t));
            const hits = [];
            if (terms.length)
                note.lines.forEach((line, j) => { if (terms.every(t => normalized(line).includes(t))) hits.push(j); });
            if (terms.length && !nameMatch && !hits.length)
                return;
            const line = hits.length ? hits[0] : 0;
            const excerpt = note.lines.slice(Math.max(0, line - 1), line + 3).join('\n').slice(0, 1800);
            results.push({
                id: `note:${i}:${line + 1}`, title: note.name, titleHtml: marked(note.name, q),
                subtitle: terms.length ? `${hits.length} matching lines · line ${line + 1}` : 'Read-only reference',
                key: '', section: 'Notes', kind: 'note', disabled: false, badge: 'Open',
                preview: marked(excerpt || 'Empty note', q).replace(/\n/g, '<br>'), previewPlain: excerpt,
                hits: hits.slice(0, 100).map(j => j + 1), detail: `Enter opens line ${line + 1} read-only; Ctrl+E edits it.`,
            });
        });
        const nq = normalized(q);
        const inTitle = r => normalized(r.title).includes(nq) ? 0 : 1;
        const order = new Map(results.map((r, i) => [r, i]));
        return results.sort((a, b) => inTitle(a) - inTitle(b) || compareText(a.title, b.title) || order.get(a) - order.get(b));
    }

    detail(ident) {
        const e = this.lookup[ident];
        if (!e)
            return {};
        const why = this.unavailable(e);
        const reference = !(e.lua || e.workflow);
        const target = this.active.title || this.active.class || 'No focused window';
        let explanation = DETAILS[ident] || (reference ? 'Use the displayed input to perform this action.' : e.label + '.');
        if (ident.startsWith('unknown:'))
            explanation = 'This binding is active but its behavior has not been verified in the catalog. Use its original shortcut; the panel will not execute it.';
        return {
            id: ident, title: e.label, body: explanation, keys: (e.keys || []).map(k => displayKeys([k])),
            group: e.group || '', disabled: !!why, reason: why, reference,
            target: e.group === 'Windows' || ident.startsWith('kbMoveWin') ? target : '',
            confirmation: this.confirmation(e), button: e.label,
        };
    }

    confirmation(e) {
        if (e.id === 'kbCloseWindow')
            return 'Close ' + (this.active.title || this.active.class || 'the focused window') + '? Unsaved work will depend on the application’s own save prompt.';
        return CONFIRMATIONS[e.id] || e.label + '?';
    }

    snapshot() {
        const view = this.state.view;
        const rows = view === 'notes' ? this.noteRows() : view === 'details' || view === 'confirm' ? [] : this.commandRows();
        this.lastRows = rows;
        const notice = view !== 'notes' ? ''
            : this.notes === null ? 'Indexing notes…'
            : (this.noteWarning ? this.noteWarning + ' ' : '') + 'Typed notes in Documents/Notes · Rnote handwriting is not indexed.';
        return {
            kind: 'state', view,
            title: {commands: 'Commands', notes: 'Search notes', details: 'Shortcut details', confirm: 'Confirm action', family: 'Choose workspace'}[view],
            query: this.state.query, category: this.state.category, rows,
            detail: view === 'details' || view === 'confirm' ? this.detail(this.state.entry || '') : {},
            selected: this.state.selected || '', scroll: this.state.scroll || 0,
            back: this.stack.length > 0, message: this.message, notice,
        };
    }

    handle(request) {
        const op = request.op;
        this.message = '';
        if (op === 'query') {
            Object.assign(this.state, {query: String(request.query === undefined ? '' : request.query).slice(0, 500), category: request.category || 'All', selected: '', scroll: 0});
            if (request.enter) {
                const snap = this.snapshot();
                if (snap.rows.length)
                    return this.handle({op: 'activate', id: snap.rows[0].id});
            }
        } else if (op === 'back') {
            if (!this.stack.length)
                return {kind: 'quit'};
            this.state = this.stack.pop();
        } else if (op === 'refresh') {
            this.notes = null;
        } else if (op === 'details' || op === 'activate') {
            const ident = request.id || '';
            if (this.state.view === 'details' || this.state.view === 'confirm') {
                if (ident !== this.state.entry)
                    throw new Error('Action is no longer selected.');
            } else if (!this.lastRows.some(r => r.id === ident)) {
                throw new Error('That result is no longer visible. Search again.');
            }
            Object.assign(this.state, {selected: ident, scroll: request.scroll || 0});
            if (ident === 'browse') {
                this.state.category = 'Browse all';
            } else if (ident.startsWith('family:')) {
                this.push('family', {family: ident.split(':')[1]});
            } else if (ident === 'notes-search' && op === 'activate') {
                this.push('notes');
            } else if (ident.startsWith('note:')) {
                this.pending = ident;
                this.pendingEdit = request.edit === true;
                return {kind: 'execute', id: ident};
            } else {
                const e = this.lookup[ident];
                const why = this.unavailable(e);
                if (why && op === 'activate')
                    this.message = why;
                else if (op === 'details' || !(e.workflow || e.lua))
                    this.push('details', {entry: ident});
                else if (e.confirm && this.state.view !== 'confirm')
                    this.push('confirm', {entry: ident});
                else if (e.confirm && request.confirmed !== true)
                    this.message = 'Choose Cancel or confirm this action explicitly.';
                else {
                    this.pending = ident;
                    return {kind: 'execute', id: ident};
                }
            }
        } else if (op === 'execute') {
            const ident = request.id;
            if (!this.pending || ident !== this.pending)
                throw new Error('No action is pending.');
            this.pending = null;
            return {kind: 'run', plan: this.plan(ident)};
        }
        return this.snapshot();
    }

    // What shell.qml must do for a confirmed, pending action.
    plan(ident) {
        if (ident.startsWith('note:')) {
            const [, index, line] = ident.split(':');
            return {type: 'note', path: this.notes[Number(index)].path, line: Number(line), edit: !!this.pendingEdit};
        }
        const e = this.lookup[ident];
        const focus = (e.group === 'Windows' || e.group === 'Workspaces') && this.active.address ? this.active.address : null;
        const recent = e.confirm ? null : [ident].concat(this.recent.filter(i => i !== ident).slice(0, 4));
        if (e.workflow)
            return {type: 'workflow', name: e.workflow, focus, recent};
        return {type: 'lua', code: LUA_PRELUDE + e.lua, focus, recent};
    }
}

// ── Theme: Caelestia's wallpaper scheme held to WCAG contrast ──

const DEFAULT_SCHEME = {
    surfaceContainerLow: '101216', onSurface: 'f1f3f5', onSurfaceVariant: 'aeb8ca', primary: '89b4fa', onPrimary: '101216', outline: '8996ad',
    surface: '101216', surfaceContainer: '181a1f', surfaceContainerHigh: '22252b', surfaceContainerHighest: '2c2f36', outlineVariant: '44474f',
    primaryContainer: '284777', onPrimaryContainer: 'd6e3ff', secondaryContainer: '3e4759', onSecondaryContainer: 'dae2f9',
    tertiaryContainer: '573e5c', onTertiaryContainer: 'fbd7fc', errorContainer: '93000a', onErrorContainer: 'ffdad6', error: 'ffb4ab', onError: '690005',
    shadow: '000000',
};

function luminance(color) {
    return [0, 2, 4].map(i => parseInt(color.slice(i, i + 2), 16) / 255)
        .map(x => x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4))
        .reduce((sum, x, i) => sum + x * [0.2126, 0.7152, 0.0722][i], 0);
}

function contrast(a, b) {
    const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
    return (light + 0.05) / (dark + 0.05);
}

function readable(preferred, background, fallback, minimum) {
    minimum = minimum === undefined ? 4.5 : minimum;
    for (const color of [preferred, fallback])
        if (contrast(color, background) >= minimum) return color;
    return contrast('000000', background) >= contrast('ffffff', background) ? '000000' : 'ffffff';
}

// Text of ~/.local/state/caelestia/scheme.json → scheme roles (defaults fill gaps).
// Returns null when the file is mid-write or malformed, so the caller keeps its colours.
function parseScheme(text) {
    let raw;
    try { raw = JSON.parse(text).colours; } catch (e) { return null; }
    if (!raw || typeof raw !== 'object' || Array.isArray(raw))
        return null;
    const scheme = Object.assign({}, DEFAULT_SCHEME);
    for (const k in raw)
        if (typeof raw[k] === 'string' && /^[0-9a-fA-F]{6}$/.test(raw[k])) scheme[k] = raw[k].toLowerCase();
    return scheme;
}

// Every 'on' colour ≥4.5:1 on its own container; indicator colours ≥3:1 on the panel.
function themeColors(scheme) {
    const s = Object.assign({}, DEFAULT_SCHEME, scheme || {});
    const surface = s.surface;
    const body = readable(s.onSurface, surface, 'ffffff');
    const roles = {};
    for (const k of ['surface', 'surfaceContainer', 'surfaceContainerHigh', 'surfaceContainerHighest', 'outlineVariant', 'shadow'])
        roles[k] = s[k];
    roles.onSurface = body;
    roles.onSurfaceVariant = readable(s.onSurfaceVariant, s.surfaceContainerHigh, body);
    roles.primary = readable(s.primary, surface, readable(s.onSurface, s.surfaceContainerLow, 'ffffff'), 3);
    roles.error = readable(s.error, surface, readable(s.onSurface, s.surfaceContainerLow, 'ffffff'), 3);
    roles.onPrimary = readable(s.onPrimary, roles.primary, body);
    roles.onError = readable(s.onError, roles.error, body);
    for (const name of ['primary', 'secondary', 'tertiary', 'error']) {
        const container = s[name + 'Container'];
        const cap = name[0].toUpperCase() + name.slice(1);
        roles[name + 'Container'] = container;
        roles['on' + cap + 'Container'] = readable(s['on' + cap + 'Container'], container, body);
    }
    return roles;
}
