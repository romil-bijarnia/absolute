# Absolute Plasma profile

This user-local Plasma 6 global theme configures the existing Fedora KDE desktop.
KWin manages real application windows. The top panel contains Absolute's application
launcher, the active application's exported global menu, system tray and clock.
The centered floating Dock pins Dolphin, Firefox, Konsole and System Settings;
it also displays running applications and a Show Desktop button. Breeze Dark
provides the palette and widget style. The two SVG assets are original Absolute
artwork under the repository's MIT license.

Install and activate from a terminal in the physical Fedora session:

```sh
bash script/install_fedora.sh --install --apply-desktop
```

Installation alone leaves the active desktop layout intact. The installer copies
`org.absolute.desktop` into
`${XDG_DATA_HOME:-$HOME/.local/share}/plasma/look-and-feel/` and saves a configuration
backup before explicit activation. It uses Plasma's native command:

```sh
plasma-apply-lookandfeel --apply org.absolute.desktop --resetLayout
```

The reset replaces the current panels and desktop layout. Use the installer's
`--restore-desktop BACKUP` command to restore the saved configuration. Do not call
the reset command directly on a customized desktop without first taking that backup.
This package does not change the bootloader, display manager, kernel or drivers.

The layout script marks its own panels and reuses them on a direct second run,
so it does not create duplicate Absolute panels. The top panel and Dock use Plasma
screen 0; the wallpaper applies to the current activity's screens. Panel sizes are
logical pixels and follow Plasma display scaling. Both panels remain editable in
Plasma's normal edit mode.

The global menu depends on the active application exporting a compatible menu.
KDE applications normally provide one; Firefox can retain its own application menu.
The Firefox Dock entry launches the installed Linux Firefox. The Swift/GTK preview
is an optional development application, separate from this native desktop profile.

Native application launching, menu export, panel placement, multi-monitor behavior,
display scaling, suspend/resume and appearance still require validation in Fedora.
Local JSON/SVG/JavaScript checks establish package structure and script consistency,
not rendered Plasma behavior or physical-Mac hardware support.

Implementation references are the upstream
[Plasma scripting API](https://develop.kde.org/docs/plasma/scripting/api/),
[Plasma 6 packaging guidance](https://develop.kde.org/docs/plasma/theme/theme-porting-to-plasma6/),
[panel scripting properties](https://github.com/KDE/plasma-workspace/blob/Plasma/6.6/shell/scripting/panel.h),
[native apply tool](https://github.com/KDE/plasma-workspace/blob/Plasma/6.6/kcms/lookandfeel/tool/lnftool.cpp),
[task manager configuration](https://github.com/KDE/plasma-desktop/blob/Plasma/6.6/applets/taskmanager/main.xml),
[application launcher configuration](https://github.com/KDE/plasma-desktop/blob/Plasma/6.6/applets/kickoff/main.xml)
and [clock configuration](https://github.com/KDE/plasma-workspace/blob/Plasma/6.6/applets/digital-clock/main.xml).
The profile references installed KDE components; it does not vendor their source or
artwork. Their upstream licenses remain with their Fedora packages.
