// SPDX-License-Identifier: MIT
// Native Plasma panels and applets; KWin continues to manage application windows.
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
        "org.kde.plasma.showdesktop"
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
    var wallpaperPath = assetDirectory + "/ocean.svg";
    var iconPath = assetDirectory + "/absolute-symbolic.svg";
    if (!fileExists(wallpaperPath) || !fileExists(iconPath)) {
        throw new Error("Install Absolute's complete user-local theme before applying its layout.");
    }

    function installedDesktop(candidates) {
        for (var index = 0; index < candidates.length; index++) {
            if (applicationExists(candidates[index])) {
                return candidates[index];
            }
        }
        throw new Error("Required desktop application is missing: " + candidates.join(" or "));
    }

    // Resolve each application before changing any panel. These are real Fedora apps.
    var launcherIds = [
        installedDesktop(["org.kde.dolphin.desktop"]),
        installedDesktop(["firefox.desktop", "org.mozilla.firefox.desktop"]),
        installedDesktop(["org.kde.konsole.desktop"]),
        installedDesktop(["systemsettings.desktop", "org.kde.systemsettings.desktop"])
    ];

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

    function widget(panel, plugin, index) {
        var existing = panel.widgets(plugin);
        var result = existing.length ? existing[0] : panel.addWidget(plugin);
        result.index = index;
        return result;
    }

    function configure(applet, group, values) {
        applet.currentConfigGroup = [group];
        Object.keys(values).forEach(function (key) {
            applet.writeConfig(key, values[key]);
        });
        applet.currentConfigGroup = [];
    }

    // Reuse our marked panels if the script is run again. Unrelated panels are
    // removed only by Plasma's deliberate --resetLayout flow, after installer backup.
    var topbar = panelForRole("topbar");
    topbar.screen = 0;
    topbar.location = "top";
    topbar.height = 34;
    topbar.lengthMode = "fill";
    topbar.alignment = "center";
    topbar.offset = 0;
    topbar.hiding = "none";
    topbar.floating = false;
    topbar.opacity = "translucent";

    configure(widget(topbar, "org.kde.plasma.kickoff", 0), "General", {
        icon: iconPath,
        menuLabel: "Absolute"
    });
    widget(topbar, "org.kde.plasma.appmenu", 1);
    widget(topbar, "org.kde.plasma.panelspacer", 2);
    widget(topbar, "org.kde.plasma.systemtray", 3);
    configure(widget(topbar, "org.kde.plasma.digitalclock", 4), "Appearance", {
        showDate: true,
        dateFormat: "custom",
        customDateFormat: "ddd, d MMM",
        dateDisplayFormat: 1,
        showSeconds: 0,
        use24hFormat: 1
    });

    var dock = panelForRole("dock");
    dock.screen = 0;
    dock.location = "bottom";
    dock.height = 64;
    dock.lengthMode = "fit";
    dock.alignment = "center";
    dock.offset = 0;
    dock.hiding = "dodgewindows";
    dock.floating = true;
    dock.opacity = "translucent";
    configure(widget(dock, "org.kde.plasma.icontasks", 0), "General", {
        launchers: launcherIds.map(function (id) { return "applications:" + id; }).join(","),
        separateLaunchers: false,
        groupingStrategy: 1,
        sortingStrategy: 1,
        showOnlyCurrentDesktop: false,
        showOnlyCurrentScreen: false,
        iconSpacing: 1
    });
    widget(dock, "org.kde.plasma.showdesktop", 1);

    var currentDesktops = desktopsForActivity(currentActivity());
    for (var desktopIndex = 0; desktopIndex < currentDesktops.length; desktopIndex++) {
        var desktop = currentDesktops[desktopIndex];
        desktop.wallpaperPlugin = "org.kde.image";
        desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
        desktop.writeConfig("Image", "file://" + encodeURI(wallpaperPath));
        desktop.currentConfigGroup = [];
    }
    print("Absolute layout configured with native Plasma panels and application launchers.");
}());
