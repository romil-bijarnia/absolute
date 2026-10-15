// SPDX-License-Identifier: MIT
// Absolute's desktop layout for KDE Plasma 6: a menu bar across the top and a
// floating Dock at the bottom, laid out the way macOS lays out its own.
// KWin keeps managing application windows; every piece here is a native
// Plasma panel or applet.
(function () {
    "use strict";

    var profile = "org.absolute.desktop";
    var required = [
        "org.kde.plasma.kickoff",
        "org.kde.plasma.appmenu",
        "org.kde.plasma.panelspacer",
        "org.kde.plasma.systemtray",
        "org.kde.plasma.digitalclock",
        "org.kde.plasma.icontasks",
        "org.kde.plasma.kickerdash",
        "org.kde.plasma.trash",
        "org.absolute.appname",
        "org.absolute.spotlight",
        "org.absolute.controlcentre"
    ];
    if (parseInt(applicationVersion, 10) < 6) {
        throw new Error("Absolute requires KDE Plasma 6.");
    }
    for (var i = 0; i < required.length; i++) {
        if (knownWidgetTypes.indexOf(required[i]) < 0) {
            throw new Error("Required Plasma widget is missing: " + required[i]);
        }
    }

    var assetDirectory = userDataPath("data", "plasma/look-and-feel/" + profile + "/contents/images").replace(/\/+$/, "");
    // Prefer the wallpaper package, so System Settings shows it selected; fall back to the
    // theme's own copy, then to the ocean vector.
    var wallpaperPath = userDataPath("data", "wallpapers/Absolute").replace(/\/+$/, "");
    if (!fileExists(wallpaperPath + "/metadata.json")) {
        wallpaperPath = assetDirectory + "/absolute-night.png";
    }
    if (!fileExists(wallpaperPath)) {
        wallpaperPath = assetDirectory + "/ocean.svg";
    }
    var menuIconPath = assetDirectory + "/absolute-symbolic.svg";
    var launchpadIconPath = assetDirectory + "/launchpad.svg";
    if (!fileExists(wallpaperPath) || !fileExists(menuIconPath) || !fileExists(launchpadIconPath)) {
        throw new Error("Install Absolute's complete user-local theme before applying its layout.");
    }

    function installedDesktop(candidates) {
        for (var index = 0; index < candidates.length; index++) {
            if (applicationExists(candidates[index])) {
                return candidates[index];
            }
        }
        return null;
    }

    // The Dock, left to right, with the macOS role each Fedora application plays.
    // Applications that are not installed are skipped, so the Dock never has a dead tile.
    var dockApplications = [
        ["org.kde.dolphin.desktop"],                                   // Finder
        ["firefox.desktop", "org.mozilla.firefox.desktop"],            // Safari
        ["org.kde.gwenview.desktop"],                                  // Photos
        ["org.kde.elisa.desktop"],                                     // Music
        ["org.kde.kate.desktop"],                                      // Notes
        ["org.keepassxc.KeePassXC.desktop", "keepassxc.desktop"],      // Passwords
        ["org.kde.konsole.desktop"],                                   // Terminal
        ["org.kde.discover.desktop"],                                  // App Store
        ["systemsettings.desktop", "org.kde.systemsettings.desktop"]   // System Settings
    ];
    var launcherIds = [];
    for (var a = 0; a < dockApplications.length; a++) {
        var id = installedDesktop(dockApplications[a]);
        if (id) { launcherIds.push("applications:" + id); }
    }
    if (launcherIds.length === 0) {
        throw new Error("None of the Dock's applications are installed.");
    }

    function panelForRole(role) {
        var existing = panels();
        for (var index = 0; index < existing.length; index++) {
            var candidate = existing[index];
            var oldGroup = candidate.currentConfigGroup;
            candidate.currentConfigGroup = ["Absolute"];
            var matches = candidate.readConfig("profile", "") === profile &&
                candidate.readConfig("role", "") === role;
            candidate.currentConfigGroup = oldGroup;
            if (matches) {
                // Rebuild the panel's contents from scratch so a second run gives the same order.
                candidate.widgets().forEach(function (old) { old.remove(); });
                return candidate;
            }
        }
        var created = new Panel();
        created.currentConfigGroup = ["Absolute"];
        created.writeConfig("profile", profile);
        created.writeConfig("role", role);
        created.currentConfigGroup = [];
        return created;
    }

    // Widgets are appended in reading order. Plasma 6.7 puts the first widget added to
    // a fresh panel at its end, so settle() moves any widget whose position differs from
    // the intended one; moving only misplaced widgets avoids the setter's off-by-one when
    // a widget is assigned the index it already has.
    function widget(panel, plugin) {
        return panel.addWidget(plugin);
    }

    function settle(panel, order) {
        for (var pass = 0; pass < 4; pass++) {
            var moved = false;
            for (var position = 0; position < order.length; position++) {
                var found = panel.widgets(order[position]);
                if (found.length && found[0].index !== position) {
                    found[0].index = position;
                    moved = true;
                    break;
                }
            }
            if (!moved) { return; }
        }
    }

    function configure(applet, group, values) {
        applet.currentConfigGroup = [group];
        Object.keys(values).forEach(function (key) {
            applet.writeConfig(key, values[key]);
        });
        applet.currentConfigGroup = [];
    }

    // Menu bar: logo menu, the active application's menus, then status items and the clock.
    var menubar = panelForRole("topbar");
    menubar.screen = 0;
    menubar.location = "top";
    menubar.height = 37;   // the Mac's menu bar on a display with a notch
    menubar.lengthMode = "fill";
    menubar.alignment = "center";
    menubar.offset = 0;
    menubar.hiding = "none";
    menubar.floating = false;
    menubar.opacity = "translucent";

    configure(widget(menubar, "org.kde.plasma.kickoff"), "General", {
        icon: menuIconPath,
        menuLabel: "",
        showActionButtonCaption: false
    });
    widget(menubar, "org.absolute.appname");
    configure(widget(menubar, "org.kde.plasma.appmenu"), "General", {
        compactView: false
    });
    widget(menubar, "org.kde.plasma.panelspacer");
    // The tray carries what the Mac's bar carries: Wi-Fi and battery. Everything else
    // is not loaded, so no overflow chevron appears.
    var tray = widget(menubar, "org.kde.plasma.systemtray");
    configure(tray, "General", {
        scaleIconsToFit: false,
        extraItems: "org.kde.plasma.networkmanagement,org.kde.plasma.battery",
        // Every applet id counts as already known, so no tray plasmoid gets auto-enabled.
        knownItems: knownWidgetTypes.join(","),
        shownItems: "org.kde.plasma.networkmanagement,org.kde.plasma.battery",
        hiddenItems: ""
    });
    widget(menubar, "org.absolute.spotlight");
    widget(menubar, "org.absolute.controlcentre");
    configure(widget(menubar, "org.kde.plasma.digitalclock"), "Appearance", {
        showDate: true,
        dateFormat: "custom",
        customDateFormat: "ddd d MMM",
        dateDisplayFormat: 1,
        showSeconds: 0,
        use24hFormat: 0,
        fontWeight: 500
    });
    settle(menubar, ["org.kde.plasma.kickoff", "org.absolute.appname", "org.kde.plasma.appmenu", "org.kde.plasma.panelspacer",
                     "org.kde.plasma.systemtray", "org.absolute.spotlight", "org.absolute.controlcentre", "org.kde.plasma.digitalclock"]);

    // Dock: Launchpad, the applications, running windows, then the Trash. When Absolute's
    // own Dock is installed it takes this place, and no Plasma panel is created for it.
    var ownDock = fileExists(userDataPath("config") + "/autostart/org.absolute.Dock.desktop");
    if (ownDock) {
        panels().forEach(function (p) {
            var g = p.currentConfigGroup;
            p.currentConfigGroup = ["Absolute"];
            var r = p.readConfig("role", "");
            p.currentConfigGroup = g;
            if (r === "dock") { p.remove(); }
        });
    }
    var dock = ownDock ? null : panelForRole("dock");
    if (dock) {
    dock.screen = 0;
    dock.location = "bottom";
    dock.height = 64;
    dock.lengthMode = "fit";
    dock.alignment = "center";
    dock.offset = 0;
    dock.hiding = "none";
    dock.floating = true;
    dock.opacity = "translucent";

    var launchpad = widget(dock, "org.kde.plasma.kickerdash");
    configure(launchpad, "General", {
        icon: launchpadIconPath,
        useCustomButtonImage: true,
        customButtonImage: launchpadIconPath
    });
    launchpad.globalShortcut = "F4";

    configure(widget(dock, "org.kde.plasma.icontasks"), "General", {
        launchers: launcherIds.join(","),
        separateLaunchers: false,
        groupingStrategy: 1,
        sortingStrategy: 1,
        showOnlyCurrentDesktop: false,
        showOnlyCurrentScreen: false,
        showOnlyCurrentActivity: false,
        iconSpacing: 1,
        maxStripes: 1,
        indicateAudioStreams: false,
        showToolTips: true
    });
    widget(dock, "org.kde.plasma.trash");
    settle(dock, ["org.kde.plasma.kickerdash", "org.kde.plasma.icontasks", "org.kde.plasma.trash"]);
    }

    var currentDesktops = desktopsForActivity(currentActivity());
    for (var desktopIndex = 0; desktopIndex < currentDesktops.length; desktopIndex++) {
        var desktop = currentDesktops[desktopIndex];
        desktop.wallpaperPlugin = "org.kde.image";
        desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
        desktop.writeConfig("Image", "file://" + encodeURI(wallpaperPath));
        desktop.writeConfig("FillMode", 2);
        desktop.currentConfigGroup = [];
    }
    print("Absolute layout configured: menu bar, Dock with " + launcherIds.length + " applications, wallpaper.");
}());
