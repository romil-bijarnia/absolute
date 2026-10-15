# Absolute window decoration

A KWin decoration plugin (KDecoration3) that draws the Mac's window chrome: a 32 pt
titlebar with the title centred in semibold, the three lights on the left, 16 pt
rounded corners on all four sides, no visible borders (a 4 pt invisible grab area
outside the window resizes it) and a soft shadow that widens when the window is
active. Hovering any light shows the glyphs on all three, as on the Mac; an inactive
window's lights are grey until hovered. Lights whose action the window refuses
(a dialog that cannot minimise) stay grey.

## Measurements

Taken on Romil's Mac on 15 October 2026 (macOS 27 beta) by asking AppKit directly,
without showing a window (`NSWindow.frameRect(forContentRect:styleMask:)` and
`standardWindowButton(_:)`), so nothing on the screen was touched:

| Measure | Value |
| --- | --- |
| Titlebar height, plain titled window | 32 pt |
| Titlebar with a unified toolbar | 66 pt |
| Light diameter | 14 pt |
| Lights' left edges from the window's left edge | 9, 32, 55 pt |
| Lights' top edge from the window's top | 9 pt |
| Window corner radius (private `_cornerRadius`) | 16 pt |

Colours are the Mac's published light colours (255 95 87, 254 188 46, 40 200 64)
with darker glyphs; the shadow's blur, offset and strength are estimates, not
measurements, until a screenshot of a Mac window can be taken next to it. The
titlebar and title colours come from the active colour scheme's Header set.

## Build and enable

    cmake -S linux/kwin/decoration -B build/decoration -DCMAKE_BUILD_TYPE=Release
    cmake --build build/decoration
    sudo cmake --install build/decoration
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.absolute.decoration
    busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure

`script/absolute_surface.sh --dock` does all of this with the other components.
KWin keeps a loaded decoration plugin in memory: after a rebuild, switch the
decoration away and back, or sign out, to load the new one.

## Not yet

The toolbar-height (66 pt) titlebar for applications with a unified toolbar; the
zoom glyph shape and the shadow against a measured Mac screenshot; the
traffic-light press animation; the option-key alternative glyphs.
