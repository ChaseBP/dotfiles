pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.launcher.items
import qs.modules.launcher.services

StyledListView {
    id: root

    required property SearchBar search
    required property ScreenState screenState

    property string displayText

    readonly property string requestedState: stateForText(search.text)
    readonly property string displayState: stateForText(displayText)

    function syncDisplayText(): void {
        if (screenState.launcher && requestedState === displayState)
            displayText = search.text;
    }

    function stateForText(text: string): string {
        const prefix = GlobalConfig.launcher.actionPrefix;
        if (text.startsWith(prefix)) {
            for (const action of ["calc", "scheme", "variant"])
                if (text.startsWith(`${prefix}${action} `))
                    return action;

            return "actions";
        }

        return "apps";
    }

    function resultsForText(text: string): var {
        switch (stateForText(text)) {
        case "actions":
            return Actions.query(text);
        case "calc":
            return [0];
        case "scheme":
            return Schemes.query(text);
        case "variant":
            return M3Variants.query(text);
        default:
            return Apps.search(text);
        }
    }

    model: ScriptModel {
        values: root.resultsForText(root.displayText)
        onValuesChanged: root.resetIndex()
    }

    // ---- Live variant preview (personal fork, ~/dotfiles/caelestia/quickshell) ----
    // In ">variant", moving the highlight (keys, Tab, or moving the mouse over a row)
    // applies that variant after a short pause, so you can see it before choosing.
    // Enter or a click keeps it; closing the launcher or leaving the list any other way
    // restores the variant it was opened with. Opening or filtering never previews.
    // One `caelestia scheme set` runs at a time (~280 ms); a newer pick replaces the queued one.
    property string previewOrigin: ""   // committed variant when previewing started
    property string previewShown: ""    // variant the preview last applied
    property string previewQueued: ""
    property bool previewConfirmed: false
    property bool previewHold: false    // index changes that aren't the user's
    property double previewSettleUntil: 0 // ...and the list (re)building just after a reset
    // The committed variant, read live like services/Colours.qml does. Schemes.currentVariant
    // only refreshes when the list opens (async), so it's stale right after the variant was
    // changed elsewhere (Nexus, CLI, a wallpaper's smart pick) -- and Escape would "restore"
    // the wrong one.
    property string liveVariant: Schemes.currentVariant

    FileView {
        path: `${Paths.state}/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const v = JSON.parse(text()).variant;
                if (v)
                    root.liveVariant = v;
            } catch (e) {}
        }
    }

    // Start on the current variant (not the top row), so arrows step to its neighbours.
    function resetIndex(): void {
        previewHold = true;
        let i = 0;
        if (stateForText(displayText) === "variant") {
            const vals = model.values;
            for (let k = 0; k < vals.length; k++)
                if (vals[k].variant === liveVariant) {
                    i = k;
                    break;
                }
        }
        currentIndex = i;
        previewHold = false;
        previewSettleUntil = Date.now() + 300;
    }

    function previewRun(variant: string): void {
        if (previewProc.running) {
            previewQueued = variant;
            return;
        }
        previewQueued = "";
        previewProc.command = ["caelestia", "scheme", "set", "-v", variant];
        previewProc.running = true;
    }

    // Called by M3Variants' onClicked (Enter or click): keep this one.
    function confirmVariant(variant: string): void {
        previewTimer.stop();
        previewConfirmed = true;
        if (variant !== (previewShown || previewOrigin || liveVariant))
            previewRun(variant);
        else
            previewQueued = "";
    }

    function endPreview(): void {
        previewTimer.stop();
        if (!previewConfirmed && previewOrigin && previewShown && previewShown !== previewOrigin)
            previewRun(previewOrigin);
        else if (!previewConfirmed)
            previewQueued = "";
        previewOrigin = "";
        previewShown = "";
        previewConfirmed = false;
    }

    onCurrentIndexChanged: {
        if (!previewHold && Date.now() >= previewSettleUntil && state === "variant" && screenState.launcher)
            previewTimer.restart();
    }

    Timer {
        id: previewTimer

        interval: 150
        onTriggered: {
            const v = root.currentItem?.modelData?.variant;
            if (!v || root.state !== "variant" || !root.screenState.launcher)
                return;
            if (!root.previewOrigin)
                root.previewOrigin = root.liveVariant || v;
            if (v === (root.previewShown || root.previewOrigin))
                return;
            root.previewShown = v;
            root.previewRun(v);
        }
    }

    Process {
        id: previewProc

        onExited: {
            if (root.previewQueued)
                root.previewRun(root.previewQueued);
        }
    }

    spacing: Tokens.spacing.small
    orientation: Qt.Vertical
    implicitHeight: (Tokens.sizes.launcher.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.ApplyRange

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        radius: Tokens.rounding.large
        color: Colours.palette.m3onSurface
        opacity: 0.08

        y: root.currentItem?.y ?? 0
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        Behavior on y {
            Anim {}
        }
    }

    state: screenState.launcher ? requestedState : displayState

    onStateChanged: {
        if (state === "scheme" || state === "variant")
            Schemes.reload();
        if (state !== "variant")
            endPreview();
    }

    Component.onCompleted: displayText = search.text

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.delegate: appItem
            }
        },
        State {
            name: "actions"

            PropertyChanges {
                root.delegate: actionItem
            }
        },
        State {
            name: "calc"

            PropertyChanges {
                root.delegate: calcItem
            }
        },
        State {
            name: "scheme"

            PropertyChanges {
                root.delegate: schemeItem
            }
        },
        State {
            name: "variant"

            PropertyChanges {
                root.delegate: variantItem
            }
        }
    ]

    transitions: Transition {
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 1
                    to: 0.9
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
            }
            PropertyAction {
                target: root
                property: "delegate"
                value: null
            }
            ScriptAction {
                script: root.displayText = root.search.text
            }
            PropertyAction {
                target: root
                property: "delegate"
            }
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 0.9
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
            }
            PropertyAction {
                targets: [root.add, root.remove]
                property: "enabled"
                value: true
            }
        }
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    add: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 0
            to: 1
        }
    }

    remove: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 1
            to: 0
        }
    }

    move: Transition {
        Anim {
            property: "y"
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    addDisplaced: Transition {
        Anim {
            property: "y"
            type: Anim.StandardSmall
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    displaced: Transition {
        Anim {
            property: "y"
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    Component {
        id: appItem

        AppItem {
            screenState: root.screenState
        }
    }

    Component {
        id: actionItem

        ActionItem {
            list: root
        }
    }

    Component {
        id: calcItem

        CalcItem {
            list: root
        }
    }

    Component {
        id: schemeItem

        SchemeItem {
            list: root
        }
    }

    Component {
        id: variantItem

        VariantItem {
            list: root
        }
    }

    Connections {
        function onTextChanged() {
            root.syncDisplayText();
        }

        target: root.search
    }

    Connections {
        function onLauncherChanged() {
            root.syncDisplayText();
            if (!root.screenState.launcher)
                root.endPreview();
        }

        target: root.screenState
    }
}
