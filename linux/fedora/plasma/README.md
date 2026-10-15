# Absolute Plasma profile

`org.absolute.desktop` is the Plasma 6 global theme that turns a Fedora KDE
session into Absolute's desktop. It is applied by
[`script/absolute_surface.sh`](../../../script/absolute_surface.sh); see
[linux/fedora/README.md](../README.md) for the full installer.

What the profile sets:

- **Menu bar** across the top (30 px): the Absolute logo menu (Kickoff), the
  active application's menus (global menu), status items and a one-line
  `Thu 15 Oct 5:19 PM` clock.
- **Dock** floating at the bottom (64 px): Launchpad (Plasma's application
  dashboard on F4), then the applications in their macOS roles: Dolphin as
  Finder, Firefox as Safari, Gwenview as Photos, Elisa as Music, Kate as Notes,
  KeePassXC as Passwords, Konsole as Terminal, Discover as the App Store,
  System Settings, then the Trash. Applications that are not installed are
  skipped. Running applications show a dot.
- **Appearance** from WhiteSur: Aurorae window decoration with the traffic
  lights on the left, WhiteSurDark colours, Kvantum widget style, WhiteSur
  icons and cursors, the WhiteSur Plasma style and splash. WhiteSur is a
  dependency fetched at pinned commits (listed in `profile.json`), never
  vendored.
- **Fonts**: Inter for the interface, JetBrains Mono for code. Font strings
  use Qt 6's sixteen-field form; the ten-field form reads weight 400 as bold.
- **Wallpaper**: `absolute-night.png`, rendered at install time by
  `script/wallpaper_absolute.py` (original artwork, any size).
- **Window switcher**: large icons, like the Mac's application switcher.

The layout script (`contents/layouts/org.kde.plasma.desktop-layout.js`) marks
its panels, rebuilds their contents on every run and settles the widget order
afterwards, because Plasma 6.7 places the first widget added to a fresh panel
at its end.

The installer adds what a look-and-feel package cannot carry: KWin's Magic
Lamp minimise, blur, Overview, centred window placement, no window borders,
the centred search (KRunner), notifications top right, the lock screen
wallpaper, the Konsole profile, the shortcuts (Meta+Space search, Ctrl+Up
Overview, Meta+Tab switcher, Meta+Q close, Meta+H minimise, F11 desktop) and
the login screen.

Activate from a Plasma session:

```sh
bash script/absolute_surface.sh --all
```

`--apply` backs up the current Plasma preferences first and prints the
`--restore` command. The two SVG assets and the wallpaper generator are
original Absolute work under the repository's MIT license.
