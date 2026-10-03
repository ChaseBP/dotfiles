// Tests for Engine.js (the logic behind the Super+K palette). Run: node --test test_palette.mjs
// Engine.js is a QML `.pragma library` script, so it is evaluated here as plain JS.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';
import {execFileSync} from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, 'Engine.js'), 'utf8').replace(/^\.pragma library\n/, '');
const E = new Function(source + '\nreturn {Model, normalized, rank, marked, buildCatalog, selectNoteFiles, parseScheme, themeColors, contrast, displayKeys, describedBind};')();

const entry = (id, label, extra = {}) => Object.assign({id, label, group: 'Windows', keys: ['SUPER + X'], lua: 'hl.dsp.no_op()'}, extra);
const model = (entries, extra = {}) => new E.Model(Object.assign({entries, active: {address: '0x1', title: 'Test window'}, clients: [{address: '0x1', mapped: true, focusHistoryID: 0}]}, extra));
const notesOf = files => {
    const {accepted, skipped} = E.selectNoteFiles(files);
    return {files: accepted.map(f => ({path: f.path, text: files.find(x => x.path === f.path).text})), skipped};
};

test('disabled stock actions are hidden, live binds catalogued', () => {
    const vars = JSON.parse(execFileSync('lua', [join(here, '..', 'scripts', 'palette-vars.lua')], {encoding: 'utf8'}));
    const actions = JSON.parse(readFileSync(join(here, '..', 'actions.json'), 'utf8'));
    const rows = E.buildCatalog(vars, [], actions);
    assert.ok(!rows.some(r => r.id === 'kbTodoWs' || r.id === 'kbMusicWs'));
    assert.ok(rows.some(r => r.id === 'notes-search'));
});

test('bind descriptions label uncatalogued binds', () => {
    const rows = E.buildCatalog({}, [
        {modmask: 72, key: 'F10', description: 'Utilities: Toggle focus timer'},
        {modmask: 72, key: 'F9', description: ''},
    ], []);
    const f10 = rows.find(r => r.id === 'unknown:SUPER + ALT + F10');
    assert.deepEqual([f10.group, f10.label], ['Utilities', 'Toggle focus timer']);
    assert.equal(rows.find(r => r.id === 'unknown:SUPER + ALT + F9').label, 'Uncatalogued shortcut — use its key combination');
    assert.deepEqual(E.describedBind('Toggle focus timer'), {group: 'Other', label: 'Toggle focus timer'});
});

test('malformed inputs build an empty-but-valid catalog', () => {
    for (const [vars, binds, actions] of [[null, null, null], [[], {}, {}], [{}, [null, 'x', {}], [{}, {id: 1}, null]]]) {
        const rows = E.buildCatalog(vars, binds, actions);
        assert.ok(Array.isArray(rows));
        assert.ok(rows.every(r => typeof r.id === 'string' && typeof r.label === 'string'));
    }
});

test('search prefers title over synonyms', () => {
    const title = entry('one', 'Open notes');
    const synonym = entry('two', 'Another command', {keywords: 'open notes'});
    assert.ok(E.rank('open notes', title) < E.rank('open notes', synonym));
    assert.equal(E.rank('SUPER+X', title), 0);
    assert.equal(E.rank('nonexistent', title), null);
});

test('workspace families expand only when needed', () => {
    const m = model(Array.from({length: 10}, (_, i) => entry('kbGoToWs' + (i + 1), 'Go to workspace ' + (i + 1))));
    let r = m.handle({op: 'query', query: '', category: 'Browse all'});
    assert.equal(r.rows.length, 1);
    assert.equal(r.rows[0].kind, 'family');
    r = m.handle({op: 'activate', id: r.rows[0].id});
    assert.equal(r.rows.length, 10);
    assert.equal(m.handle({op: 'back'}).view, 'commands');
    assert.equal(m.handle({op: 'query', query: 'workspace 3', category: 'All'}).rows[0].id, 'kbGoToWs3');
});

test('details preserve query, selection and scroll', () => {
    const m = model([entry('one', 'Open notes')]);
    m.handle({op: 'query', query: 'notes', category: 'All'});
    m.handle({op: 'details', id: 'one', scroll: 88});
    const r = m.handle({op: 'back'});
    assert.deepEqual([r.query, r.selected, r.scroll], ['notes', 'one', 88]);
});

test('close requires explicit confirmation and cancel is safe', () => {
    const m = model([entry('kbCloseWindow', 'Close focused window', {confirm: true})]);
    m.handle({op: 'query', query: 'close', category: 'All'});
    let r = m.handle({op: 'activate', id: 'kbCloseWindow'});
    assert.equal(r.view, 'confirm');
    assert.match(r.detail.confirmation, /Test window/);
    r = m.handle({op: 'activate', id: 'kbCloseWindow'});
    assert.equal(r.view, 'confirm');
    assert.equal(m.pending, null);
    assert.equal(m.handle({op: 'back'}).query, 'close');
});

test('confirmed action waits for the panel to hide, then plans', () => {
    const m = model([entry('kbCloseWindow', 'Close focused window', {confirm: true})]);
    m.handle({op: 'query', query: 'close', category: 'All'});
    m.handle({op: 'activate', id: 'kbCloseWindow'});
    const r = m.handle({op: 'activate', id: 'kbCloseWindow', confirmed: true});
    assert.equal(r.kind, 'execute');
    const run = m.handle({op: 'execute', id: 'kbCloseWindow'});
    assert.equal(run.kind, 'run');
    assert.deepEqual(run.plan, {type: 'lua', code: 'local v=require("variables");local fn=require("utils.functions");hl.dsp.no_op()', focus: '0x1', recent: null});
    assert.throws(() => m.handle({op: 'execute', id: 'kbCloseWindow'}), /No action is pending/);
});

test('safe actions update recents; workflows plan their own launch', () => {
    const m = model([entry('one', 'Open notes', {group: 'Your workflows', lua: undefined, workflow: 'notes'})], {recent: ['a', 'one', 'b', 'c', 'd']});
    m.handle({op: 'query', query: 'notes', category: 'All'});
    m.handle({op: 'activate', id: 'one'});
    assert.deepEqual(m.handle({op: 'execute', id: 'one'}).plan, {type: 'workflow', name: 'notes', focus: null, recent: ['one', 'a', 'b', 'c', 'd']});
});

test('unavailable previous window', () => {
    const m = model([entry('previous', 'Focus previous window')]);
    assert.ok(m.handle({op: 'query', query: 'previous', category: 'All'}).rows[0].disabled);
    const r = m.handle({op: 'activate', id: 'previous'});
    assert.equal(r.kind, 'state');
    assert.equal(m.pending, null);
});

test('unverified binding cannot execute', () => {
    const m = model([{id: 'unknown:Q', label: 'Unknown', group: 'Other', keys: ['SUPER+Q']}]);
    m.handle({op: 'query', query: 'unknown', category: 'All'});
    assert.ok(m.handle({op: 'activate', id: 'unknown:Q'}).detail.reference);
    assert.throws(() => m.handle({op: 'execute', id: 'unknown:Q'}));
});

test('notes group matches and escape markup', () => {
    const notes = notesOf([
        {path: 'Inbox.md', size: 60, text: 'Docker <img src="file:///etc/passwd">\nDocker commands\nOther context'},
        {path: '.hidden.md', size: 6, text: 'Docker'},
    ]);
    const m = model([], {start: 'notes', notes});
    const r = m.handle({op: 'query', query: 'docker', category: 'All'});
    assert.equal(r.rows.length, 1);
    assert.deepEqual(r.rows[0].hits, [1, 2]);
    assert.match(r.rows[0].preview, /&lt;img/);
    assert.doesNotMatch(r.rows[0].preview, /<img/);
});

test('notes open read-only by default and for editing on request', () => {
    const notes = notesOf([{path: 'Ideas.md', size: 20, text: '# Ideas\nrocket'}]);
    const m = model([], {start: 'notes', notes});
    const row = m.handle({op: 'query', query: 'rocket', category: 'All'}).rows[0];
    assert.equal(m.handle({op: 'activate', id: row.id}).kind, 'execute');
    assert.deepEqual(m.handle({op: 'execute', id: row.id}).plan, {type: 'note', path: 'Ideas.md', line: 2, edit: false});
    m.handle({op: 'query', query: 'rocket', category: 'All'});
    m.handle({op: 'activate', id: row.id, edit: true});
    assert.deepEqual(m.handle({op: 'execute', id: row.id}).plan, {type: 'note', path: 'Ideas.md', line: 2, edit: true});
});

test('oversized notes are disclosed; notes view waits for indexing', () => {
    const m = model([], {start: 'notes', notes: notesOf([{path: 'large.md', size: 2000001, text: 'x'}])});
    assert.match(m.snapshot().notice, /1 files omitted/);
    const waiting = model([], {start: 'notes'});
    assert.ok(waiting.needsNotes);
    assert.equal(waiting.snapshot().notice, 'Indexing notes…');
});

test('theme keeps text readable', () => {
    const t = E.themeColors(E.parseScheme(JSON.stringify({colours: {surface: 'ffffff', onSurface: 'fefefe', primary: 'ffff00'}})));
    assert.ok(E.contrast(t.onSurface, t.surface) >= 4.5);
    assert.ok(E.contrast(t.primary, t.surface) >= 3);
    assert.equal(E.parseScheme('{"colours": '), null);
});

test('Engine.js avoids JavaScript Qt V4 lacks', () => {
    // V4 has no flat/flatMap/replaceAll, rejects object spread, and /\p{…}/u silently fails.
    for (const [pattern, why] of [[/\.flatMap\(|\.flat\(/, 'flat/flatMap'], [/\.replaceAll\(/, 'replaceAll'],
                                  [/\\p\{/, 'Unicode property escapes'], [/\{\s*\.\.\./, 'object spread'], [/\(\?<[=!]/, 'lookbehind']])
        assert.doesNotMatch(source, pattern, why);
    assert.equal(E.normalized ? E.normalized('Héllo wörld_1 — ß→x') : 'héllo wörld_1 ß x', 'héllo wörld_1 ß x');
});
