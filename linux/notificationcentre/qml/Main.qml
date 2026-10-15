// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.notificationmanager as NotificationManager

// Notification Centre: this process owns the notification service. New notifications
// appear as cards at the top right (the popups window) and stay in the history that
// slides in at the right edge when the clock is clicked (this window).
Window {
    id: root
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint
    title: "Notification Centre"
    width: 380

    readonly property color cardColor: Qt.rgba(0.16, 0.16, 0.18, 0.92)
    readonly property color textColor: Qt.rgba(1, 1, 1, 0.92)
    readonly property color dimColor: Qt.rgba(1, 1, 1, 0.55)

    function timeAgo(date) {
        const seconds = Math.max(0, (Date.now() - date.getTime()) / 1000);
        if (seconds < 60) { return "now"; }
        if (seconds < 3600) { return Math.floor(seconds / 60) + "m ago"; }
        if (seconds < 86400) { return Math.floor(seconds / 3600) + "h ago"; }
        return Qt.formatDate(date, "ddd d MMM");
    }

    // History: everything, grouped by application, newest first.
    NotificationManager.Notifications {
        id: history
        showExpired: true
        showDismissed: true
        showJobs: false
        groupMode: NotificationManager.Notifications.GroupApplicationsFlat
        groupLimit: 4
        expandUnread: true
        sortMode: NotificationManager.Notifications.SortByDate
        urgencies: NotificationManager.Notifications.LowUrgency | NotificationManager.Notifications.NormalUrgency | NotificationManager.Notifications.CriticalUrgency
        onCountChanged: console.warn("history count", count, "expired", expiredNotificationsCount, "server valid", NotificationManager.Server.valid)
    }

    // Popups: the newest few that have not expired or been dismissed.
    NotificationManager.Notifications {
        id: popups
        showExpired: false
        showDismissed: false
        showJobs: true
        showAddedDuringInhibition: false
        groupMode: NotificationManager.Notifications.GroupDisabled
        sortMode: NotificationManager.Notifications.SortByDate
        limit: 3
        urgencies: NotificationManager.Notifications.LowUrgency | NotificationManager.Notifications.NormalUrgency | NotificationManager.Notifications.CriticalUrgency
        onCountChanged: console.warn("popups count", count)
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.09, 0.09, 0.11, 0.82)
        Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.08) }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            anchors.topMargin: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: Qt.formatDate(new Date(), "dddd d MMMM")
                    color: root.textColor
                    font.pixelSize: 20
                    font.weight: Font.Bold
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    visible: history.count > 0
                    width: clearLabel.implicitWidth + 20
                    height: 24
                    radius: 12
                    color: clearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)
                    Text { id: clearLabel; anchors.centerIn: parent; text: "Clear All"; color: root.textColor; font.pixelSize: 12; font.weight: Font.Medium }
                    MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; onClicked: history.clear(NotificationManager.Notifications.ClearExpired) }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 160
                visible: history.count === 0
                text: "No Notifications"
                color: root.dimColor
                font.pixelSize: 17
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: history
                spacing: 6
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    required property var model
                    required property int index
                    width: list.width
                    height: model.isGroup ? 30 : card.height
                    // Group header: application icon and name, a clear button.
                    RowLayout {
                        visible: model.isGroup
                        anchors.fill: parent
                        spacing: 8
                        Kirigami.Icon { Layout.preferredWidth: 18; Layout.preferredHeight: 18; source: model.applicationIconName || model.iconName || "dialog-information" }
                        Text { text: model.applicationName; color: root.textColor; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 20; height: 20; radius: 10
                            color: groupClose.containsMouse ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.14)
                            Text { anchors.centerIn: parent; text: "×"; color: root.textColor; font.pixelSize: 14 }
                            MouseArea { id: groupClose; anchors.fill: parent; hoverEnabled: true; onClicked: history.close(history.index(index, 0)) }
                        }
                    }
                    // Notification card.
                    Rectangle {
                        id: card
                        visible: !model.isGroup
                        width: parent.width
                        height: visible ? Math.max(58, cardColumn.implicitHeight + 20) : 0
                        radius: 12
                        color: cardMouse.containsMouse ? Qt.lighter(root.cardColor, 1.15) : root.cardColor
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10
                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                source: model.image ? model.image : (model.iconName || model.applicationIconName || "dialog-information")
                            }
                            ColumnLayout {
                                id: cardColumn
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { Layout.fillWidth: true; text: model.summary || model.applicationName; color: root.textColor; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                    Text { text: root.timeAgo(model.created); color: root.dimColor; font.pixelSize: 11 }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: model.body
                                    textFormat: Text.StyledText
                                    color: Qt.rgba(1, 1, 1, 0.8)
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (model.hasDefaultAction) { history.invokeDefaultAction(history.index(index, 0), NotificationManager.Notifications.Close); }
                                else { history.close(history.index(index, 0)); }
                            }
                        }
                    }
                }
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: centre.hide() }
    Component.onCompleted: console.warn("server valid at start", NotificationManager.Server.valid, "owner", NotificationManager.Server.currentOwner)

    // The popups window at the top right.
    Window {
        id: popupWindow
        objectName: "popups"
        visible: popups.count > 0
        color: "transparent"
        flags: Qt.FramelessWindowHint
        title: "Notifications"
        width: 380
        height: Math.max(1, popupColumn.implicitHeight + 16)

        Column {
            id: popupColumn
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 8
            Repeater {
                model: popups
                delegate: Rectangle {
                    id: popup
                    required property var model
                    required property int index
                    width: popupColumn.width
                    height: Math.max(66, popupContent.implicitHeight + 24)
                    radius: 14
                    color: Qt.rgba(0.14, 0.14, 0.16, 0.94)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    Component.onCompleted: popups.startTimeout(popups.index(index, 0))
                    RowLayout {
                        id: popupContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        Kirigami.Icon {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            source: popup.model.image ? popup.model.image : (popup.model.iconName || popup.model.applicationIconName || "dialog-information")
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { Layout.fillWidth: true; text: popup.model.applicationName; color: root.dimColor; font.pixelSize: 11; font.weight: Font.Medium; elide: Text.ElideRight; font.capitalization: Font.AllUppercase }
                            Text { Layout.fillWidth: true; text: popup.model.summary; color: root.textColor; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: popup.model.type === NotificationManager.Notifications.JobType ? (popup.model.percentage + "%") : popup.model.body
                                textFormat: Text.StyledText
                                color: Qt.rgba(1, 1, 1, 0.8)
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                            // Action buttons, as the Mac shows them under the text.
                            Flow {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 6
                                visible: popup.model.actionNames && popup.model.actionNames.length > 0
                                Repeater {
                                    model: popup.model.actionLabels
                                    delegate: Rectangle {
                                        required property string modelData
                                        required property int index
                                        width: actionLabel.implicitWidth + 18
                                        height: 22
                                        radius: 7
                                        color: actionMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.14)
                                        Text { id: actionLabel; anchors.centerIn: parent; text: modelData; color: root.textColor; font.pixelSize: 11; font.weight: Font.Medium }
                                        MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; onClicked: popups.invokeAction(popups.index(popup.index, 0), popup.model.actionNames[index], NotificationManager.Notifications.Close) }
                                    }
                                }
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        z: -1
                        onEntered: popups.stopTimeout(popups.index(popup.index, 0))
                        onExited: popups.startTimeout(popups.index(popup.index, 0))
                        onClicked: {
                            if (popup.model.hasDefaultAction) { popups.invokeDefaultAction(popups.index(popup.index, 0), NotificationManager.Notifications.Close); }
                            else { popups.expire(popups.index(popup.index, 0)); }
                        }
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        width: 18; height: 18; radius: 9
                        visible: popupClose.containsMouse || popupHover.containsMouse
                        color: Qt.rgba(1, 1, 1, 0.2)
                        Text { anchors.centerIn: parent; text: "×"; color: root.textColor; font.pixelSize: 12 }
                        MouseArea { id: popupClose; anchors.fill: parent; hoverEnabled: true; onClicked: popups.close(popups.index(popup.index, 0)) }
                    }
                    MouseArea { id: popupHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton; z: -2 }
                }
            }
        }
    }
}
