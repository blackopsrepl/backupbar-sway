import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

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
    property real nowMilliseconds: Date.now()
    property var viewData: snapshotAdapter.view && snapshotAdapter.view.summary ? snapshotAdapter.view : ({ summary: {}, systems: [], storage: [], timeline: [] })
    property var summary: viewData.summary || ({})
    property var systems: viewData.systems || []
    property var storage: viewData.storage || []
    property var timeline: viewData.timeline || []
    property var source: viewData.source || ({})
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

    function systemDetail(system) {
        if (!system) {
            return ""
        }
        var metrics = system.metrics || ({})
        if (metrics.snapshotCount !== undefined) {
            return metrics.snapshotCount + " snapshots"
        }
        if (metrics.allArchives) {
            return metrics.allArchives.replace("All archives:", "archives:")
        }
        return system.detail || system.coverage || "no detail"
    }

    function reloadState() {
        snapshotFile.reload()
        uiFile.reload()
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

    component StatusBadge: Rectangle {
        property string status: "unknown"
        property color accent: root.statusColor(status)
        implicitWidth: badgeText.implicitWidth + 20
        implicitHeight: 24
        color: Qt.rgba(accent.r, accent.g, accent.b, 0.12)
        border.color: accent
        border.width: 1
         radius: 0

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: parent.status.toUpperCase()
            color: parent.accent
            font.family: root.textFont
            font.pixelSize: 9
            font.bold: true
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

    PanelWindow {
        id: modal
        visible: uiAdapter.open
        screen: Quickshell.screens.length ? Quickshell.screens[0] : null
        implicitWidth: screen ? screen.width : 1200
        implicitHeight: screen ? screen.height : 820
        color: "transparent"
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        margins { top: 0; bottom: 0; left: 0; right: 0 }

        Shortcut {
            sequence: "Esc"
            context: Qt.WindowShortcut
            onActivated: root.closeModal()
        }

        Item {
            anchors.fill: parent
            Rectangle {
                anchors.fill: parent
                color: "#050711"
                opacity: 0.78
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.closeModal()
            }

            Rectangle {
                id: card
                width: Math.min(1120, Math.max(340, modal.width - 36))
                height: Math.min(820, Math.max(620, modal.height - 30))
                anchors.centerIn: parent
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
                    anchors.margins: 17
                    contentWidth: width
                    contentHeight: panelContent.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: panelContent
                        width: panelScroll.width
                        spacing: 12

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
                            Text {
                                Layout.fillWidth: true
                                text: "BACKUPBAR"
                                color: "#DDF7FF"
                                font.family: root.textFont
                                font.pixelSize: 24
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "live backup telemetry  /  no-touch observer"
                                color: "#9CF7C2"
                                font.family: root.textFont
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        StatusBadge { status: root.effectiveStatus }
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
                        rowSpacing: 8
                        columnSpacing: 8
                        MetricTile {
                            label: "systems healthy"
                            value: String(summary.healthyCount || 0)
                            detail: (summary.systemCount || 0) + " observed"
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
                            detail: (summary.criticalCount || 0) + " critical"
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
                        Text {
                            text: "BACKUP CONSTELLATION"
                            color: "#6A6E95"
                            font.family: root.textFont
                            font.pixelSize: 9
                            font.bold: true
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: panelScroll.width >= 860 ? 3 : (panelScroll.width >= 560 ? 2 : 1)
                            rowSpacing: 8
                            columnSpacing: 8
                            Repeater {
                                model: root.systems
                                delegate: BackupCard {}
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
                                text: (summary.storageWarningCount || 0) + " mounts over threshold"
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
                        Layout.preferredHeight: 82
                        model: root.timeline
                        orientation: ListView.Horizontal
                        spacing: 8
                        clip: true
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
