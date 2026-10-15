// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// The magnifier at the right of the menu bar: one click opens the search panel.
PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Layout.minimumWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.fillHeight: true

    Kirigami.Icon {
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.small
        height: width
        source: "search"
        color: Kirigami.Theme.textColor
        isMask: true
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName) => disconnectSource(sourceName)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: executable.connectSource("sh -c 'if [ -x \"$HOME/.local/bin/absolute-spotlight\" ]; then \"$HOME/.local/bin/absolute-spotlight\" --toggle; else busctl --user call org.kde.krunner /App org.kde.krunner.App display; fi'")
    }
}
