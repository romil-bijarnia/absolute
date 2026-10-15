// SPDX-License-Identifier: MIT
import QtQuick
import org.kde.kirigami as Kirigami

// One Dock tile: its span along the bar comes from the magnification of its two
// edges, it sits on the glass baseline, grows upward, bounces while its application
// starts, carries the running dot and shows its name above when hovered.
Item {
    id: tile
    required property int slot
    property var icon
    property string label: ""
    property bool running: false
    property bool active: false
    property bool startup: false
    readonly property alias iconItem: iconItem
    signal clicked()
    signal rightClicked()

    x: root.tileStart(slot)
    width: root.tileEnd(slot) - x
    height: width
    y: root.baseline - height + bounceOffset

    property real bounceOffset: 0
    SequentialAnimation {
        running: tile.startup
        loops: Animation.Infinite
        NumberAnimation { target: tile; property: "bounceOffset"; to: -root.tile * 0.55; duration: 260; easing.type: Easing.OutQuad }
        NumberAnimation { target: tile; property: "bounceOffset"; to: 0; duration: 260; easing.type: Easing.InQuad }
        PauseAnimation { duration: 180 }
    }
    onStartupChanged: if (!startup) { bounceOffset = 0; }

    Kirigami.Icon {
        id: iconItem
        anchors.fill: parent
        source: tile.icon
        smooth: true
    }

    // Running dot below the icon, centred in the glass padding.
    Rectangle {
        visible: tile.running
        width: Math.max(3, Math.round(root.tile * 0.065))
        height: width
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.85)
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height + Math.round((root.pad - height) / 2) - tile.bounceOffset
    }

    // Name label above the tile while hovered.
    Rectangle {
        visible: hover.hovered && tile.label.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: -height - Math.round(root.tile * 0.2)
        width: labelText.implicitWidth + 20
        height: labelText.implicitHeight + 10
        radius: 6
        color: Qt.rgba(0.11, 0.11, 0.13, 0.92)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)
        Text {
            id: labelText
            anchors.centerIn: parent
            text: tile.label
            color: "white"
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    HoverHandler { id: hover }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: tile.clicked()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: tile.rightClicked()
    }
}
