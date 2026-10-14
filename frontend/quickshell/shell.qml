import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property string configPath: Quickshell.env("BACKUPBAR_CONFIG") || ((Quickshell.env("HOME") || "") + "/.config/backupbar/config.json")
    property string stateDir: Quickshell.env("BACKUPBAR_STATE_DIR") || ((Quickshell.env("HOME") || "") + "/.local/state/backupbar")
    property string backupbarBin: Quickshell.env("BACKUPBAR_BIN") || "backupbar"
    property string snapshotPath: root.stateDir + "/snapshot.json"
    property string uiPath: root.stateDir + "/ui.json"
    property string eventPath: root.stateDir + "/state-event.json"
    property string textFont: "Fira Code"
    property string iconFont: "Symbols Nerd Font Mono"
    property string unknownIcon: "󰘥"
    property string refreshIcon: "󰑐"
    property string closeIcon: "󰅖"
    // Bar drop-down geometry. The panel is a Waybar companion chip on the bar
    // (modules-left, left of center). Waybar and QuickShell are separate
    // processes, so no anchor item exists; the surface anchors to the top bar
    // edge and the left screen edge — one horizontal anchor, chip's side —
    // hung below the bar by panelTopMargin from the surface's top edge to the
    // card, with a gutter from the left edge for the shadow's bleed. The
    // surface carries exactly the card plus that gutter — never the screen.
    // 52 clears the 46px Waybar island (13px font + padding) with a 6px
    // gap for the drop shadow; bar height is not queryable across the
    // Waybar/QuickShell process boundary.
    property int panelTopMargin: 52
    property int panelMaxWidth: 1120
    property int panelGutterWidth: 16
    property int panelMaxHeight: 760
    property int panelMinHeight: 480
    property int panelChrome: 16
    property int panelMinWidth: 372

    // Breakpoint pattern shared with the Switchyard panel: fixed margins and
    // font sizes below wide/narrow thresholds, mirroring Switchyard's
    // narrowLayout/shortViewport pair, in BackupBar's vocabulary.
    property bool narrowWidth: panel.width < 1000
    property bool shortViewport: panel.height < 700
    property real nowMilliseconds: Date.now()
    property var viewData: snapshotAdapter.view && snapshotAdapter.view.summary ? snapshotAdapter.view : ({ summary: {}, systems: [], storage: [], timeline: [] })
    property var summary: viewData.summary || ({})
    property var systems: viewData.systems || []
    property var storage: viewData.storage || []
    property var timeline: viewData.timeline || []
    property var source: viewData.source || ({})

    // The presenter owns every derived fact; source classification stays out of
    // the QML. view.context carries the earliest upcoming scheduled run.
    property var context: viewData.context || ({})

    property string effectiveStatus: snapshotExpired ? "stale" : (snapshotAdapter.status || "loading")
    property bool snapshotExpired: {
        if (!snapshotAdapter.generatedAt) {
            return false
        }
        var generated = Date.parse(snapshotAdapter.generatedAt)
        var threshold = Number(viewData.staleAfterSeconds || 240)
        return isNaN(generated) || root.nowMilliseconds - generated > threshold * 1000
    }

    function runBackupbar(args) {
        if (actionRunner.running) {
            return
        }
        actionRunner.command = [root.backupbarBin].concat(args).concat(["--config", root.configPath])
        actionRunner.running = true
    }

    function closeModal() {
        if (closeRunner.running) {
            return
        }
        closeRunner.command = [root.backupbarBin, "ui", "close", "--config", root.configPath]
        closeRunner.running = true
    }

    function statusColor(status) {
        if (status === "critical" || status === "failed") {
            return "#FF6B7A"
        }
        if (status === "warning" || status === "stalled") {
            return "#F2C572"
        }
        if (status === "stale" || status === "unknown" || status === "loading") {
            return "#6A6E95"
        }
        if (status === "active") {
            return "#85E1FB"
        }
        return "#82FB9C"
    }

    function compactNumber(value) {
        var number = Number(value || 0)
        if (number >= 1000000) {
            return (number / 1000000).toFixed(1) + "m"
        }
        if (number >= 1000) {
            return (number / 1000).toFixed(1) + "k"
        }
        return number.toLocaleString()
    }

    function storageWidth(mount) {
        var percent = Number(mount.usePercent)
        return isNaN(percent) ? 0 : Math.max(0, Math.min(100, percent))
    }

    // Detail band under the job label. Each fact is presenter-projected; the
    // lines stay short and elide rather than pushing the card wider.
    function systemDetail(system) {
        if (!system) {
            return ""
        }
        var lines = []
        if (system.repoUsageText) {
            lines.push("repo " + system.repoUsageText)
        }
        var metrics = system.metrics || ({})
        if (metrics.snapshotCount !== undefined) {
            lines.push(metrics.snapshotCount + (system.overdue ? " snapshots (overdue)" : " snapshots"))
        } else if (metrics.allArchives) {
            lines.push(metrics.allArchives.replace("All archives:", "archives"))
        } else if (metrics.jobs) {
            lines.push(metrics.jobs.length + (metrics.jobs.length === 1 ? " timer" : " timers") + (system.overdue ? " (overdue)" : ""))
        } else {
            lines.push(system.detail || system.coverage || "no detail")
        }
        if (system.nextAtText) {
            lines.push("next " + system.nextAtText)
        }
        return lines.join("  ·  ")
    }

    function reloadState() {
        snapshotFile.reload()
        uiFile.reload()
    }

    // The drop-down's size, counted from the parts actually laid out — never
    // from implicit sizes, which collapse on Flickable/ListView panes. Vertical
    // budget: 160 = 146 BackupCard row + 8 spacing (12 visible rows max), then
    // 120 of fixed chrome (header band, metric-tile band, list header, PRESSURE
    // MAP band, OBSERVATION STREAM, the no-touch footer and paddings), + 146
    // extra for a populated timeline strip. Capped to the true viewport minus
    // the bar-edge strip (panelTopMargin) and a breathing gap, so on capped
    // viewports the job list scrolls inside with its own cue instead of
    // inflating the surface toward the screen edge.
    function panelHeight() {
        var rowsHeight = Math.min(root.systems.length, 12) * 160
        var contentHeight = 120 + rowsHeight + (root.timeline.length > 0 ? 146 : 0)
        var availableHeight = Math.max(root.panelMinHeight, panel.screen.height - root.panelTopMargin - 12)
        return Math.max(root.panelMinHeight, Math.min(root.panelMaxHeight, availableHeight, contentHeight))
    }

    // Width is a fixed surface width: layer-shell margins only inset the
    // anchored (left/right) edges — they cannot shrink the window — so the
    // bounded surface is one fixed bar-drop width, anchored at the chip's side
    // with a gutter for the shadow's bleed, clamped to the viewport with a
    // floor.
    function panelWidth() {
        return Math.min(root.panelMaxWidth + root.panelGutterWidth,
                        Math.max(root.panelMinWidth, panel.screen.width - 16))
    }

    Process {
        id: actionRunner
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    console.log(text.trim())
                }
            }
        }
    }

    Process {
        id: closeRunner
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    console.log(text.trim())
                }
            }
        }
    }

    FileView {
        id: eventFile
        path: root.eventPath
        watchChanges: true
        onFileChanged: root.reloadState()
    }

    FileView {
        id: snapshotFile
        path: root.snapshotPath
        watchChanges: false

        JsonAdapter {
            id: snapshotAdapter
            property int snapshotVersion: 0
            property string generatedAt: ""
            property string status: "loading"
            property var view: ({})
        }
    }

    FileView {
        id: uiFile
        path: root.uiPath
        watchChanges: false

        JsonAdapter {
            id: uiAdapter
            property bool open: false
            property string requestedAt: ""
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.nowMilliseconds = Date.now()
    }

    Timer {
        interval: 2800
        running: true
        repeat: true
        onTriggered: orbitCanvas.phase = orbitCanvas.phase + 0.14
    }

    Component.onCompleted: {
        eventFile.reload()
        root.reloadState()
    }

    // Streamlined badge: tone carried by a left dot, not a filled pill —
    // same glanceable status, less width.
    component StatusBadge: Rectangle {
        property string status: "unknown"
        property color accent: root.statusColor(status)
        implicitWidth: badgeDot.implicitWidth + 4 + badgeText.implicitWidth + 8
        implicitHeight: 14
        color: "transparent"

        Text {
            id: badgeDot
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            text: "●"
            color: parent.accent
            font.family: root.textFont
            font.pixelSize: 7
        }

        Text {
            id: badgeText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: badgeDot.right
            anchors.leftMargin: 4
            text: parent.status
            color: parent.accent
            font.family: root.textFont
            font.pixelSize: 8
        }
    }

    component ActionButton: Rectangle {
        signal clicked()
        property string icon: ""
        property string label: ""
        property color accent: "#82FB9C"
        Layout.preferredHeight: 36
        Layout.preferredWidth: 104
        color: buttonArea.containsMouse ? Qt.rgba(accent.r, accent.g, accent.b, 0.16) : "#121827"
        border.color: buttonArea.containsMouse ? accent : "#2B3550"
        border.width: 1
        radius: 0

        RowLayout {
            anchors.centerIn: parent
            spacing: 7
            Text {
                text: parent.parent.icon
                color: parent.parent.accent
                font.family: root.iconFont
                font.pixelSize: 15
            }
            Text {
                text: parent.parent.label
                color: "#DDF7FF"
                font.family: root.textFont
                font.pixelSize: 10
            }
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component MetricTile: Rectangle {
        property string label: ""
        property string value: ""
        property string detail: ""
        property color accent: "#82FB9C"
        Layout.fillWidth: true
        Layout.preferredHeight: 70
        color: "#101522"
        border.color: "#253057"
        border.width: 1
        radius: 0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: parent.parent.label.toUpperCase()
                color: "#6A6E95"
                font.family: root.textFont
                font.pixelSize: 9
                font.bold: true
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: parent.parent.parent.value
                    color: parent.parent.parent.accent
                    font.family: root.textFont
                    font.pixelSize: 22
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: parent.parent.parent.detail
                    color: "#9AA4BE"
                    font.family: root.textFont
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }
        }
    }

    component BackupCard: Rectangle {
        required property var modelData
        property var system: modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 146
        color: "#111725"
        border.color: "#253057"
        border.width: 1
        radius: 0

        Rectangle {
            width: 5
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: root.statusColor(system.status)
            radius: 0
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            anchors.topMargin: 11
            anchors.bottomMargin: 10
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: system.icon || root.unknownIcon
                    color: root.statusColor(system.status)
                    font.family: root.iconFont
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: system.label || "backup system"
                    color: "#DDF7FF"
                    font.family: root.textFont
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                }
                StatusBadge { status: system.status || "unknown" }
            }

            Text {
                Layout.fillWidth: true
                text: system.latestText || "not observed"
                color: root.statusColor(system.status)
                font.family: root.textFont
                font.pixelSize: 11
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.systemDetail(system)
                color: "#A4B1CC"
                font.family: root.textFont
                font.pixelSize: 9
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    text: system.schedule || "schedule unknown"
                    color: "#6A6E95"
                    font.family: root.textFont
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
                Text {
                    Layout.maximumWidth: 220
                    text: system.target || "target unknown"
                    color: "#85E1FB"
                    font.family: root.textFont
                    font.pixelSize: 9
                    elide: Text.ElideMiddle
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                color: "#090C14"
                radius: 0
                border.color: "#242D44"
                border.width: 1
                Rectangle {
                    width: system.ageSeconds === null || system.ageSeconds === undefined ? 0 : Math.max(4, Math.min(parent.width, parent.width * (1 - Math.min(1, Number(system.ageSeconds) / 172800))))
                    height: parent.height
                    color: root.statusColor(system.status)
                    radius: 0
                }
            }
        }
    }

    component StorageRow: Rectangle {
        required property var modelData
        property var mount: modelData
        height: 42
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        color: "#101522"
        border.color: "#253057"
        border.width: 1
        radius: 0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: mount.label + "  " + mount.path
                    color: "#DDF7FF"
                    font.family: root.textFont
                    font.pixelSize: 9
                    elide: Text.ElideMiddle
                }
                Text {
                    text: mount.usePercent === null || mount.usePercent === undefined ? "--" : Number(mount.usePercent).toFixed(0) + "%"
                    color: root.statusColor(mount.status)
                    font.family: root.textFont
                    font.pixelSize: 10
                    font.bold: true
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                color: "#080B12"
                radius: 0
                Rectangle {
                    width: parent.width * root.storageWidth(mount) / 100
                    height: parent.height
                    color: root.statusColor(mount.status)
                    radius: 0
                }
            }
        }
    }

    // Bounded bar drop-down surface. The PanelWindow is exactly the card's
    // rect plus the left gutter for the shadow's bleed: anchored to the top
    // bar edge (and the chip-side left edge), sized by the counted
    // panelHeight()/panelWidth(), and transparent. There is no scrim and no
    // backdrop catcher — the desktop stays interactive because only this
    // bar-edge strip is covered. Wayland surfaces are opaque to input, so the
    // gutter strip (window minus the card's rect) closes the panel; apps never
    // receive clicks through the card.
    // NOTE (family trade): a bounded surface cannot see clicks on the desktop
    // outside it, so the old "click anywhere outside closes" UX is retired in
    // favor of Esc, the Close button, or a click inside the gutter strip.
    PanelWindow {
        id: panel
        visible: uiAdapter.open
        screen: Quickshell.screens.length ? Quickshell.screens[0] : null
        implicitWidth: panelWidth()
        implicitHeight: panelHeight()
        color: "transparent"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; left: true }
        margins { top: panelTopMargin; left: 0 }

        Shortcut {
            sequence: "Esc"
            context: Qt.WindowShortcut
            onActivated: root.closeModal()
        }

        Item {
            id: panelItem
            anchors.fill: parent

            // Transparent click-catcher filling the bounded gutter strip: any
            // click inside the window but outside the card's rect dismisses.
            MouseArea {
                id: stripCatcher
                anchors.fill: panelItem
                z: -1
                onClicked: root.closeModal()
            }

            Rectangle {
                id: frameShadow
                anchors.centerIn: panelItem
                width: modalFrame.width
                height: modalFrame.height
                color: Qt.rgba(0, 0, 0, 0.55)
                radius: 0
                visible: modalFrame.visible
            }

            Rectangle {
                id: modalFrame
                // The card is inset from the window's left edge: the inset is
                // the window's own dismissal gutter (clicks there close) and
                // the shadow's bleed room. Layer surfaces are opaque to input
                // across their whole rect, so the inset must live inside.
                anchors.fill: panelItem
                anchors.leftMargin: root.panelGutterWidth
                color: "#0A0D16"
                border.color: root.statusColor(root.effectiveStatus)
                border.width: 1
                radius: 0

                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse.accepted = true
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 0
                    color: "transparent"
                    border.color: "#27304A"
                    border.width: 1
                }

                Flickable {
                    id: panelScroll
                    anchors.fill: parent
                    anchors.margins: root.panelChrome
                    contentWidth: width
                    contentHeight: panelContent.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: panelContent
                        width: panelScroll.width
                        spacing: root.shortViewport ? 10 : 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 58
                            color: "#0E1422"
                            border.color: "#82FB9C"
                            border.width: 1
                            radius: 0

                            Canvas {
                                id: orbitCanvas
                                anchors.fill: parent
                                anchors.margins: 7
                                property real phase: 0
                                onPhaseChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    var cx = width / 2
                                    var cy = height / 2
                                    ctx.lineWidth = 1.2
                                    ctx.strokeStyle = "#27304A"
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, 17, 0, Math.PI * 2)
                                    ctx.stroke()
                                    ctx.strokeStyle = "#1E7C71"
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, 11, -0.8, 2.5)
                                    ctx.stroke()
                                    ctx.strokeStyle = "#82FB9C"
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, 17, phase, phase + 0.9)
                                    ctx.stroke()
                                    var nodes = [[cx + 17 * Math.cos(phase), cy + 17 * Math.sin(phase)], [cx - 11, cy + 4], [cx + 3, cy - 11]]
                                    for (var index = 0; index < nodes.length; index++) {
                                        ctx.fillStyle = index === 0 ? "#F2C572" : "#85E1FB"
                                        ctx.beginPath()
                                        ctx.arc(nodes[index][0], nodes[index][1], index === 0 ? 2.5 : 1.7, 0, Math.PI * 2)
                                        ctx.fill()
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Row {
                                spacing: 8
                                Text {
                                    text: "BACKUPBAR"
                                    color: "#DDF7FF"
                                    font.family: root.textFont
                                    font.pixelSize: root.shortViewport ? 22 : 24
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                // Live dot: the panel is a live read-only view;
                                // the dot carries that at a glance (amber while
                                // a refresh runs, red on a source-level error).
                                Rectangle {
                                    id: liveDot
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: root.source.status === "error" ? "#FF6B7A"
                                        : (actionRunner.running || closeRunner.running) ? "#F2C572" : "#82FB9C"
                                }
                            }
                            // Like-for-like headline: the chip's job basis with
                            // an explicit overdue count next to it. Presenter-
                            // derived; the panel only renders it.
                            Text {
                                Layout.fillWidth: true
                                visible: !root.shortViewport
                                text: summary.headlineText || "--"
                                color: "#9CF7C2"
                                font.family: root.textFont
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.context.nextRunText ? ("next scheduled run  " + root.context.nextRunText + (root.context.nextRunLabel ? "  ·  " + root.context.nextRunLabel : "")) : "next scheduled run unavailable"
                                color: root.context.nextRunText ? "#85E1FB" : "#6A6E95"
                                font.family: root.textFont
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                        }

                        // Count chip: N observed systems on the same basis the
                        // presenter's headline uses. Stays on narrow screens;
                        // it is the compact replacement for the headline line.
                        Rectangle {
                            visible: root.systems.length > 0
                            implicitWidth: jobsChipText.implicitWidth + 8
                            implicitHeight: 18
                            color: "#121827"
                            border.color: "#2B3550"
                            border.width: 1
                            radius: 0
                            Text {
                                id: jobsChipText
                                anchors.centerIn: parent
                                text: (root.systems.length) + " observed"
                                color: "#9AA4BE"
                                font.family: root.textFont
                                font.pixelSize: 9
                            }
                        }

                        StatusBadge {
                            status: root.effectiveStatus
                            visible: !root.narrowWidth
                        }
                        ActionButton {
                            icon: root.refreshIcon
                            label: "Refresh"
                            onClicked: root.runBackupbar(["refresh"])
                        }
                        ActionButton {
                            icon: root.closeIcon
                            label: "Close"
                            accent: "#85E1FB"
                            onClicked: root.closeModal()
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: panelScroll.width >= 760 ? 4 : (panelScroll.width >= 460 ? 2 : 1)
                        rowSpacing: root.shortViewport ? 6 : 8
                        columnSpacing: 8

                        MetricTile {
                            label: "systems"
                            // Like-for-like with the chip (BB N/M): the tile
                            // carries the all-systems count; the overdue share
                            // lives in the detail line and the full headline
                            // sentence under the title. A long value in the
                            // big font clips at the tile border, so prose
                            // never goes in the value slot.
                            value: String(summary.systemCount || 0)
                            detail: (summary.healthyCount || 0) + " healthy · " + (summary.overdueCount || 0) + " overdue"
                            accent: (summary.overdueCount || 0) > 0 || (summary.criticalCount || 0) > 0 ? "#F2C572" : "#82FB9C"
                        }
                        MetricTile {
                            label: "next run"
                            value: root.context.nextRunText || "--"
                            detail: root.context.nextRunLabel || "no schedule observed"
                            accent: "#85E1FB"
                        }
                        MetricTile {
                            label: "latest good"
                            value: summary.latestGoodText || "--"
                            detail: "backup observation"
                            accent: "#85E1FB"
                        }
                        MetricTile {
                            label: "attention"
                            value: String(summary.attentionCount || 0)
                            detail: (summary.criticalCount || 0) + (summary.criticalCount === 1 ? " critical" : " critical") + " / " + (summary.overdueCount || 0) + (summary.overdueCount === 1 ? " overdue" : " overdue")
                            accent: (summary.attentionCount || 0) > 0 ? "#F2C572" : "#82FB9C"
                        }
                        MetricTile {
                            label: "storage peak"
                            value: summary.hottestPercent === null || summary.hottestPercent === undefined ? "--" : Number(summary.hottestPercent).toFixed(0) + "%"
                            detail: summary.hottestMount || "mounts unavailable"
                            accent: (summary.hottestPercent || 0) >= 85 ? "#F2C572" : "#C79CF7"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "BACKUP CONSTELLATION"
                                color: "#6A6E95"
                                font.family: root.textFont
                                font.pixelSize: 9
                                font.bold: true
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: "#242D44" }
                            Text {
                                text: (root.systems.length) + " observed"
                                color: "#6A6E95"
                                font.family: root.textFont
                                font.pixelSize: 8
                            }
                            Text {
                                // Visible overflow cue: bound directly to the
                                // list viewport so it tracks late model changes.
                                visible: jobsScroll.contentHeight > jobsScroll.height
                                text: "· scroll"
                                color: "#6A6E95"
                                font.family: root.textFont
                                font.pixelSize: 8
                            }
                        }

                        Flickable {
                            id: jobsScroll

                            Layout.fillWidth: true
                            // Three cards at full height, then scroll; shrinks
                            // near the floor so the pressure map stays visible.
                            Layout.preferredHeight: root.shortViewport ? 420 : 492
                            contentWidth: width
                            contentHeight: jobsGrid.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            GridLayout {
                                id: jobsGrid
                                width: jobsScroll.width
                                columns: jobsScroll.width >= 876 ? 3 : (jobsScroll.width >= 576 ? 2 : 1)
                                columnSpacing: 8
                                rowSpacing: 8
                                Repeater {
                                    model: root.systems
                                    delegate: BackupCard {}
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: root.systems.length === 0
                                text: "No backup jobs observed yet."
                                color: "#6A6E95"
                                font.family: root.textFont
                                font.pixelSize: 10
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "PRESSURE MAP"
                                color: "#6A6E95"
                                font.family: root.textFont
                                font.pixelSize: 9
                                font.bold: true
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: "#242D44" }
                            Text {
                                Layout.maximumWidth: jobsScroll.width / 2
                                text: (summary.storageWarningCount || 0) + (summary.storageWarningCount === 1 ? " mount over threshold" : " mounts over threshold")
                                color: (summary.storageWarningCount || 0) > 0 ? "#F2C572" : "#6A6E95"
                                font.family: root.textFont
                                font.pixelSize: 8
                            }
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: panelScroll.width >= 860 ? 3 : (panelScroll.width >= 560 ? 2 : 1)
                            rowSpacing: 8
                            columnSpacing: 8
                            Repeater {
                                model: root.storage
                                delegate: StorageRow {}
                                }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "OBSERVATION STREAM"
                            color: "#6A6E95"
                            font.family: root.textFont
                            font.pixelSize: 9
                            font.bold: true
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#242D44" }
                        Text {
                            text: snapshotAdapter.generatedAt ? snapshotAdapter.generatedAt.replace("T", " ").replace("Z", " UTC") : "waiting"
                            color: "#6A6E95"
                            font.family: root.textFont
                            font.pixelSize: 9
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.shortViewport ? 64 : 82
                        model: root.timeline
                        orientation: ListView.Horizontal
                        spacing: 8
                        clip: true
                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            required property var modelData
                            width: 190
                            height: 70
                            color: "#101522"
                            border.color: "#253057"
                            border.width: 1
                            radius: 0
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 3
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.label || "event"
                                        color: "#DDF7FF"
                                        font.family: root.textFont
                                        font.pixelSize: 10
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: modelData.timeText || "--"
                                        color: root.statusColor(modelData.status)
                                        font.family: root.textFont
                                        font.pixelSize: 8
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.detail || "no detail"
                                    color: "#8D9BB8"
                                    font.family: root.textFont
                                    font.pixelSize: 8
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.timeline.length === 0
                            text: "No observation events yet."
                            color: "#6A6E95"
                            font.family: root.textFont
                            font.pixelSize: 10
                        }
                    }

                        Text {
                            Layout.fillWidth: true
                            text: "Refresh reads existing telemetry only. It does not start, stop, prune, unlock, or repair a backup."
                            color: "#596582"
                            font.family: root.textFont
                            font.pixelSize: 8
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
