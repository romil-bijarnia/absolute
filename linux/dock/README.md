# Absolute Dock

A layer-shell window at the bottom edge, drawn by Absolute, driven by Plasma's
task model (`org.kde.taskmanager`). Left to right: Finder (Dolphin), Launchpad,
the pinned applications and running windows, a separator, Downloads and Trash.

- Magnification is the curve measured from the Mac's Dock ("fish", see
  `research/DOCK-MAGNIFICATION.md`): each tile's span is the displacement of
  its two edges, the amplitude normalised so the tile under the pointer is
  exactly `largeSize`; the ramp lasts `floor(ln(Δ/2+1)·42+1)` ms.
- Each window's tile rectangle is published to KWin, so the Genie effect in
  `linux/kwin/genie` knows where a window minimises to. KWin only grants that
  protocol to clients whose desktop entry declares
  `X-KDE-Wayland-Interfaces=org_kde_plasma_window_management`, matched by
  executable path; the installer writes that entry.
- Blur and contrast behind the glass come from KWindowSystem; the input region
  is the column above the glass so magnified tiles stay clickable; the
  exclusive zone keeps maximised windows above the Dock.
- Configuration: `~/.config/absolute/dockrc` (`tileSize`, `largeSize`,
  `magnification`, `autohide`, `launchers`, `launchpadCommand`), the same
  numbers the Mac's `com.apple.dock` keys carry.

Build and install with `bash script/absolute_surface.sh --dock`, which also
builds the Genie effect, writes the autostart entry and removes the Plasma dock
panel from the layout. The window is a Qt Quick scene; a hover handler tracks
the pointer, the layout is recomputed from the fish value and centre on every
change, and the Plasma task model supplies icons, names, launch and activation.
