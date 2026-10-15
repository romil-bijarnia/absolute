// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// The clock at the right end of the menu bar, in the Mac's form ("Thu 15 Oct  8:44 PM").
// One click opens Notification Centre.
PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Layout.minimumWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.fillHeight: true

    function text() {
        const now = new Date();
        return Qt.formatDateTime(now, "ddd d MMM") + "  " + Qt.formatTime(now, "h:mm AP");
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text()
        color: Kirigami.Theme.textColor
        font.family: Kirigami.Theme.defaultFont.family
        font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.1)
        font.weight: Font.Medium
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: label.text = root.text()
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName) => disconnectSource(sourceName)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: executable.connectSource("sh -c 'if [ -x \"$HOME/.local/bin/absolute-notificationcentre\" ]; then \"$HOME/.local/bin/absolute-notificationcentre\" --toggle; fi'")
    }
}
