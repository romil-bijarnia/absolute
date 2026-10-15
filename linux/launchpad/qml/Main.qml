// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Launchpad: the desktop blurred and darkened, a search field at the top, pages of
// seven by five application tiles, page dots at the bottom. Escape or a click on
// the background dismisses it; typing filters.
Window {
    id: root
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint
    title: "Launchpad"

    readonly property int columns: 7
    readonly property int rows: 5
    readonly property int perPage: columns * rows
    property int pageCount: Math.max(1, Math.ceil(appCount / perPage))
    property int appCount: 0
    // Bumped whenever the filtered model changes so tile bindings re-read it.
    property int generation: 0

    function refreshCount() {
        generation += 1;
        appCount = launchpad.apps.rowCount();
        pageCount = Math.max(1, Math.ceil(appCount / perPage));
        if (pages.currentIndex >= pageCount) {
            pages.currentIndex = 0;
        }
    }
    Connections {
        target: launchpad.apps
        function onRowsInserted() { root.refreshCount(); }
        function onRowsRemoved() { root.refreshCount(); }
        function onModelReset() { root.refreshCount(); }
        function onLayoutChanged() { root.refreshCount(); }
    }
    Connections {
        target: launchpad
        function onRequestFocus() { search.forceActiveFocus(); search.selectAll(); root.refreshCount(); }
        function onShownChanged() { if (!launchpad.shown) { search.text = ""; pages.currentIndex = 0; } }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.02, 0.05, 0.45)
        MouseArea {
            anchors.fill: parent
            onClicked: launchpad.hide()
        }
        Keys.onEscapePressed: launchpad.hide()
    }

    // Search field, centred near the top.
    Rectangle {
        id: searchBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.06)
        width: 300
        height: 36
        radius: 10
        color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.25)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8
            Kirigami.Icon {
                source: "search"
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                color: Qt.rgba(1, 1, 1, 0.8)
                isMask: true
            }
            QQC2.TextField {
                id: search
                Layout.fillWidth: true
                Layout.fillHeight: true
                placeholderText: "Search"
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.5)
                color: "white"
                font.pixelSize: 15
                background: Item {}
                onTextChanged: { launchpad.setFilter(text); root.refreshCount(); pages.currentIndex = 0; }
                Keys.onEscapePressed: launchpad.hide()
                Keys.onReturnPressed: if (root.appCount > 0) { launchpad.launch(0); }
                Keys.onLeftPressed: if (text.length === 0) { pages.decrementCurrentIndex(); }
                Keys.onRightPressed: if (text.length === 0) { pages.incrementCurrentIndex(); }
            }
        }
    }

    // Pages of tiles.
    readonly property int gridWidth: Math.min(root.width - 160, 1180)
    readonly property int cellWidth: Math.floor(gridWidth / columns)
    readonly property int cellHeight: Math.floor((root.height * 0.72) / rows)
    readonly property int iconSize: Math.min(96, Math.floor(cellHeight * 0.5))

    QQC2.SwipeView {
        id: pages
        anchors.horizontalCenter: parent.horizontalCenter
        y: searchBox.y + searchBox.height + Math.round(root.height * 0.05)
        width: root.gridWidth
        height: root.cellHeight * root.rows
        clip: true
        // A wheel or two-finger swipe flips one page per notch, with a short rest between.
        WheelHandler {
            property int rest: 0
            onWheel: (event) => {
                const delta = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y) ? event.angleDelta.x : event.angleDelta.y;
                if (wheelRest.running || Math.abs(delta) < 30) { return; }
                if (delta < 0) { pages.incrementCurrentIndex(); } else { pages.decrementCurrentIndex(); }
                wheelRest.restart();
            }
        }
        Timer { id: wheelRest; interval: 350 }
        Repeater {
            model: root.pageCount
            Item {
                id: page
                required property int index
                Grid {
                    columns: root.columns
                    rows: root.rows
                    Repeater {
                        model: Math.max(0, Math.min(root.perPage, root.appCount - index * root.perPage))
                        Item {
                            required property int index
                            readonly property int row: page.index * root.perPage + index
                            width: root.cellWidth
                            height: root.cellHeight
                            Column {
                                anchors.centerIn: parent
                                spacing: 8
                                Kirigami.Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: root.iconSize
                                    height: root.iconSize
                                    source: { root.generation; return launchpad.apps.data(launchpad.apps.index(row, 0), 258); }
                                    scale: tileMouse.pressed ? 0.92 : 1
                                    Behavior on scale { NumberAnimation { duration: 80 } }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: root.cellWidth - 16
                                    text: { root.generation; return launchpad.apps.data(launchpad.apps.index(row, 0), 257); }
                                    color: "white"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    style: Text.Raised
                                    styleColor: Qt.rgba(0, 0, 0, 0.5)
                                }
                            }
                            MouseArea {
                                id: tileMouse
                                anchors.fill: parent
                                onClicked: launchpad.launch(row)
                            }
                        }
                    }
                }
            }
        }
    }

    // Page dots.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: pages.y + pages.height + Math.round(root.height * 0.03)
        spacing: 10
        Repeater {
            model: root.pageCount
            Rectangle {
                required property int index
                width: 8; height: 8; radius: 4
                color: index === pages.currentIndex ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.35)
                MouseArea { anchors.fill: parent; onClicked: pages.currentIndex = parent.index }
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: launchpad.hide() }
}
