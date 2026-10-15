// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.milou as Milou
import org.kde.kirigami as Kirigami

// Spotlight: a wide field in a glass panel a fifth of the way down the screen; results
// grow below it, Enter runs the chosen one, Escape dismisses.
Window {
    id: root
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint
    title: "Spotlight"
    width: 680
    height: panel.height

    readonly property int fieldHeight: 60
    readonly property int rowHeight: 44
    readonly property int maxRows: 9
    readonly property int radius: 18

    Milou.ResultsModel {
        id: results
        queryString: field.text
        limit: 15
        onRowsInserted: list.currentIndex = 0
        onModelReset: list.currentIndex = 0
    }

    function run() {
        if (list.count === 0) {
            return;
        }
        const index = Math.max(0, list.currentIndex);
        if (results.run(results.index(index, 0))) {
            field.text = "";
            spotlight.hide();
        }
    }

    Connections {
        target: spotlight
        function onRequestFocus() { field.forceActiveFocus(); field.selectAll(); }
        function onShownChanged() { if (!spotlight.shown) { field.text = ""; } }
    }

    Rectangle {
        id: panel
        width: root.width
        height: root.fieldHeight + (list.count > 0 ? Math.min(list.count, root.maxRows) * root.rowHeight + 10 : 0)
        radius: root.radius
        color: Qt.rgba(0.11, 0.11, 0.14, 0.74)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
        onWidthChanged: spotlight.setGlass(0, 0, width, height, radius)
        onHeightChanged: spotlight.setGlass(0, 0, width, height, radius)
        Component.onCompleted: spotlight.setGlass(0, 0, width, height, radius)

        RowLayout {
            x: 20
            width: parent.width - 40
            height: root.fieldHeight
            spacing: 14
            Kirigami.Icon {
                source: "search"
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                color: Qt.rgba(1, 1, 1, 0.85)
                isMask: true
            }
            QQC2.TextField {
                id: field
                Layout.fillWidth: true
                Layout.fillHeight: true
                placeholderText: "Spotlight Search"
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                color: "white"
                font.pixelSize: 26
                font.weight: Font.Normal
                background: Item {}
                verticalAlignment: TextInput.AlignVCenter
                Keys.onDownPressed: list.incrementCurrentIndex()
                Keys.onUpPressed: list.decrementCurrentIndex()
                Keys.onReturnPressed: root.run()
                Keys.onEnterPressed: root.run()
                Keys.onEscapePressed: spotlight.hide()
            }
        }

        Rectangle {
            x: 14
            y: root.fieldHeight
            width: parent.width - 28
            height: 1
            visible: list.count > 0
            color: Qt.rgba(1, 1, 1, 0.12)
        }

        ListView {
            id: list
            x: 8
            y: root.fieldHeight + 6
            width: parent.width - 16
            height: Math.max(0, panel.height - root.fieldHeight - 10)
            clip: true
            model: results
            currentIndex: 0
            highlightMoveDuration: 0
            keyNavigationEnabled: false
            delegate: Rectangle {
                id: row
                required property int index
                required property var model
                width: list.width
                height: root.rowHeight
                radius: 10
                color: ListView.isCurrentItem ? Qt.rgba(0.20, 0.47, 0.95, 0.92) : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 14
                    spacing: 12
                    Kirigami.Icon {
                        source: row.model.decoration
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                    }
                    Text {
                        text: row.model.display
                        color: "white"
                        font.pixelSize: 16
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: String(row.model.subtext || "")
                        visible: text.length > 0
                        color: row.ListView.isCurrentItem ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.5)
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        Layout.maximumWidth: list.width * 0.4
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: list.currentIndex = row.index
                    onClicked: { list.currentIndex = row.index; root.run(); }
                }
            }
        }
    }
}
