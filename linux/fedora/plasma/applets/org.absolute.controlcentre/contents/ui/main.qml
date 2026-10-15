// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// The Control Centre: the menu bar icon opens the Mac's grid of glass tiles with
// Wi-Fi, Bluetooth and Focus toggles and the Display and Sound sliders.
PlasmoidItem {
    id: root
    switchWidth: 0
    switchHeight: 0

    property bool wifiOn: false
    property bool bluetoothOn: false
    property bool focusOn: false
    property int volume: 50
    property int brightness: -1

    P5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            const out = (data["stdout"] || "").trim();
            if (sourceName.indexOf("nmcli radio wifi") === 0 && sourceName.indexOf(" on") < 0 && sourceName.indexOf(" off") < 0) {
                root.wifiOn = out === "enabled";
            } else if (sourceName.indexOf("bluetoothctl show") === 0) {
                root.bluetoothOn = out.indexOf("Powered: yes") >= 0;
            } else if (sourceName.indexOf("wpctl get-volume") === 0) {
                const match = out.match(/Volume: ([0-9.]+)/);
                if (match) { root.volume = Math.round(parseFloat(match[1]) * 100); }
            } else if (sourceName.indexOf("kreadconfig6") === 0) {
                root.focusOn = out.length > 0 && out !== "0";
            } else if (sourceName.indexOf("brightnessctl") === 0) {
                const value = parseInt(out, 10);
                root.brightness = isNaN(value) ? -1 : value;
            }
            disconnectSource(sourceName);
        }
        function run(command) { connectSource(command); }
    }

    function poll() {
        shell.run("nmcli radio wifi");
        shell.run("bluetoothctl show");
        shell.run("wpctl get-volume @DEFAULT_AUDIO_SINK@");
        shell.run("kreadconfig6 --file plasmanotifyrc --group DoNotDisturb --key Until");
        shell.run("brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d %");
    }
    Component.onCompleted: poll()
    Timer { interval: 5000; running: root.expanded; repeat: true; onTriggered: root.poll() }
    onExpandedChanged: if (expanded) { poll(); }

    compactRepresentation: MouseArea {
        Layout.minimumWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small
            height: width
            source: Qt.resolvedUrl("../icons/controlcentre.svg")
            color: Kirigami.Theme.textColor
            isMask: true
        }
    }

    fullRepresentation: Item {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: column.implicitHeight + Kirigami.Units.largeSpacing * 2
        Layout.minimumWidth: Layout.preferredWidth
        Layout.minimumHeight: Layout.preferredHeight

        component Tile: Rectangle {
            property string icon
            property string title
            property string subtitle: ""
            property bool active: false
            signal toggled()
            radius: 14
            color: active ? Qt.rgba(0.20, 0.47, 0.95, 0.95) : Qt.rgba(1, 1, 1, 0.10)
            implicitHeight: 56
            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                Rectangle {
                    width: 32; height: 32; radius: 16
                    color: active ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.14)
                    Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: icon; color: "white"; isMask: true }
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    PlasmaComponents.Label { text: title; font.weight: Font.DemiBold; color: "white"; elide: Text.ElideRight; Layout.fillWidth: true }
                    PlasmaComponents.Label { text: subtitle; visible: subtitle.length > 0; font.pointSize: Kirigami.Theme.smallFont.pointSize; color: Qt.rgba(1, 1, 1, 0.75); elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: parent.toggled() }
        }

        component SliderRow: ColumnLayout {
            property string title
            property string icon
            property alias value: slider.value
            property bool enabled: true
            signal moved(real value)
            spacing: 4
            PlasmaComponents.Label { text: title; font.weight: Font.DemiBold; color: "white" }
            RowLayout {
                spacing: 8
                Kirigami.Icon { width: 16; height: 16; source: icon; color: "white"; isMask: true }
                QQC2.Slider {
                    id: slider
                    Layout.fillWidth: true
                    from: 0; to: 100; stepSize: 1
                    enabled: parent.parent.enabled
                    onMoved: parent.parent.moved(value)
                }
            }
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            GridLayout {
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.largeSpacing
                Layout.fillWidth: true
                Tile {
                    Layout.fillWidth: true
                    icon: "network-wireless"; title: "Wi-Fi"; subtitle: root.wifiOn ? "On" : "Off"; active: root.wifiOn
                    onToggled: { shell.run("nmcli radio wifi " + (root.wifiOn ? "off" : "on")); root.wifiOn = !root.wifiOn; }
                }
                Tile {
                    Layout.fillWidth: true
                    icon: "network-bluetooth"; title: "Bluetooth"; subtitle: root.bluetoothOn ? "On" : "Off"; active: root.bluetoothOn
                    onToggled: { shell.run("bluetoothctl power " + (root.bluetoothOn ? "off" : "on")); root.bluetoothOn = !root.bluetoothOn; }
                }
                Tile {
                    Layout.fillWidth: true
                    icon: "notifications-disabled"; title: "Focus"; subtitle: root.focusOn ? "Do Not Disturb" : "Off"; active: root.focusOn
                    onToggled: {
                        const until = root.focusOn ? "" : "2099,1,1,0,0,0";
                        shell.run("kwriteconfig6 --notify --file plasmanotifyrc --group DoNotDisturb --key Until '" + until + "'");
                        root.focusOn = !root.focusOn;
                    }
                }
                Tile {
                    Layout.fillWidth: true
                    icon: "preferences-desktop-theme-global"; title: "Dark"; subtitle: "Always"; active: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.10)
                implicitHeight: sliders.implicitHeight + 24
                ColumnLayout {
                    id: sliders
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    SliderRow {
                        Layout.fillWidth: true
                        title: "Display"; icon: "video-display-brightness"
                        enabled: root.brightness >= 0
                        value: root.brightness >= 0 ? root.brightness : 100
                        onMoved: (v) => shell.run("brightnessctl set " + Math.round(v) + "%")
                    }
                    SliderRow {
                        Layout.fillWidth: true
                        title: "Sound"; icon: "audio-volume-high"
                        value: root.volume
                        onMoved: (v) => shell.run("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + Math.round(v) + "%")
                    }
                }
            }
        }
    }
}
