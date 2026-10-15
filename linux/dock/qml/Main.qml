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

    // Autohide, from research/DOCK-AUTOHIDE.md: the bar slides by distanceTop + tile +
    // distanceBottom + 10 (nothing stays on screen), the show starts 0.15 s after the
    // pointer rests on a 2 px strip along the edge, the hide starts as soon as it leaves
    // the band 10 px beyond the glass, and both slides take floor(ln(d/2 + 1) + 1) × 60 ms
    // with a cosine ease, d being the travel left.
    readonly property bool autohide: dockHost.autohide
    readonly property real hiddenOffset: glassHeight + bottomMargin + 10
    property real hideOffset: 0
    property bool hidden: false
    function slideDuration(distance) { return Math.floor(Math.log(distance / 2 + 1) + 1) * 60; }
    NumberAnimation { id: slide; target: root; property: "hideOffset"; easing.type: Easing.InOutSine }
    function slideTo(target) {
        slide.stop();
        slide.duration = slideDuration(Math.abs(target - hideOffset));
        slide.to = target;
        slide.start();
    }
    function showBar() {
        if (!autohide) { return; }
        showTimer.stop();
        hidden = false;
        dockHost.setHiddenStrip(false);
        slideTo(0);
    }
    function hideBar() {
        if (!autohide || hidden) { return; }
        hidden = true;
        fish = 0;
        slideTo(hiddenOffset);
    }
    onHideOffsetChanged: if (hidden && hideOffset >= hiddenOffset - 0.5) { dockHost.setHiddenStrip(true); }
    Timer { id: showTimer; interval: 150; onTriggered: root.showBar() }
    property point armedPoint: Qt.point(-100, -100)
    // The Mac reveals the Dock 500 ms after launch, then it hides.
    Timer { id: launchHide; interval: 500; running: root.autohide; onTriggered: root.hideBar() }

    // The fish: 0 at rest, 1 fully magnified, ramping linearly over the measured duration.
    property real fish: 0
    property real center: 0
    Behavior on fish {
        NumberAnimation { duration: Mag.rampDuration(root.large - root.tile); easing.type: Easing.Linear }
    }

    // Unmagnified layout: slots left to right. The left section is the task tiles with
    // Launchpad in slot 1; the right section, after the separator, holds Downloads and Trash.
    readonly property int leftCount: Math.max(taskRepeater.count, 1) + 1
    // Minimised windows take tiles right of the separator, before Downloads and Trash.
    readonly property int rightCount: 2 + minimisedRepeater.count
    readonly property int nextMinimisedSlot: leftCount + minimisedRepeater.count
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
    Component.onCompleted: dockHost.setExclusiveZone(autohide ? 0 : glassHeight + bottomMargin)

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
    // Only the minimised windows, one tile each.
    TaskManager.TasksModel {
        id: minimisedModel
        virtualDesktop: virtualDesktopInfo.currentDesktop
        activity: activityInfo.currentActivity
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
        filterMinimized: false
        filterNotMinimized: true
        sortMode: TaskManager.TasksModel.SortManual
        groupMode: TaskManager.TasksModel.GroupDisabled
        launchInPlace: false
        separateLaunchers: false
    }

    // Everything visible slides together when the bar hides.
    Item {
        id: content
        anchors.fill: parent
        transform: Translate { y: root.hideOffset }
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
                // Where a window of this application minimises to: the next free tile right
                // of the separator, as the Mac does unless "minimise into application icon" is on.
                function publish() {
                    const target = Qt.rect(root.slotStart(root.nextMinimisedSlot), root.glassY + root.pad, root.tile, root.tile);
                    if (model.IsGroupParent) {
                        for (let c = 0; c < model.ChildCount; ++c) {
                            tasksModel.requestPublishDelegateGeometry(tasksModel.makeModelIndex(index, c), target, root);
                        }
                    } else if (model.IsWindow) {
                        tasksModel.requestPublishDelegateGeometry(tasksModel.makeModelIndex(index), target, root);
                    }
                }
                Timer { id: publishTimer; interval: 120; onTriggered: taskTile.publish() }
                onRunningChanged: publishTimer.restart()
                onXChanged: publishTimer.restart()
                onWidthChanged: publishTimer.restart()
                Component.onCompleted: publishTimer.restart()
                Connections {
                    target: minimisedRepeater
                    function onCountChanged() { publishTimer.restart(); }
                }
            }
        }

        Tile {
            slot: 1
            icon: "qrc:/qml/launchpad.svg"
            label: "Launchpad"
            onClicked: dockHost.openLaunchpad()
        }
        // Minimised windows: a tile each, restored with a click; a window un-minimises from it.
        Repeater {
            id: minimisedRepeater
            model: minimisedModel
            delegate: Tile {
                id: minimisedTile
                required property int index
                required property var model
                slot: root.leftCount + index
                icon: model.decoration
                label: model.display
                onClicked: minimisedModel.requestToggleMinimized(minimisedModel.makeModelIndex(index))
                function publish() {
                    minimisedModel.requestPublishDelegateGeometry(minimisedModel.makeModelIndex(index), Qt.rect(0, 0, width, height), minimisedTile.iconItem);
                }
                Timer { id: minimisedPublish; interval: 120; onTriggered: minimisedTile.publish() }
                onXChanged: minimisedPublish.restart()
                onWidthChanged: minimisedPublish.restart()
                Component.onCompleted: minimisedPublish.restart()
            }
        }
        Tile {
            slot: root.leftCount + minimisedRepeater.count
            icon: "folder-download"
            label: "Downloads"
            onClicked: dockHost.openPath(dockHost.homePath + "/Downloads")
        }
        Tile {
            slot: root.leftCount + minimisedRepeater.count + 1
            icon: dockHost.trashEmpty ? "user-trash" : "user-trash-full"
            label: "Trash"
            onClicked: dockHost.openTrash()
        }
    }

    // Pointer tracking over the glass column, and the autohide trigger.
    HoverHandler {
        id: hover
        onPointChanged: root.trackPointer(point.position)
        onHoveredChanged: {
            if (!hovered) {
                root.fish = 0;
                showTimer.stop();
                root.hideBar();
            } else if (root.hidden) {
                root.armedPoint = point.position;
                showTimer.restart();
            }
        }
    }
    function trackPointer(p) {
        if (hidden) {
            // Moving more than 2 px from the armed point re-arms the 0.15 s delay.
            if (Math.abs(p.x - armedPoint.x) > 2 || Math.abs(p.y - armedPoint.y) > 2) {
                armedPoint = p;
                showTimer.restart();
            }
            return;
        }
        const over = p.x >= glassX && p.x <= glassX + glassW && p.y >= glassY - (large - tile) && p.y <= height;
        if (over) {
            center = Math.min(Math.max(p.x, slotStart(0)), slotStart(slotCount - 1) + tile);
            fish = 1;
        } else {
            fish = 0;
        }
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
