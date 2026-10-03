pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Caelestia.Config
import "Engine.js" as Engine

// Styled with Caelestia's own design tokens (rounding, padding, fonts, motion) and the
// wallpaper's M3 roles (Engine.themeColors), so it reads as part of the shell.
// Engine.js holds the model; this file renders it and does all I/O natively.
ShellRoot {
    id: root
    property var page: ({view: "commands", title: "Commands", rows: [], query: "", category: "All"})
    property var colors: ({
        surface: "121316", surfaceContainer: "1e1f23", surfaceContainerHigh: "282a2e", surfaceContainerHighest: "33353a",
        onSurface: "e3e2e6", onSurfaceVariant: "c4c6d0", outlineVariant: "44474f", shadow: "000000",
        primary: "aac7ff", onPrimary: "0a305f", primaryContainer: "284777", onPrimaryContainer: "d6e3ff",
        secondaryContainer: "3e4759", onSecondaryContainer: "dae2f9", tertiaryContainer: "573e5c", onTertiaryContainer: "fbd7fc",
        error: "ffb4ab", onError: "690005", errorContainer: "93000a", onErrorContainer: "ffdad6"
    })
    property string error: ""
    property string pendingId: ""
    property var engine: null
    property bool indexing: false
    readonly property string home: Quickshell.env("HOME")
    readonly property string base: home + "/.config/caelestia"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/caelestia"
    readonly property string notesRoot: home + "/Documents/Notes"
    property bool ready: false
    property bool closing: false
    // Resident: the instance stays loaded and hides between uses (caelestia-palette).
    property bool open: false          // panel requested on screen
    property bool actionHidden: false  // off screen while a chosen action runs
    property bool fresh: false         // binds/windows re-read since this opening
    property var cache: null           // last data read: {vars, binds, clients, active, actions}
    property var deferredRequest: null // Enter/Details pressed before the refresh landed
    property string startView: "commands"
    property int session: 0            // bumped per opening; late callbacks from older ones are ignored
    property bool touchMode: false
    readonly property bool compact: panel.width < 620
    // One knob for text density: Caelestia's M3 type roles, scaled down for a dense list.
    readonly property real textScale: 0.86
    // Text font override; "" falls back to Caelestia's own type roles (icons are unaffected).
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    property var categories: ["All", "Your workflows", "Windows", "Workspaces", "Apps", "Capture", "Clipboard", "Media", "Desktop", "System", "Guides"]
    readonly property var groupIcons: ({
        "All": "apps", "Your workflows": "bolt", "Windows": "select_window", "Workspaces": "grid_view",
        "Apps": "widgets", "Capture": "screenshot_region", "Clipboard": "content_paste", "Media": "music_note",
        "Desktop": "desktop_windows", "System": "settings_power", "Guides": "menu_book"
    })
    readonly property var idIcons: ({
        "notes": "edit_note", "notes-choose": "stylus_note", "windows": "search", "ocr": "document_scanner",
        "notes-search": "manage_search", "projects": "terminal", "kbClipboard": "content_paste",
        "kbSpecialWs": "layers", "browse": "explore", "notes-new": "note_add"
    })

    function f(tok) { return Qt.font({family: fontFamily || tok.family, pointSize: tok.pointSize * textScale, weight: tok.weight}); }
    function c(role) { return "#" + (colors[role] || colors.onSurface || colors.text); }
    function iconFor(e) {
        if (!e) return "keyboard";
        if (idIcons[e.id]) return idIcons[e.id];
        if (e.kind === "note") return "description";
        if (e.kind === "family") return "view_module";
        if (e.kind === "guide") return "menu_book";
        return groupIcons[e.group] || "keyboard_command_key";
    }
    // Engine.marked() marks matches as <b><u>…</u></b>; recolour them instead of underlining.
    function marks(html, color) {
        return (html || "").replace(/<b><u>/g, `<font color="${color}"><b>`).replace(/<\/u><\/b>/g, "</b></font>");
    }
    function keyParts(key) {
        const out = [];
        for (const part of (key || "").split("+")) {
            if (part.trim()) out.push(part.trim());
            else if (out[out.length - 1] !== "+") out.push("+");
        }
        return out;
    }
    function keyLabel(k) { return ({Left: "←", Right: "→", Up: "↑", Down: "↓", Return: "Enter", mouse_down: "Scroll ↓", mouse_up: "Scroll ↑"})[k] || k; }
    function send(value) {
        if (!engine) return;
        // Acting needs this opening's active window and binds; hold it until they land.
        if (!fresh && (value.op === "activate" || value.op === "details" || value.enter)) {
            deferredRequest = value;
            return;
        }
        if (!fresh) deferredRequest = null;  // typing, Back or a new category changes the intent
        let message;
        try { message = engine.handle(value); }
        catch (e) { message = {kind: "error", message: String(e.message || e).slice(0, 350)}; }
        apply(message);
    }
    function chosen() { return page.rows && list.currentIndex >= 0 ? page.rows[list.currentIndex] : null; }
    function close() {
        if (closing || !open) return;
        closing = true;
        queryTimer.stop();
        if (!actionHidden) cancelPending();  // Escape withdraws anything not yet started
        closeTimer.start();
    }
    function cancelPending() {
        deferredRequest = null;
        executeTimer.stop();
        deferred.stop();
    }
    function hide() {
        open = false;
        closing = false;
        actionHidden = false;
        deferredRequest = null;
        error = "";
    }
    // Shows at once from the last-known catalog, then refreshes in the background.
    function show(view) {
        closeTimer.stop();
        cancelPending();
        session++;
        closing = false;
        startView = view || "commands";
        error = "";
        actionHidden = false;
        fresh = false;
        if (cache) {
            try { build(cache, false); }
            catch (e) { cache = null; }  // never let a bad cache block opening
        }
        open = true;
        refresh();
    }
    function toggle(view) {
        if (open && !closing) close();
        else show(view);
    }
    function selectStep(delta) {
        if (!page.rows || !page.rows.length) return;
        list.currentIndex = Math.max(0, Math.min(page.rows.length - 1, list.currentIndex + delta));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }
    function activate(details, edit) {
        const entry = chosen();
        if (!entry) return;
        send({op: details ? "details" : "activate", id: entry.id, scroll: list.contentY, edit: !!edit});
    }
    // Launch a workflow straight from a button (e.g. New note) once the panel is hidden.
    function launchWorkflow(name) {
        actionHidden = true;
        deferred.plan = {type: "workflow", name, focus: null, recent: null};
        deferred.start();
    }
    function back() {
        queryTimer.stop();
        if (page.back) send({op: "back"});
        else close();
    }
    // background: a refresh or notes index finishing — keep keyboard focus where it is.
    function apply(message, background) {
        if (message.kind === "quit") { close(); return; }
        if (message.kind === "run") { perform(message.plan); return; }
        if (message.kind === "execute") {
            pendingId = message.id;
            actionHidden = true;
            executeTimer.start();
            return;
        }
        if (message.kind === "error") {
            error = message.message;
            actionHidden = false;
            search.forceActiveFocus();
            return;
        }
        if (message.kind !== "state") return;
        page = message;
        error = message.message || "";
        ready = true;
        search.text = message.query || "";
        Qt.callLater(() => {
            if (page !== message) return;  // a newer state replaced this one meanwhile
            let selected = (message.rows || []).findIndex(e => e.id === message.selected);
            list.currentIndex = selected >= 0 ? selected : (message.rows.length ? 0 : -1);
            if (message.scroll) list.contentY = message.scroll;
            if (background && win.activeFocusItem && win.activeFocusItem !== search) return;
            if (page.view === "confirm") cancelButton.forceActiveFocus();
            else if (page.view === "details") backButton.forceActiveFocus();
            else search.forceActiveFocus();
        });
        if (engine && engine.needsNotes) loadNotes();
    }

    // ── Native I/O ──

    // Run a command; callback(exitCode, stdout, stderr). A binary that fails to
    // start never emits exited, so a stopped process without one reports 127.
    component Job: Process {
        id: job
        property var callback
        property int code: -1
        property bool done: false
        property bool collected: false
        stdout: StdioCollector { id: jobOut; onStreamFinished: { job.collected = true; job.finish(); } }
        stderr: StdioCollector { id: jobErr }
        onExited: exitCode => { job.code = exitCode; job.done = true; job.finish(); }
        onRunningChanged: if (!running) Qt.callLater(() => { if (job && !job.done) { job.code = 127; job.done = true; job.collected = true; job.finish(); } })
        function finish() {
            if (!done || !collected || !callback) return;
            const cb = callback;
            callback = null;
            cb(code, jobOut.text, jobErr.text);
            destroy();
        }
    }
    Component { id: jobComponent; Job {} }
    function run(command, callback) {
        jobComponent.createObject(root, {command, callback}).running = true;
    }
    function parse(text, fallback) {
        try { return JSON.parse(text); } catch (e) { return fallback; }
    }
    // Synchronous read; null when missing or unreadable. A fresh FileView per read:
    // re-pointing one at a new path keeps returning the previous file's text.
    function readFile(path) {
        const view = readerComponent.createObject(null, {path});
        const text = view.text();
        const ok = view.loaded;
        view.destroy();
        return ok ? text : null;
    }

    // Everything the catalog needs, read in parallel. Variables fall back to the last
    // good read; windows and binds are always current.
    function fetch(callback) {
        const data = {};
        let waiting = 4;
        const done = () => {
            if (--waiting) return;
            data.vars = data.vars || (cache ? cache.vars : null);
            data.actions = parse(readFile(base + "/actions.json") || "[]", []);
            callback(data);
        };
        run(["lua", base + "/scripts/palette-vars.lua"], (code, out) => { data.vars = code === 0 ? parse(out, null) : null; done(); });
        run(["hyprctl", "-j", "binds"], (code, out) => { data.binds = parse(out, []); done(); });
        run(["hyprctl", "-j", "clients"], (code, out) => { data.clients = parse(out, []); done(); });
        run(["hyprctl", "-j", "activewindow"], (code, out) => { data.active = parse(out, {}); done(); });
    }

    // A model from data. keepState carries this opening's view, query, selection and
    // scroll (and any indexed notes) across a background refresh.
    function build(data, keepState) {
        const recent = parse(readFile(stateDir + "/palette-recent.json") || "[]", []);
        const next = new Engine.Model({
            entries: Engine.buildCatalog(data.vars, data.binds || [], data.actions || []),
            active: data.active || {}, clients: data.clients || [],
            recent: Array.isArray(recent) ? recent : [],
            start: keepState ? "commands" : startView,
        });
        if (keepState && engine) {
            if (queryTimer.running) {  // fold in keystrokes still waiting on the debounce
                queryTimer.stop();
                engine.handle({op: "query", query: search.text, category: page.category || "All"});
            }
            next.state = engine.state;
            next.stack = engine.stack;
            next.state.selected = chosen() ? chosen().id : next.state.selected;
            next.state.scroll = list.contentY;
            next.notes = engine.notes;
            next.noteWarning = engine.noteWarning;
            next.pending = engine.pending;
            next.pendingEdit = engine.pendingEdit;
        }
        engine = next;
        apply(engine.handle({op: "init"}), keepState);
    }

    function refresh() {
        const opening = session;
        refreshDeadline.restart();
        fetch(data => {
            if (opening !== session) return;  // an older opening's data: never apply it
            refreshDeadline.stop();
            if (!data.vars) {
                apply({kind: "error", message: "Could not read Hyprland variables (palette-vars.lua)."});
                return;
            }
            try {
                build(data, !!engine && ready);
                cache = data;  // only data that built cleanly is reused next time
                fresh = true;
                if (deferredRequest) {
                    const request = deferredRequest;
                    deferredRequest = null;
                    send(request);
                }
            } catch (e) {
                apply({kind: "error", message: String(e.message || e)});
            }
        });
    }

    // Notes are indexed only when the notes view first needs them (and on Refresh).
    // find -type f skips symlinks; hidden files and folders are pruned.
    function loadNotes() {
        if (indexing) return;
        indexing = true;
        const target = engine;
        run(["find", notesRoot, "-mindepth", "1", "-name", ".*", "-prune", "-o", "-type", "f", "-printf", "%s\t%P\n"], (code, out) => {
            const files = out.split("\n").filter(Boolean).map(line => {
                const tab = line.indexOf("\t");
                return {size: Number(line.slice(0, tab)), path: line.slice(tab + 1)};
            });
            const selection = Engine.selectNoteFiles(files);
            const notes = [];
            let skipped = selection.skipped;
            for (const f of selection.accepted) {
                const text = readFile(notesRoot + "/" + f.path);
                if (text === null) skipped++;
                else notes.push({path: f.path, text});
            }
            indexing = false;
            if (engine !== target) {  // the model was rebuilt meanwhile; index for the new one
                if (engine && engine.needsNotes) loadNotes();
                return;
            }
            engine.setNotes(notes, skipped);
            if (page.view === "notes") apply(engine.snapshot(), true);
        });
    }

    // Side effects of a confirmed action. Failures re-show the panel with the reason.
    // Window actions run as one Lua chunk: confirm the window still exists, focus it,
    // confirm focus really landed (dispatch is synchronous), then act — no gap in which
    // another window could become the target.
    function guarded(code, address) {
        const target = JSON.stringify(address);
        return "local target = " + target + "; local found = false; "
            + "for _, w in ipairs(hl.get_windows()) do if w.address == target then found = true end end; "
            + 'if not found then error("PALETTE: The original window closed. No action was taken.") end; '
            + 'hl.dispatch(hl.dsp.focus({window = "address:" .. target})); '
            + "local now = hl.get_active_window(); "
            + 'if not now or now.address ~= target then error("PALETTE: Could not focus the original window. No action was taken.") end; '
            + code;
    }
    // Hyprland's error text, minus the chunk preamble, for our own guard messages.
    function luaError(out, err) {
        const text = (out.trim() || err.trim());
        const own = /PALETTE: (.*)$/m.exec(text);
        return own ? own[1] : text || "The action failed.";
    }
    function toast(message) {
        Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "toaster", "error", "Command palette", message, "error"]);
    }

    function perform(plan) {
        const opening = session;
        // Results belong to the opening that started the action: a newer opening is
        // never closed by it, and a late failure becomes a toast instead.
        const fail = reason => {
            if (opening === session && open) apply({kind: "error", message: reason});
            else toast(reason);
        };
        const finish = () => { if (opening === session) close(); };
        const remember = () => { if (plan.recent) recentFile.setText(JSON.stringify(plan.recent)); };
        if (plan.type === "note" && plan.edit) {
            // workflows.py owns editable notes: autosave, reuse, notes workspace.
            Quickshell.execDetached(["python3", base + "/scripts/workflows.py", "notes-open", notesRoot + "/" + plan.path, String(plan.line)]);
            finish();
            return;
        }
        if (plan.type === "note") {
            const path = notesRoot + "/" + plan.path;
            run(["find", path, "-maxdepth", "0", "-type", "f"], (code, out) => {
                if (code !== 0 || !out.trim()) return fail("This note moved or is no longer available.");
                Quickshell.execDetached(["ghostty", "--class=local.caelestia.note-search", "--title=Note reference", "-e",
                                         home + "/.local/bin/nvim", "-R", "-n", "+" + plan.line, "--", path]);
                finish();
            });
            return;
        }
        const workflow = () => {
            Quickshell.execDetached(["python3", base + "/scripts/workflows.py", plan.name]);
            remember();
            finish();
        };
        if (plan.type === "workflow" && !plan.focus)
            return workflow();
        // Lua actions (and window-targeted workflows' focus step) go through Hyprland.
        const code = plan.type === "workflow" ? "" : plan.code;
        run(["hyprctl", "eval", plan.focus ? guarded(code, plan.focus) : code], (exitCode, out, err) => {
            if (out.trim() !== "ok") return fail(luaError(out, err));
            if (plan.type === "workflow") return workflow();
            remember();
            finish();
        });
    }

    // Always starts hidden, prefetching so the first Super+K is instant. A cold start
    // is shown by caelestia-palette over IPC once this instance answers — never by an
    // environment variable, which would reopen the palette on every config reload.
    Component.onCompleted: fetch(data => {
        if (cache || !data.vars) return;
        try {
            Engine.buildCatalog(data.vars, data.binds || [], data.actions || []);
            cache = data;
        } catch (e) {}
    })
    Component { id: readerComponent; FileView { blockLoading: true; printErrors: false } }
    FileView { id: recentFile; path: root.stateDir + "/palette-recent.json"; printErrors: false }
    // Live wallpaper colours: re-read whenever Caelestia rewrites the scheme. A partial
    // or malformed write parses to null and keeps the current colours.
    FileView {
        path: root.stateDir + "/scheme.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { const scheme = Engine.parseScheme(text()); if (scheme) root.colors = Engine.themeColors(scheme); }
    }
    Timer { id: executeTimer; interval: 120; onTriggered: root.send({op: "execute", id: root.pendingId}) }
    Timer { id: deferred; property var plan; interval: 120; onTriggered: root.perform(plan) }
    Timer { id: closeTimer; interval: Tokens.anim.durations.small + 20; onTriggered: root.hide() }
    // A hung hyprctl/lua must not hold Enter forever: give up on this refresh visibly.
    Timer {
        id: refreshDeadline
        interval: 3000
        onTriggered: if (root.open && !root.fresh) {
            root.deferredRequest = null;
            root.apply({kind: "error", message: "Couldn't re-read windows and shortcuts. Close and reopen to try again."});
        }
    }
    Timer { id: queryTimer; interval: 90; onTriggered: root.send({op: "query", query: search.text, category: root.page.category || "All"}) }
    IpcHandler {
        target: "palette"
        function close(): void { root.close(); }
        function toggle(view: string): void { root.toggle(view); }
        // Not "show": the qs CLI parses that as its own subcommand.
        function showView(view: string): void { root.show(view); }
        function state(): string { return JSON.stringify({open: root.open && !root.closing, fresh: root.fresh, view: root.page.view, query: search.text, selected: root.chosen()?.id || "", background: root.colors.surface, count: (root.page.rows || []).length, back: !!root.page.back, error: root.error}); }
    }

    // ── Building blocks (mirrors of Caelestia's StyledRect / StyledText / MaterialIcon / StateLayer) ──

    component Anim: NumberAnimation {
        duration: Tokens.anim.durations.normal
        easing: Tokens.anim.standard
    }
    component CAnim: ColorAnimation {
        duration: Tokens.anim.durations.expressiveSlowEffects
        easing: Tokens.anim.expressiveSlowEffects
    }
    component CRect: Rectangle {
        color: "transparent"
        Behavior on color { CAnim {} }
    }
    component SText: Text {
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
        color: root.c("onSurface")
        font: root.f(Tokens.font.body.medium)
        Behavior on color { CAnim {} }
    }
    component Icon: Text {
        property real fill: 0
        property int size: 20
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
        color: root.c("onSurfaceVariant")
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: Tokens.font.icon.small.family
        font.pixelSize: size
        font.variableAxes: ({FILL: fill, GRAD: 0, opsz: 24, wght: 400})
        Behavior on color { CAnim {} }
    }
    component StateLayer: MouseArea {
        id: layer
        property color tone: root.c("onSurface")
        property alias radius: tint.radius
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        CRect {
            id: tint
            anchors.fill: parent
            color: layer.tone
            opacity: layer.pressed ? 0.12 : layer.containsMouse ? 0.08 : 0
            Behavior on opacity { Anim { duration: Tokens.anim.durations.small } }
        }
    }
    component FocusRing: Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: root.c("primary")
    }
    component PillButton: Button {
        id: pill
        property string glyph: ""
        property string tone: "tonal" // filled | tonal | text | danger
        property bool small: false
        readonly property color fg: tone === "filled" ? root.c("onPrimary") : tone === "danger" ? root.c("onError")
                                  : tone === "tonal" ? root.c("onSecondaryContainer") : root.c("primary")
        implicitHeight: small ? 30 : 36
        leftPadding: glyph ? (small ? 12 : 16) : (small ? 16 : 24)
        rightPadding: small ? 16 : 24
        Accessible.name: text
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        contentItem: RowLayout {
            spacing: 8
            opacity: pill.enabled ? 1 : 0.38
            Icon { visible: !!pill.glyph; text: pill.glyph; size: pill.small ? 16 : 18; color: pill.fg }
            SText { text: pill.text; font: pill.small ? root.f(Tokens.font.label.medium) : root.f(Tokens.font.label.large); color: pill.fg }
        }
        background: CRect {
            radius: height / 2
            opacity: pill.enabled ? 1 : 0.5
            color: pill.tone === "filled" ? root.c("primary") : pill.tone === "danger" ? root.c("error")
                 : pill.tone === "tonal" ? root.c("secondaryContainer") : "transparent"
            CRect {
                anchors.fill: parent; radius: parent.radius; color: pill.fg
                opacity: pill.pressed ? 0.12 : pill.hovered ? 0.08 : 0
                Behavior on opacity { Anim { duration: Tokens.anim.durations.small } }
            }
            FocusRing { visible: pill.activeFocus }
        }
    }
    component IconButton: Button {
        id: ib
        property string glyph: ""
        implicitWidth: 36
        implicitHeight: 36
        focusPolicy: Qt.TabFocus
        Accessible.name: text
        Keys.onReturnPressed: clicked()
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        ToolTip.visible: hovered && !!text
        ToolTip.text: text
        ToolTip.delay: 600
        contentItem: Icon {
            text: ib.glyph; fill: ib.checked ? 1 : 0
            color: ib.checked ? root.c("onSecondaryContainer") : root.c("onSurfaceVariant")
        }
        background: CRect {
            radius: height / 2
            color: ib.checked ? root.c("secondaryContainer") : "transparent"
            CRect {
                anchors.fill: parent; radius: parent.radius; color: root.c("onSurface")
                opacity: ib.pressed ? 0.12 : ib.hovered ? 0.08 : 0
                Behavior on opacity { Anim { duration: Tokens.anim.durations.small } }
            }
            FocusRing { visible: ib.activeFocus }
        }
    }
    component Chip: Button {
        id: chip
        property string glyph: ""
        property bool selected: false
        implicitHeight: 30
        leftPadding: 8
        rightPadding: 14
        focusPolicy: Qt.NoFocus
        Accessible.name: text
        Accessible.checked: selected
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        contentItem: RowLayout {
            spacing: 6
            Icon {
                text: chip.selected ? "check" : chip.glyph; size: 16; fill: chip.selected ? 1 : 0
                color: chip.selected ? root.c("onSecondaryContainer") : root.c("primary")
            }
            SText {
                text: chip.text; font: root.f(Tokens.font.label.medium)
                color: chip.selected ? root.c("onSecondaryContainer") : root.c("onSurfaceVariant")
            }
        }
        background: CRect {
            radius: Tokens.rounding.small
            color: chip.selected ? root.c("secondaryContainer") : "transparent"
            border.width: chip.selected ? 0 : 1
            border.color: root.c("outlineVariant")
            CRect {
                anchors.fill: parent; radius: parent.radius; color: root.c("onSurface")
                opacity: chip.pressed ? 0.12 : chip.hovered ? 0.08 : 0
                Behavior on opacity { Anim { duration: Tokens.anim.durations.small } }
            }
        }
    }
    component Keycap: CRect {
        id: cap
        property string label: ""
        property bool onAccent: false
        implicitHeight: 22
        implicitWidth: Math.max(implicitHeight, capText.implicitWidth + 12)
        radius: Tokens.rounding.small
        color: onAccent ? Qt.alpha(root.c("onSecondaryContainer"), 0.14) : root.c("surfaceContainerHighest")
        // A soft bottom lip so it reads as a physical key.
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.radius; radius: parent.radius; z: -1
            anchors.bottomMargin: -2
            color: Qt.alpha(root.c("shadow"), 0.35)
        }
        SText {
            id: capText
            anchors.centerIn: parent
            text: cap.label
            font: root.f(Tokens.font.mono.small)
            color: cap.onAccent ? root.c("onSecondaryContainer") : root.c("onSurfaceVariant")
        }
    }
    component Chord: Row {
        id: chord
        property string keys: ""
        property bool onAccent: false
        spacing: 4
        Repeater {
            model: root.keyParts(chord.keys)
            Keycap { required property string modelData; label: root.keyLabel(modelData); onAccent: chord.onAccent }
        }
    }
    component Badge: CRect {
        id: badge
        property string label: ""
        readonly property string role: label === "Guide" ? "tertiary" : label === "Confirm" ? "error" : "primary"
        implicitHeight: 20
        implicitWidth: badgeText.implicitWidth + 14
        radius: height / 2
        color: root.c(role + "Container")
        SText {
            id: badgeText
            anchors.centerIn: parent
            text: badge.label
            font: root.f(Tokens.font.label.small)
            color: root.c("on" + badge.role[0].toUpperCase() + badge.role.slice(1) + "Container")
        }
    }
    component SlimBar: ScrollBar {
        id: bar
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
            implicitWidth: 4; implicitHeight: 4
            radius: 2
            color: root.c("onSurfaceVariant")
            opacity: bar.pressed ? 0.6 : bar.active ? 0.35 : 0
            Behavior on opacity { Anim { duration: Tokens.anim.durations.small } }
        }
        background: Item {}
    }

    PanelWindow {
        id: win
        visible: root.open && !root.actionHidden
        color: "transparent"
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "caelestia-command-panel"

        Rectangle { anchors.fill: parent; color: root.c("shadow"); opacity: Math.min(1, panel.shown) * 0.4 }
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        RectangularShadow {
            anchors.fill: panel
            radius: panel.radius
            blur: 40
            spread: 0
            offset.y: 12
            color: Qt.alpha(root.c("shadow"), 0.55)
            opacity: panel.opacity
            scale: panel.scale
        }

        CRect {
            id: panel
            property real shown: root.open && (root.ready || root.error) && !root.closing ? 1 : 0
            Behavior on shown {
                Anim {
                    duration: root.closing ? Tokens.anim.durations.small : Tokens.anim.durations.expressiveDefaultSpatial
                    easing: root.closing ? Tokens.anim.standard : Tokens.anim.expressiveDefaultSpatial
                }
            }
            anchors.centerIn: parent
            anchors.verticalCenterOffset: (1 - shown) * 28
            width: Math.min(800, win.width - 32)
            height: Math.min(660, win.height - 48)
            radius: Tokens.rounding.extraLarge
            color: root.c("surface")
            opacity: Math.max(0, Math.min(1, shown))
            scale: 0.94 + 0.06 * shown
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.compact ? Tokens.padding.large : Tokens.padding.large + Tokens.padding.small
                spacing: Tokens.spacing.medium

                // ── Header ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium
                    IconButton { id: backButton; visible: !!root.page.back; glyph: "arrow_back"; text: "Back"; onClicked: root.back() }
                    CRect {
                        visible: !root.page.back
                        implicitWidth: 40; implicitHeight: 40
                        radius: Tokens.rounding.large
                        color: root.c("primaryContainer")
                        Icon { anchors.centerIn: parent; text: "keyboard"; fill: 1; size: 22; color: root.c("onPrimaryContainer") }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        SText { text: root.page.title || "Commands"; font: root.f(Tokens.font.title.large); elide: Text.ElideRight; Layout.fillWidth: true }
                        SText {
                            readonly property int count: (root.page.rows || []).length
                            text: root.page.view === "confirm" ? "Needs your confirmation" : root.page.view === "details" ? "Details and every binding"
                                : root.page.view === "notes" ? `${count} matching ${count === 1 ? "note" : "notes"}`
                                : !root.page.query && root.page.category === "All" && root.page.view === "commands" ? "Shortcuts, workflows and guides"
                                : `${count} ${count === 1 ? "result" : "results"}`
                            font: root.f(Tokens.font.label.medium)
                            color: root.c("onSurfaceVariant")
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    IconButton {
                        visible: panel.width > 520
                        glyph: root.touchMode ? "unfold_less" : "unfold_more"
                        text: root.touchMode ? "Compact rows" : "Larger rows"
                        checkable: true; checked: root.touchMode
                        onClicked: root.touchMode = !root.touchMode
                    }
                    IconButton { glyph: "close"; text: "Close"; Accessible.description: "Close command panel, Escape"; onClicked: root.close() }
                }

                // ── Search ──
                TextField {
                    id: search
                    visible: root.page.view !== "details" && root.page.view !== "confirm"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    font: root.f(Tokens.font.body.medium)
                    color: root.c("onSurface")
                    placeholderTextColor: root.c("onSurfaceVariant")
                    selectionColor: root.c("primary")
                    selectedTextColor: root.c("onPrimary")
                    placeholderText: root.page.view === "notes" ? "Search filenames or words in your notes…" : "Find an action, shortcut, or category…"
                    Accessible.name: root.page.view === "notes" ? "Search saved notes" : "Search commands and shortcuts"
                    leftPadding: 46
                    rightPadding: 44
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    background: CRect {
                        radius: height / 2
                        color: root.c("surfaceContainer")
                        Icon {
                            anchors.left: parent.left; anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.page.view === "notes" ? "manage_search" : "search"
                            color: search.activeFocus ? root.c("primary") : root.c("onSurfaceVariant")
                        }
                        CRect {
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: 16
                            opacity: search.text ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Anim { duration: Tokens.anim.durations.small } }
                            Icon { anchors.centerIn: parent; text: "close"; size: 18 }
                            StateLayer { radius: 16; onClicked: { search.clear(); queryTimer.restart(); search.forceActiveFocus(); } }
                        }
                    }
                    onTextEdited: queryTimer.restart()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) { root.selectStep(event.key === Qt.Key_Down ? 1 : -1); event.accepted = true; }
                        else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) { root.selectStep(event.key === Qt.Key_PageDown ? 6 : -6); event.accepted = true; }
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            queryTimer.stop();
                            if (search.text === root.page.query) root.activate(false);
                            else root.send({op: "query", query: search.text, category: root.page.category || "All", enter: true});
                            event.accepted = true;
                        }
                    }
                }

                // ── Category filter chips ──
                Flickable {
                    id: chipFlick
                    visible: root.page.view === "commands"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    contentWidth: chips.width
                    contentHeight: height
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    WheelHandler {
                        onWheel: event => {
                            const d = event.angleDelta.y || event.angleDelta.x;
                            chipFlick.contentX = Math.max(0, Math.min(chipFlick.contentWidth - chipFlick.width, chipFlick.contentX - d));
                        }
                    }
                    Behavior on contentX { enabled: !chipFlick.dragging; Anim { duration: Tokens.anim.durations.small } }
                    Rectangle {
                        parent: chipFlick; z: 1
                        width: 28; height: chipFlick.height
                        visible: chipFlick.contentX > 1
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: root.c("surface") }
                            GradientStop { position: 1; color: Qt.alpha(root.c("surface"), 0) } }
                    }
                    Rectangle {
                        parent: chipFlick; z: 1
                        x: chipFlick.width - width; width: 36; height: chipFlick.height
                        visible: chipFlick.contentX < chipFlick.contentWidth - chipFlick.width - 1
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.alpha(root.c("surface"), 0) }
                            GradientStop { position: 1; color: root.c("surface") } }
                    }
                    Row {
                        id: chips
                        spacing: Tokens.spacing.small
                        Repeater {
                            model: root.categories
                            Chip {
                                required property string modelData
                                text: modelData
                                glyph: root.groupIcons[modelData] || "label"
                                selected: root.page.category === modelData || (modelData === "All" && root.page.category === "Browse all")
                                onClicked: root.send({op: "query", query: search.text, category: modelData})
                            }
                        }
                    }
                }

                // ── Error banner ──
                CRect {
                    visible: !!root.error
                    Layout.fillWidth: true
                    implicitHeight: errorRow.implicitHeight + 20
                    radius: Tokens.rounding.large
                    color: root.c("errorContainer")
                    Accessible.role: Accessible.AlertMessage
                    Accessible.name: root.error
                    RowLayout {
                        id: errorRow
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                        spacing: 10
                        Icon { text: "error"; fill: 1; color: root.c("onErrorContainer") }
                        SText { text: root.error; color: root.c("onErrorContainer"); wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }

                // ── Results ──
                RowLayout {
                    visible: root.page.view !== "details" && root.page.view !== "confirm"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacing.large
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ListView {
                            id: list
                            anchors.fill: parent
                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.page.rows || []
                            ScrollBar.vertical: SlimBar {}
                            Accessible.name: "Search results"
                            highlightFollowsCurrentItem: false
                            highlight: CRect {
                                visible: list.currentIndex >= 0 && !!list.currentItem
                                width: list.width
                                y: list.currentItem ? list.currentItem.y + list.currentItem.rowY : 0
                                height: list.currentItem ? list.currentItem.rowHeight : 0
                                radius: Tokens.rounding.large
                                color: root.c("secondaryContainer")
                                Behavior on y { Anim { duration: Tokens.anim.durations.expressiveFastSpatial; easing: Tokens.anim.expressiveFastSpatial } }
                                Behavior on height { Anim { duration: Tokens.anim.durations.small } }
                                // Active indicator: keeps the selection at ≥3:1 whatever the wallpaper.
                                Rectangle {
                                    x: 5; width: 4; height: 18; radius: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.c("primary")
                                }
                            }
                            delegate: Item {
                                id: entry
                                required property var modelData
                                required property int index
                                readonly property bool current: list.currentIndex === index
                                readonly property bool heading: !!modelData.section && (index === 0 || root.page.rows[index - 1]?.section !== modelData.section)
                                readonly property real rowY: heading ? (index === 0 ? 22 : 32) : 0
                                readonly property real rowHeight: root.touchMode || root.compact ? 62 : 50
                                width: list.width
                                height: rowY + rowHeight
                                SText {
                                    visible: entry.heading
                                    text: entry.modelData.section
                                    font: root.f(Tokens.font.label.large)
                                    color: root.c("primary")
                                    x: 16
                                    y: entry.rowY - height - 6
                                }
                                Item {
                                    id: rowItem
                                    y: entry.rowY
                                    width: parent.width
                                    height: entry.rowHeight
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: entry.modelData.title + ". " + entry.modelData.subtitle + ". " + entry.modelData.key
                                    Accessible.description: entry.modelData.disabled ? entry.modelData.reason : entry.modelData.badge || "Run action"
                                    StateLayer {
                                        radius: Tokens.rounding.large
                                        onClicked: { list.currentIndex = entry.index; root.activate(false); }
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 18
                                        anchors.rightMargin: 14
                                        spacing: 14
                                        opacity: entry.modelData.disabled ? 0.6 : 1
                                        CRect {
                                            implicitWidth: 34; implicitHeight: 34
                                            radius: entry.current ? 17 : Tokens.rounding.medium
                                            color: entry.current ? root.c("primary") : root.c("surfaceContainerHigh")
                                            Behavior on radius { Anim { duration: Tokens.anim.durations.expressiveFastSpatial; easing: Tokens.anim.expressiveFastSpatial } }
                                            Icon {
                                                anchors.centerIn: parent
                                                text: root.iconFor(entry.modelData)
                                                fill: entry.current ? 1 : 0
                                                color: entry.current ? root.c("onPrimary") : root.c("onSurfaceVariant")
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            SText {
                                                text: root.marks(entry.modelData.titleHtml || entry.modelData.title, entry.current ? root.c("onSecondaryContainer") : root.c("primary"))
                                                textFormat: Text.StyledText
                                                font: root.f(Tokens.font.title.small)
                                                color: entry.current ? root.c("onSecondaryContainer") : root.c("onSurface")
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                            }
                                            SText {
                                                text: entry.modelData.subtitle + (root.compact && entry.modelData.key ? " · " + entry.modelData.key : "")
                                                font: root.f(Tokens.font.body.small)
                                                color: entry.current ? root.c("onSecondaryContainer") : root.c("onSurfaceVariant")
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Badge { visible: !!entry.modelData.badge && !root.compact; label: entry.modelData.badge || "" }
                                        Chord { visible: !!entry.modelData.key && !root.compact; keys: entry.modelData.key || ""; onAccent: entry.current }
                                        Icon {
                                            visible: !root.compact && (entry.modelData.kind === "family" || entry.modelData.kind === "browse")
                                            text: "chevron_right"
                                            color: entry.current ? root.c("onSecondaryContainer") : root.c("onSurfaceVariant")
                                        }
                                    }
                                }
                            }
                        }
                        // Soft fade at the scroll edges, like Caelestia's VerticalFadeListView.
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: 22
                            opacity: list.atYBeginning ? 0 : 1
                            Behavior on opacity { Anim { duration: Tokens.anim.durations.small } }
                            gradient: Gradient {
                                GradientStop { position: 0; color: root.c("surface") }
                                GradientStop { position: 1; color: Qt.alpha(root.c("surface"), 0) }
                            }
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 32
                            opacity: list.atYEnd ? 0 : 1
                            Behavior on opacity { Anim { duration: Tokens.anim.durations.small } }
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.alpha(root.c("surface"), 0) }
                                GradientStop { position: 1; color: root.c("surface") }
                            }
                        }
                        ColumnLayout {
                            visible: !root.page.rows || root.page.rows.length === 0
                            anchors.centerIn: parent
                            width: parent.width - 32
                            spacing: Tokens.spacing.medium
                            CRect {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 72; implicitHeight: 72; radius: 36
                                color: root.c("surfaceContainerHigh")
                                Icon { anchors.centerIn: parent; size: 34; text: root.ready ? "search_off" : "hourglass_empty" }
                            }
                            SText { text: root.ready ? "No matches" : "Loading…"; font: root.f(Tokens.font.title.medium); Layout.alignment: Qt.AlignHCenter }
                            SText {
                                text: root.page.view === "notes" ? "Try a filename or another word, or start one with New note (Super+Shift+N)." : "Try “notes”, “scan”, or “window”, or choose another category."
                                color: root.c("onSurfaceVariant"); wrapMode: Text.Wrap
                                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                            }
                            PillButton { text: "Clear search"; glyph: "backspace"; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 4; onClicked: root.send({op: "query", query: "", category: "All"}) }
                        }
                    }
                    CRect {
                        visible: root.page.view === "notes" && panel.width >= 780 && root.chosen() !== null
                        Layout.preferredWidth: Math.min(330, panel.width * .38)
                        Layout.fillHeight: true
                        radius: Tokens.rounding.large
                        color: root.c("surfaceContainer")
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 18
                            spacing: 10
                            RowLayout {
                                spacing: 8
                                Icon { text: "description"; size: 18; color: root.c("primary") }
                                SText { text: "Preview"; font: root.f(Tokens.font.label.large); color: root.c("primary") }
                            }
                            ScrollView {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                contentWidth: availableWidth
                                ScrollBar.vertical: SlimBar {}
                                SText {
                                    width: parent.width
                                    text: root.marks(root.chosen()?.preview || "Select a note to preview it.", root.c("primary"))
                                    textFormat: Text.RichText; wrapMode: Text.Wrap
                                    lineHeight: 1.25
                                }
                            }
                        }
                    }
                }
                CRect {
                    visible: root.page.view === "notes" && panel.width < 780 && root.chosen() !== null
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(150, panel.height * .22)
                    radius: Tokens.rounding.large
                    color: root.c("surfaceContainer")
                    ScrollView {
                        anchors.fill: parent; anchors.margins: 14
                        contentWidth: availableWidth
                        SText {
                            width: parent.width
                            text: root.marks(root.chosen()?.preview || "Select a note to preview it.", root.c("primary"))
                            textFormat: Text.RichText; wrapMode: Text.Wrap
                        }
                    }
                }

                // ── Details / confirmation ──
                ScrollView {
                    visible: root.page.view === "details" || root.page.view === "confirm"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    ScrollBar.vertical: SlimBar {}
                    ColumnLayout {
                        readonly property bool confirm: root.page.view === "confirm"
                        id: detailView
                        width: parent.width
                        spacing: Tokens.spacing.large
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: Tokens.spacing.large
                            CRect {
                                implicitWidth: 52; implicitHeight: 52
                                radius: Tokens.rounding.large
                                color: detailView.confirm ? root.c("errorContainer") : root.c("primaryContainer")
                                Icon {
                                    anchors.centerIn: parent; size: 26; fill: 1
                                    text: detailView.confirm ? "warning" : root.iconFor(root.page.detail)
                                    color: detailView.confirm ? root.c("onErrorContainer") : root.c("onPrimaryContainer")
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                SText {
                                    text: detailView.confirm ? "Confirm" : (root.page.detail?.reference ? "Guide" : root.page.detail?.group || "Action")
                                    font: root.f(Tokens.font.label.large)
                                    color: detailView.confirm ? root.c("error") : root.c("primary")
                                }
                                SText {
                                    text: root.page.detail?.title || ""
                                    font: root.f(Tokens.font.headline.small)
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                        CRect {
                            Layout.fillWidth: true
                            implicitHeight: bodyText.implicitHeight + 36
                            radius: Tokens.rounding.large
                            color: root.c("surfaceContainer")
                            SText {
                                id: bodyText
                                anchors.fill: parent; anchors.margins: 18
                                text: detailView.confirm ? root.page.detail?.confirmation || "" : root.page.detail?.body || ""
                                font: root.f(Tokens.font.body.large)
                                wrapMode: Text.Wrap
                                lineHeight: 1.2
                            }
                        }
                        ColumnLayout {
                            visible: !detailView.confirm
                            Layout.fillWidth: true
                            spacing: 10
                            SText { text: "Shortcuts"; font: root.f(Tokens.font.label.large); color: root.c("onSurfaceVariant") }
                            Repeater {
                                model: root.page.detail?.keys || []
                                Chord { required property string modelData; keys: modelData }
                            }
                            SText {
                                visible: !(root.page.detail?.keys || []).length
                                text: "Available from this panel"
                                color: root.c("onSurfaceVariant")
                            }
                        }
                        RowLayout {
                            visible: !!root.page.detail?.target
                            spacing: 10
                            Icon { text: "select_window"; size: 20 }
                            SText { text: "Target: " + (root.page.detail?.target || ""); color: root.c("onSurfaceVariant"); wrapMode: Text.Wrap; Layout.fillWidth: true }
                        }
                        CRect {
                            visible: !!root.page.detail?.disabled
                            Layout.fillWidth: true
                            implicitHeight: reasonRow.implicitHeight + 20
                            radius: Tokens.rounding.large
                            color: root.c("errorContainer")
                            RowLayout {
                                id: reasonRow
                                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                                spacing: 10
                                Icon { text: "block"; color: root.c("onErrorContainer") }
                                SText { text: root.page.detail?.reason || ""; color: root.c("onErrorContainer"); wrapMode: Text.Wrap; Layout.fillWidth: true }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: Tokens.spacing.small
                            Item { Layout.fillWidth: true }
                            PillButton {
                                id: cancelButton
                                text: detailView.confirm ? "Cancel" : "Back"
                                tone: "tonal"
                                onClicked: root.back()
                            }
                            PillButton {
                                text: detailView.confirm ? "Confirm action" : "Run action"
                                glyph: detailView.confirm ? "check" : "play_arrow"
                                tone: detailView.confirm ? "danger" : "filled"
                                visible: !root.page.detail?.reference
                                enabled: !root.page.detail?.disabled
                                onClicked: root.send({op: "activate", id: root.page.detail.id, confirmed: detailView.confirm})
                            }
                        }
                    }
                }

                // ── Notice ──
                RowLayout {
                    visible: !!root.page.notice
                    Layout.fillWidth: true
                    spacing: 8
                    Icon { text: "info"; size: 18 }
                    SText { text: root.page.notice || ""; font: root.f(Tokens.font.label.medium); color: root.c("onSurfaceVariant"); wrapMode: Text.Wrap; Layout.fillWidth: true }
                }

                // ── Footer: key hints + contextual actions ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.large
                    // Hints take whatever room the buttons leave and clip, so a crowded
                    // footer can never stretch the panel.
                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitWidth: hints.implicitWidth
                        implicitHeight: hints.implicitHeight
                        clip: true
                        RowLayout {
                            id: hints
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.spacing.large
                            Repeater {
                                model: root.page.view === "details" || root.page.view === "confirm"
                                    ? [["Tab", "Move"], ["Enter", "Choose"], ["Esc", "Back"]]
                                    : root.compact || root.page.view === "notes"
                                    ? [["↑↓", "Navigate"], ["Enter", "Open"], ["Esc", "Back"]]
                                    : [["↑↓", "Navigate"], ["Enter", "Run"], ["Ctrl+I", "Details"], ["Esc", "Back"]]
                                RowLayout {
                                    required property var modelData
                                    spacing: 6
                                    Chord { keys: modelData[0] === "↑↓" ? "↑+↓" : modelData[0] }
                                    SText { text: modelData[1]; font: root.f(Tokens.font.label.medium); color: root.c("onSurfaceVariant") }
                                }
                            }
                        }
                    }
                    PillButton { text: "Browse all"; glyph: "explore"; tone: "text"; small: true; visible: root.page.view === "commands" && panel.width >= 720; onClicked: root.send({op: "query", query: "", category: "Browse all"}) }
                    PillButton { text: "Details"; glyph: "info"; tone: "text"; small: true; visible: root.page.view === "commands" || root.page.view === "family"; enabled: root.chosen() !== null; onClicked: root.activate(true) }
                    PillButton { text: "New note"; glyph: "note_add"; tone: "text"; small: true; visible: root.page.view === "notes"; onClicked: root.launchWorkflow("notes-new") }
                    PillButton {
                        text: "Edit"; glyph: "edit"; tone: "text"; small: true
                        visible: root.page.view === "notes" && panel.width >= 620; enabled: root.chosen() !== null
                        ToolTip.visible: hovered; ToolTip.text: "Edit this note (Ctrl+E)"; ToolTip.delay: 500
                        onClicked: root.activate(false, true)
                    }
                    PillButton { text: "Refresh"; glyph: "refresh"; tone: "text"; small: true; visible: root.page.view === "notes" && panel.width >= 720; onClicked: root.send({op: "refresh"}) }
                }
            }
        }
        Shortcut { sequence: "Escape"; onActivated: root.back() }
        Shortcut { sequence: "Ctrl+I"; enabled: root.page.view === "commands" || root.page.view === "family"; onActivated: root.activate(true) }
        Shortcut { sequence: "Alt+Left"; onActivated: root.back() }
        Shortcut { sequence: "Ctrl+E"; enabled: root.page.view === "notes"; onActivated: root.activate(false, true) }
    }
}
