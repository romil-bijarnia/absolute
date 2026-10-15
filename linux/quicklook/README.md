# Absolute Quick Look

A floating preview of the selected files: the name on top, an "Open with" button
on the right, the content underneath. Images, text and code, PDF, video and audio
preview inline; everything else shows its icon with the type, size and date. Space
or Escape closes it, the arrow keys move through the selection, Return opens the
file in its application.

## How it is reached

- `absolute-quicklook FILE...` from anywhere; a running instance takes the files
  over DBus (`org.absolute.QuickLook /App show`).
- Finder's context menu carries a "Quick Look" entry on every file and folder
  (`data/absolute-quicklook-servicemenu.desktop`, installed under
  `~/.local/share/kio/servicemenus/`).
- The Space key inside Finder needs an action in Dolphin itself; that is the open
  item on the roadmap (a Dolphin patch or Absolute's own Finder).

## Build

    cmake -S linux/quicklook -B build/quicklook -DCMAKE_BUILD_TYPE=Release
    cmake --build build/quicklook
    install -m755 build/quicklook/absolute-quicklook ~/.local/bin/

`script/absolute_surface.sh --dock` builds and installs it with the Dock. PDF and
media previews use Qt's `QtQuick.Pdf` and `QtMultimedia` modules at run time.
