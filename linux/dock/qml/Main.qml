// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami
import "Magnification.js" as Mag

Window {
    id: root
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint
    title: "Absolute Dock"

    // Sizes in logical pixels, from the configuration the Mac's own Dock keys use.
    readonly property int tile: dockHost.tileSize
    readonly property int large: dockHost.magnification ? Math.max(dockHost.largeSize, dockHost.tileSize) : dockHost.tileSize
    readonly property int spacing: Math.round(tile * 0.125)
    readonly property int pad: Math.round(tile * 0.17)
    readonly property int bottomMargin: Math.round(tile * 0.12)
    readonly property int glassHeight: tile + 2 * pad
    readonly property int glassRadius: Math.round(glassHeight * 0.28)
    readonly property int headroom: large + Math.round(tile * 0.75)
    height: headroom + glassHeight + bottomMargin

    // The fish: 0 at rest, 1 fully magnified, ramping linearly over the measured duration.
    property real fish: 0
    property real center: 0
    Behavior on fish {
        NumberAnimation { duration: Mag.rampDuration(root.large - root.tile); easing.type: Easing.Linear }
    }

    // Unmagnified layout: slots left to right. The left section is the task tiles with
    // Launchpad in slot 1; the right section, after the separator, holds Downloads and Trash.
    readonly property int leftCount: Math.max(taskRepeater.count, 1) + 1
    readonly property int rightCount: 2
    readonly property int slotCount: leftCount + rightCount
    readonly property int separatorWidth: Math.round(tile * 0.4)
    readonly property real barLength: slotCount * tile + (slotCount - 1) * spacing + separatorWidth
    readonly property real barOrigin: Math.round((width - barLength) / 2)
    readonly property real baseline: height - bottomMargin - pad
    function slotStart(slot) {
        return barOrigin + slot * (tile + spacing) + (slot >= leftCount ? separatorWidth : 0);
    }
    function tileStart(slot) {
        return Mag.displace(slotStart(slot), center, tile, large, fish);
    }
    function tileEnd(slot) {
        return Mag.displace(slotStart(slot) + tile, center, tile, large, fish);
    }
    function taskSlot(index) {
        return index === 0 ? 0 : index + 1;
    }
    readonly property real glassX: tileStart(0) - pad
    readonly property real glassW: tileEnd(slotCount - 1) + pad - glassX
    readonly property real glassY: height - bottomMargin - glassHeight

    onGlassXChanged: syncGlass()
    onGlassWChanged: syncGlass()
    onHeightChanged: syncGlass()
    function syncGlass() {
        if (width > 0) {
            dockHost.setGlass(glassX, glassY, glassW, glassHeight, glassRadius);
        }
    }
    Component.onCompleted: dockHost.setExclusiveZone(glassHeight + bottomMargin)

    TaskManager.VirtualDesktopInfo { id: virtualDesktopInfo }
    TaskManager.ActivityInfo { id: activityInfo }
    TaskManager.TasksModel {
        id: tasksModel
        virtualDesktop: virtualDesktopInfo.currentDesktop
        activity: activityInfo.currentActivity
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
        filterMinimized: false
        sortMode: TaskManager.TasksModel.SortManual
        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        launchInPlace: true
        separateLaunchers: false
        Component.onCompleted: launcherList = dockHost.launchers
    }

    // Glass
    Rectangle {
        id: glass
        x: root.glassX
        y: root.glassY
        width: root.glassW
        height: root.glassHeight
        radius: root.glassRadius
        color: Qt.rgba(0.13, 0.14, 0.19, 0.58)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        Rectangle {   // inner highlight along the top edge
            x: 1; y: 1; width: parent.width - 2; height: 1
            color: Qt.rgba(1, 1, 1, 0.10)
        }
    }

    // Separator between the application section and the right section.
    Rectangle {
        x: root.slotStart(root.leftCount) - root.separatorWidth / 2 - 0.5
        y: root.glassY + root.pad * 0.9
        width: 1
        height: root.glassHeight - root.pad * 1.8
        color: Qt.rgba(1, 1, 1, 0.22)
        // The separator sits in the unmagnified bar; displace it like a tile edge.
        transform: Translate { x: Mag.displace(root.slotStart(root.leftCount) - root.separatorWidth / 2, root.center, root.tile, root.large, root.fish) - (root.slotStart(root.leftCount) - root.separatorWidth / 2) }
    }

    // Pointer tracking over the glass column.
    HoverHandler {
        id: hover
        onPointChanged: root.trackPointer(point.position)
        onHoveredChanged: if (!hovered) { root.fish = 0; }
    }
    function trackPointer(p) {
        const over = p.x >= glassX && p.x <= glassX + glassW && p.y >= glassY - (large - tile) && p.y <= height;
        if (over) {
            center = Math.min(Math.max(p.x, slotStart(0)), slotStart(slotCount - 1) + tile);
            fish = 1;
        } else {
            fish = 0;
        }
    }

    // Application tiles from the task model.
    Repeater {
        id: taskRepeater
        model: tasksModel
        delegate: Tile {
            id: taskTile
            required property int index
            required property var model
            slot: root.taskSlot(index)
            icon: model.decoration
            label: model.display
            running: model.IsWindow || model.IsGroupParent
            active: model.IsActive
            startup: model.IsStartup
            onClicked: {
                const idx = tasksModel.makeModelIndex(index);
                if (model.IsLauncher) {
                    tasksModel.requestNewInstance(idx);
                } else if (model.IsGroupParent) {
                    tasksModel.requestActivate(tasksModel.makeModelIndex(index, 0));
                } else {
                    tasksModel.requestActivate(idx);
                }
            }
            onRightClicked: root.openMenu(index, model.IsLauncher, model.IsWindow || model.IsGroupParent, model.IsGroupParent ? model.ChildCount : 1, model.LauncherUrlWithoutIcon, taskTile)
            // Where a window of this application minimises to: the tile itself.
            function publish() {
                if (model.IsGroupParent) {
                    for (let c = 0; c < model.ChildCount; ++c) {
                        tasksModel.requestPublishDelegateGeometry(tasksModel.makeModelIndex(index, c), Qt.rect(0, 0, width, height), taskTile.iconItem);
                    }
                } else if (model.IsWindow) {
                    tasksModel.requestPublishDelegateGeometry(tasksModel.makeModelIndex(index), Qt.rect(0, 0, width, height), taskTile.iconItem);
                }
            }
            Timer { id: publishTimer; interval: 120; onTriggered: taskTile.publish() }
            onRunningChanged: publishTimer.restart()
            onXChanged: publishTimer.restart()
            onWidthChanged: publishTimer.restart()
            Component.onCompleted: publishTimer.restart()
        }
    }

    Tile {
        slot: 1
        icon: "qrc:/qml/launchpad.svg"
        label: "Launchpad"
        onClicked: dockHost.openLaunchpad()
    }
    Tile {
        slot: root.leftCount
        icon: "folder-download"
        label: "Downloads"
        onClicked: dockHost.openPath(dockHost.homePath + "/Downloads")
    }
    Tile {
        slot: root.leftCount + 1
        icon: dockHost.trashEmpty ? "user-trash" : "user-trash-full"
        label: "Trash"
        onClicked: dockHost.openTrash()
    }

    // Context menu for application tiles.
    function openMenu(row, isLauncher, isRunning, windows, launcherUrl, item) {
        taskMenu.row = row;
        taskMenu.isLauncher = isLauncher;
        taskMenu.isRunning = isRunning;
        taskMenu.windows = windows;
        taskMenu.launcherUrl = launcherUrl;
        taskMenu.pinned = tasksModel.launcherPosition(launcherUrl) >= 0;
        taskMenu.popup(item, 0, -taskMenu.height - 8);
    }
    QQC2.Menu {
        id: taskMenu
        property int row: -1
        property bool isLauncher: false
        property bool isRunning: false
        property int windows: 0
        property var launcherUrl: ""
        property bool pinned: false
        function each(action) {
            if (windows > 1) {
                for (let c = 0; c < windows; ++c) { action(tasksModel.makeModelIndex(row, c)); }
            } else {
                action(tasksModel.makeModelIndex(row));
            }
        }
        QQC2.MenuItem {
            text: "Show All Windows"
            enabled: taskMenu.isRunning
            onTriggered: { taskMenu.each(i => tasksModel.requestActivate(i)); dockHost.showAllWindows(); }
        }
        QQC2.MenuItem {
            text: "Hide"
            enabled: taskMenu.isRunning
            onTriggered: taskMenu.each(i => tasksModel.requestToggleMinimized(i))
        }
        QQC2.MenuSeparator {}
        QQC2.Menu {
            title: "Options"
            QQC2.MenuItem {
                text: taskMenu.pinned ? "Remove from Dock" : "Keep in Dock"
                onTriggered: taskMenu.pinned ? tasksModel.requestRemoveLauncher(taskMenu.launcherUrl) : tasksModel.requestAddLauncher(taskMenu.launcherUrl)
            }
        }
        QQC2.MenuSeparator {}
        QQC2.MenuItem {
            text: taskMenu.isRunning ? "Quit" : "Open"
            onTriggered: {
                if (taskMenu.isRunning) {
                    taskMenu.each(i => tasksModel.requestClose(i));
                } else {
                    tasksModel.requestNewInstance(tasksModel.makeModelIndex(taskMenu.row));
                }
            }
        }
    }
}
