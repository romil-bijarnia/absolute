// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami

// The bold application name that follows the logo in the Mac's menu bar. With no
// window active the desktop owns the bar, so it reads Finder.
PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Layout.minimumWidth: label.implicitWidth + Kirigami.Units.largeSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.fillHeight: true

    property string activeName: ""
    property var activeIndex: null

    TaskManager.TasksModel {
        id: tasks
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
        groupMode: TaskManager.TasksModel.GroupDisabled
        onActiveTaskChanged: root.refresh()
        onDataChanged: root.refresh()
        onRowsRemoved: root.refresh()
    }

    function refresh() {
        const index = tasks.activeTask;
        if (index && index.valid) {
            root.activeIndex = index;
            const name = tracker.nameFor(index.row);
            root.activeName = name.length > 0 ? name : "";
        } else {
            root.activeIndex = null;
            root.activeName = "";
        }
    }

    // Delegates read the model roles; the active one reports its application name.
    Repeater {
        id: tracker
        model: tasks
        property var names: ({})
        function nameFor(row) { return names[row] || ""; }
        delegate: Item {
            visible: false
            required property int index
            required property var model
            readonly property string appName: model.AppName || model.display || ""
            onAppNameChanged: { tracker.names[index] = appName; if (model.IsActive) root.refresh(); }
            Component.onCompleted: { tracker.names[index] = appName; if (model.IsActive) root.refresh(); }
        }
    }

    PlasmaComponents.Label {
        id: label
        anchors.centerIn: parent
        text: root.activeName.length > 0 ? root.activeName : "Finder"
        font.weight: Font.DemiBold
        color: Kirigami.Theme.textColor
    }

    MouseArea {
        anchors.fill: parent
        onClicked: appMenu.openRelative()
    }

    PlasmaExtras.Menu {
        id: appMenu
        visualParent: root
        placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
        PlasmaExtras.MenuItem {
            text: "About " + label.text
            enabled: false
        }
        PlasmaExtras.MenuItem { separator: true }
        PlasmaExtras.MenuItem {
            text: "Hide " + label.text
            enabled: root.activeIndex !== null
            onClicked: tasks.requestToggleMinimized(root.activeIndex)
        }
        PlasmaExtras.MenuItem {
            text: "Quit " + label.text
            enabled: root.activeIndex !== null
            onClicked: tasks.requestClose(root.activeIndex)
        }
    }
}
