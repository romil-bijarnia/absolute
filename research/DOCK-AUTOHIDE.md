# Dock autohide

This records the third behavior unit under the 15 October 2026 direction: the
timing and trigger geometry of the Dock's automatic hiding, so that Absolute's
Dock can clone them. The reference is macOS 27.0, build 26A5421a, the same Dock
copy as [DOCK-MAGNIFICATION.md](DOCK-MAGNIFICATION.md) (thin arm64e, 4,843,616
bytes, SHA-256
`c8e55d01cbfa33eb68b6d90707da5fd4bd13b27349295e0e732f87eb5263488f`). Hashed
records are in [dock-autohide-findings.json](dock-autohide-findings.json); the
REA dossiers and the annotated listings are under
`research/local/dock-autohide/`.

## Analysis boundary

Everything below is a static reading of machine code. The functions were
analysed with REA 6.4.0 and Ghidra 12.1.3, and the constants were read from the
`otool -tV` dump retained from the magnification pass, annotated by
`research/local/dock-autohide/annotate_otool.py`, which resolves the
`objc_msgSend$selector` stubs, CFString constants, float literals and
Objective-C ivar offsets from the binary. The running Dock was not attached to,
executed or modified, no preference was changed, and nothing was recorded on
screen, so the model has not been compared against the real Dock's timing.

## Shape of the machinery

The Dock does not poll the pointer. It asks the window server for background
mouse events inside a shape with `CGSSetBackgroundEventMaskAndShape`, using the
mask `0x360` kept at `0x1003fa108`: MouseMoved (5), LeftMouseDragged (6),
MouseEntered (8) and MouseExited (9). The shape is `DockBar.rect`, which the
bar-frame function `0x1000128f0` (the function that lays out the bar in the
magnification unit) recomputes on every update and pushes through `0x10000b0cc`
and `-[BackgroundEventsController setMask:shape:]` whenever it changes. Those
events arrive in `-[DockBarMouseEventHandler handleMouseEvent:type:]`, which
sends types 5, 8 and 9 to `_handleMoveEvent:type:`.

`DockBar.autoHide` is a `DockFloatAnimatedProperty` whose value is 0 when the
Dock is shown and 1 when it is hidden. `startAutoShow` and `startAutoHide` set
its target and duration; the update loop steps it (`0x1000502b4`), turns the
value into `autoHideOffset` (`0x1000812e8`), lays the bar out displaced by that
offset along the hide axis, and hides the windows when the value reaches 1.

## Numbers

| Quantity | Value | Read from |
| --- | --- | --- |
| Delay from reaching the edge to the show starting (`autohide-delay`) | 0.15 s | `-[DockBarMouseEventHandler initWithConnection:]` `0x10006ee34`–`0x10006ee48`; float literal at `0x100308980` |
| Delay from leaving to the hide starting | none; `startAutoHide` runs on the leave event | `-[DockBar handleDockEventMouseLeave:]` `0x100095870`–`0x100095880` |
| `autohide-time-modifier` default | 1.0 | `fmov s0, #1.0` at `0x1002586e8` in the DockBar setup function `0x100257e34` |
| `autoHideSpeed` | 60 × modifier, milliseconds per duration step | `0x1002586fc`–`0x100258710` |
| Slide duration, show and hide | `floor(ln(Δ/2 + 1) + 1) × autoHideSpeed` ms; 240 ms both ways for the default geometry | `-[DockBar startAutoShow]` `0x10005f380`–`0x10005f3b4`, `-[DockBar startAutoHide]` `0x10005f5ec`–`0x10005f620` |
| Easing | `0.5 − 0.5·cos(π·t/T)`, ease-in-out in time | step `0x10005031c`–`0x100050344`; easing kind 1 stored by the initialiser called at `0x100258620` |
| Hidden offset | `(distanceTop + tileSize + distanceBottom + 10) × value`; 90 pt for the default 64 pt tile, so nothing of the bar stays on screen | `0x100081304`–`0x100081358` |
| Timer re-arm tolerance | 2 pt for a mouse, 5 pt for tablet events | `0x100070c20`–`0x100070c4c` |
| Edge strip while hidden | 2 pt thick, the full length of the screen edge | `0x1000130d8`–`0x100013100` (bottom), `0x10001316c`–`0x100013184` (left), `0x1000131f0`–`0x100013214` (right) |
| Band while shown | from 10 pt beyond the tiles' outer edge to the screen edge, full edge length | `fmov s0, #-10.0` at `0x100012fbc`, `0x100012f24`; `#10.0` at `0x100012e8c` |
| Dig (full-screen spaces, other displays) | 0.25 s of pushing, at most 0.1 s between moves, within 25° of the edge normal | `0x10006ee4c`–`0x10006ee88` |
| Launch reveal | starts 500 ms after the bar is set up, lasts 550 ms | `0x10025865c`–`0x100258680` |
| Geometry defaults | distanceTop 6, distanceBottom 10, distanceSides 8; tileSize 64 (52 when the main display is at most 800 pt tall); largeSize 128 | `0x100258378`–`0x1002583ac`, `0x100008578`–`0x1000086a0` |

The hide-axis distance Δ is the travel still to make: hiding,
`|autoHideOffset − (distanceTop + tileSize + distanceBottom + currentFish)|`;
showing, `|size − (distanceTop + tileSize + distanceBottom + currentFish −
autoHideOffset)|`, where `size` is `largeSize` only while the fish ramp is
running with the pointer in the bar and `tileSize` otherwise. The floor makes
the duration a step function: 60 ms below 3.44 pt, 120 ms to 12.8 pt, 180 ms
to 38.2 pt, 240 ms to 107.2 pt and 300 ms beyond, all scaled by the modifier.
With the defaults the bar is 80 pt tall, hides over Δ = 80 pt and shows over
Δ = 74 pt, both 240 ms; the 16 pt tile gives 180 ms and the 128 pt tile 300 ms.

## Show and hide

On MouseEntered, `_handleMoveEvent:type:` (`0x100070534`) decides between an
immediate reveal and a delayed one. If autohide is on and the Dock is fully
hidden (`autoHide.now == 1`) or hiding (`animating` with target 1), or the
pointer entered on a display other than the Dock's, it arms a one-shot
`dispatch_source` timer on the main queue for `autohideDelay` seconds
(`0x100070084`, leeway 0) and remembers the entry point. Otherwise, and whenever
autohide is off, it posts the mouse-enter event at once. While the timer is
pending, each MouseMoved compares the pointer with the armed point; a move of
more than 2 pt (5 pt for a tablet subtype) in either axis re-arms the timer for
the full delay, so the Dock appears once the pointer has rested at the edge for
0.15 s. MouseExited cancels the timer. When the timer fires it calls
`_mouseEnterHelper:location:allowSwitchingBetweenDisplays:` with the last
pointer position, which refuses while a mouse button is held without a drag
and otherwise posts the enter event. `-[DockBar handleDockEventMouseEnter:]`
then calls `startAutoShowAndShowAllWindows` whenever the property is idle or
hiding, which animates `autoHide` from its current value to 0.

The `autohide-delay` value lives in `DockBarMouseEventHandler._autohideDelay`.
`-[DOCKPreferences autohideDelayPref]` is a proxy for that ivar and its setter
writes the preference back with `CFPreferencesSetAppValue`.

On MouseExited with no timer pending, the handler posts a mouse-leave event;
`-[DockBar handleDockEventMouseLeave:]` calls `startAutoHide` immediately when
autohide is on and no tile is being dragged, animating `autoHide` to 1. There
is no hide delay in the executable; the pause a user sees is the event path
plus the slide.

When the preference itself changes,
`-[DockBar handleDockEventAutohideEnabled:setRect:context:]` sets `autoHideOn`
and hides at once unless the pointer is inside the in-bar rect, or shows at
once when autohide was turned off.

In a space that is not a user space (a full-screen application) or when the
pointer arrives on another display, the timer is the dig variant instead: the
pointer must keep pushing toward the edge for 0.25 s, with no more than 0.1 s
between moves and a direction within 25° of the edge normal, or the attempt is
reset. The angle is `|Δy/Δx|·180/π` for a bottom Dock.

## Trigger geometry

The bar-frame function computes two rectangles after laying out the tiles.
`inBarRect` spans the bar's own extent along the edge, from the displaced
`barLeft − distanceSides` to the displaced `barRight + distanceSides`, and
across the edge from 10 pt beyond the tiles' outer edge (including the
magnified outer edge, shifted by `autoHideOffset`) to the screen edge, rounded
to whole points. It is what `myInBar` is tested against for magnification and
label handling. `myRect`, whose CGRect form is `rect`, is the window server
shape. With autohide off it equals `inBarRect`. With autohide on it is widened
to the whole stage edge, that is `screenBoundsExcludingMenuBar` along the
edge, and keeps the same band across it; once the bar has slid far enough that
the band is under 2 pt, both rectangles become a 2 pt strip along the entire
edge, and the shape is re-sent to the window server. At activation
`-[DockBar activate]` starts with that 2 pt full-length strip.

So the hidden Dock shows for a pointer resting anywhere along its screen edge,
not only within the Dock's width, and the pointer must be within the last
2 pt of the screen. While shown, moving the pointer more than 10 pt above the
tiles (for a bottom Dock) anywhere along the width leaves the shape and starts
the hide; the horizontal position does not matter. A left or right Dock uses
the same construction with the axes swapped.

## Side finding: the ramp curve

`DockFloatAnimatedProperty`'s direct initialiser (`0x1002dd2d8`) stores its
argument at offset 0x18, the field the step function tests before choosing
`0.5 − 0.5·cos(π·p)` over linear progress. The DockBar setup function creates
both `autoHide` (`0x100258620`) and `fish` (`0x10025876c`) with that argument
equal to 1, so both ramps are cosine-eased in time. DOCK-MAGNIFICATION.md
describes the fish ramp as linear because no easing function appeared to be
attached; the paired store in the initialiser is what that reading missed, and
the magnification unit should be re-checked against it.

## Limitations

The window server's latency in delivering background enter and exit events,
and dispatch's actual timer slack, are outside this binary and were not
measured. `stageWidth` and `stageHeight` are the width and height of
`screenBoundsExcludingMenuBar`; how that descriptor is built from the display
was not traced. The display-switching path, the temporarily revealed Dock
(`DockVisibility`), the drag-leave path and the dig variant are recorded but
not modelled. Three REA runs ended in a provider timeout, two while a second Ghidra
instance was running and one alone; all were repeated successfully and the
failed envelopes are kept beside the dossiers.
Addresses, offsets and constants are specific to build 26A5421a.

## Evidence ledger

| Subject | Operation | Canonical Evidence ID |
| --- | --- | --- |
| procedure search (autohide names) | search | `ev_b46082d67b6ed1b3b499fb324077b641c87618121b350ba58c1bc47a8c73a76b` |
| `0x100070534` DockBarMouseEventHandler::_handleMoveEvent:type: | function | `ev_a6a3841f630594e07696a9d38fe49a1e203136f26e6a468b92cfd8e95fe67bcd` |
| `0x10006edbc` DockBarMouseEventHandler::initWithConnection: | function | `ev_9de5e7280d80fdc0113a888c10b3fbad631a75d66e754e67d53b83731ab5bbed` |
| `0x10007107c` DOCKPreferences::autohideDelayPref | function | `ev_a3e1188aa4246afc774e0482aba017fd23aa6583983ea94f3898356affb1b0a9` |
| `0x100070288` DockBarMouseEventHandler::_mouseEnterHelper:location:allowSwitchingBetweenDisplays: | function | `ev_cf42c8864ddba8acb254918523de3ff74e755ad252173737acad593df6f877bc` |
| `0x10005f2c4` DockBar::startAutoShow | function | `ev_0647821ec51291354536a4085a01ef5056ab4e2ee1bfc7386622eede32ff9ba3` |
| `0x10005f59c` DockBar::startAutoHide | function | `ev_bebf3dac0c4b3036d67b9ab8b6d558c5ff3835fe266a11b6b75dda83b0cfad4b` |
| `0x100095468` DockBar::handleDockEventMouseEnter: | function | `ev_53c168c9a6e82eb47a04114c6f5fc70a78a798610d9136cb7e241a9133e971e5` |
| `0x1000956b8` DockBar::handleDockEventMouseLeave: | function | `ev_18a67f372d836a4aac46284dbe325d53c9d3cd94143fbd6a9c02f6fe1e29e510` |
| `0x100098768` DockBar::handleDockEventAutohideEnabled:setRect:context: | function | `ev_ffeb2cefe886a152ee478c193f235b5db2d21aa12166499f21ebb0a35b57571c` |
| `0x1000812e8` FUN_1000812e8 | function | `ev_aa36f5df0b640e22ebae54043b106ad31334ffb5ae26a3434bed4ec8671c1548` |
| `0x100257e34` FUN_100257e34 | function | `ev_ee10d0afaa8f854627fa3825b0a020bd5413daa6b28ae20378d198a9055fcf6e` |
| `0x1000502b4` FUN_1000502b4 | function | `ev_ddb9a9438558bab2f013487c4ed0bc0035c23cce746d82893a0893f2c08eca87` |
| `0x1000128f0` bar frame (inBarRect, myRect, event shape) | function | `ev_9b463fd4f35d2e2be1ab991cf511c8c8115719c1ce2761ef14b3718351ea0766` |

The constants in the table above are readings of the annotated `otool`
listings retained under `research/local/dock-autohide/`, not REA records; the
dossiers supply the procedure bodies, callers and the decompilation that was
checked against them.
