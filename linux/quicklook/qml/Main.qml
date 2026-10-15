// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Pdf
import QtMultimedia
import org.kde.kirigami as Kirigami

// Quick Look: a rounded dark panel with the file's name on top, an "Open with" button
// on the right, and the preview filling the rest. Space or Escape closes it, the
// arrow keys move through the selection, Return opens the file.
Window {
    id: root
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.Tool
    title: quicklook.fileName
    width: Math.round(Screen.width * 0.62)
    height: Math.round(Screen.height * 0.78)
    minimumWidth: 560
    minimumHeight: 400

    readonly property int radius: 12

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: root.radius
        color: Qt.rgba(0.12, 0.12, 0.13, 0.96)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        // Header: name centred, Open button on the right.
        Item {
            id: header
            width: parent.width
            height: 44
            Text {
                anchors.centerIn: parent
                width: parent.width - 260
                text: quicklook.fileName
                color: Qt.rgba(1, 1, 1, 0.9)
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: quicklook.files.length > 1
                text: (quicklook.index + 1) + " of " + quicklook.files.length
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 12
            }
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: quicklook.openWith.length > 0
                width: openLabel.implicitWidth + 24
                height: 26
                radius: 7
                color: openMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.14)
                Text {
                    id: openLabel
                    anchors.centerIn: parent
                    text: "Open with " + quicklook.openWith
                    color: "white"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
                MouseArea { id: openMouse; anchors.fill: parent; hoverEnabled: true; onClicked: quicklook.open() }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
        }

        // Preview area.
        Item {
            id: content
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            clip: true

            Loader {
                anchors.fill: parent
                sourceComponent: {
                    switch (quicklook.kind) {
                    case "image": return imageView;
                    case "text": return textView;
                    case "pdf": return pdfView;
                    case "video": return videoView;
                    case "audio": return audioView;
                    default: return iconView;
                    }
                }
            }
        }
    }

    Component {
        id: imageView
        Image {
            source: quicklook.url
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            autoTransform: true
        }
    }

    Component {
        id: textView
        QQC2.ScrollView {
            QQC2.TextArea {
                readOnly: true
                text: quicklook.text
                color: Qt.rgba(1, 1, 1, 0.88)
                font.family: "JetBrains Mono"
                font.pixelSize: 13
                wrapMode: TextEdit.NoWrap
                selectByMouse: true
                background: Rectangle { color: Qt.rgba(0, 0, 0, 0.25); radius: 8 }
                leftPadding: 14
                topPadding: 12
            }
        }
    }

    Component {
        id: pdfView
        PdfMultiPageView {
            document: PdfDocument { source: quicklook.url }
        }
    }

    Component {
        id: videoView
        Item {
            MediaPlayer {
                id: player
                source: quicklook.url
                videoOutput: output
                audioOutput: AudioOutput {}
                Component.onCompleted: play()
            }
            VideoOutput { id: output; anchors.fill: parent }
            MouseArea { anchors.fill: parent; onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
        }
    }

    Component {
        id: audioView
        Item {
            MediaPlayer {
                id: audio
                source: quicklook.url
                audioOutput: AudioOutput {}
                Component.onCompleted: play()
            }
            Column {
                anchors.centerIn: parent
                spacing: 16
                Kirigami.Icon { anchors.horizontalCenter: parent.horizontalCenter; width: 160; height: 160; source: quicklook.iconName }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: quicklook.details; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 13 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: audio.playbackState === MediaPlayer.PlayingState ? "Playing" : "Paused"
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 12
                }
            }
            MouseArea { anchors.fill: parent; onClicked: audio.playbackState === MediaPlayer.PlayingState ? audio.pause() : audio.play() }
        }
    }

    Component {
        id: iconView
        Column {
            anchors.centerIn: parent
            spacing: 14
            Kirigami.Icon { anchors.horizontalCenter: parent.horizontalCenter; width: 192; height: 192; source: quicklook.iconName }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: quicklook.fileName
                color: Qt.rgba(1, 1, 1, 0.9)
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: quicklook.details; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 13 }
        }
    }

    Shortcut { sequences: ["Escape", "Space"]; onActivated: quicklook.close() }
    Shortcut { sequence: "Right"; onActivated: quicklook.next() }
    Shortcut { sequence: "Left"; onActivated: quicklook.previous() }
    Shortcut { sequences: ["Return", "Enter"]; onActivated: quicklook.open() }
}
