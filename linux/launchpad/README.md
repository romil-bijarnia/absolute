# Absolute Launchpad

The full-screen application grid: the desktop blurred and darkened behind a search
field, pages of seven by five tiles, page dots underneath. The Dock's Launchpad tile
toggles it, so does `absolute-launchpad --toggle` from anywhere, and the panel is
reachable over DBus as `org.absolute.Launchpad /App` (`toggle`, `show`, `hide`).

## How it works

- `src/launchpad.cpp` lists every application with a menu entry through
  `KApplicationTrader`, sorted with a locale-aware collator, and exposes the list as a
  model with name, icon, desktop id and comment roles. A `QSortFilterProxyModel` on top
  does the typed search. Launching goes through `KIO::ApplicationLauncherJob`.
- The window is a LayerShellQt overlay anchored to all four edges with exclusive
  keyboard focus, so Escape and typing always reach it. `KWindowEffects` asks KWin for
  blur behind the whole surface.
- `qml/Main.qml` draws the search field, a `SwipeView` of pages (arrow keys flip pages
  when the field is empty, Enter launches the first match) and the dots.
- One process owns the DBus name; later invocations forward `toggle` or `show` to it,
  which is what the Dock and the launcher entry do.

## Build

    cmake -S linux/launchpad -B build/launchpad -DCMAKE_BUILD_TYPE=Release
    cmake --build build/launchpad
    install -m755 build/launchpad/absolute-launchpad ~/.local/bin/

`script/absolute_surface.sh --dock` builds and installs it with the Dock, writes the
launcher entry and an autostart entry that keeps the hidden service running.

## Not yet

Folders, drag-to-reorder and the pinch gesture. The page order is alphabetical.
