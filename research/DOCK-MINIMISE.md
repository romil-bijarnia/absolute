# Dock minimise effects

This records the second behavior unit under the 15 October 2026 direction:
the three effects the Dock uses to minimise a window into a tile, the clock
that drives them and the duration it picks. The reference is macOS 27.0, build
26A5421a, the same Dock copy as [DOCK-MAGNIFICATION.md](DOCK-MAGNIFICATION.md)
(SHA-256 `c8e55d01cbfa33eb68b6d90707da5fd4bd13b27349295e0e732f87eb5263488f`).
Hashed records are in [dock-minimise-findings.json](dock-minimise-findings.json);
the raw dossiers stay under `research/local/dock-magnification/`.

## Analysis boundary

Everything below is a static reading of machine code analysed with REA 6.4.0
and Ghidra 12.1.3. No Dock process was attached to, executed or modified, no
minimise was recorded on screen, and no preference was changed. The model has
not yet been compared against a frame capture of the real effect.

## Shape of the machinery

`DockBar::handleDockEventMinimizeWindow:context:` receives the tile for the
window being minimised, inserts it into the bar and reads `effectDur`. It then
calls `_handleMinimizeWindow:animate:duration:`, which starts a
`DockFloatAnimatedProperty` from 0 to 1 over that duration and attaches
`0x100026514` as the property's update: on every step it writes
`0.5 − 0.5 · cos(π · value)` into the tile as the transition progress and marks
the Dock for update. The property's own step (`0x1000502b4`) is linear; the
cosine lives in that update, so every effect receives a cosine-eased clock.

The same handler picks the Genie direction from the bar's orientation: a bottom
Dock sends windows above it down (direction 1) and windows below it up (2), a
right Dock sends them right (3) and a left Dock sends them left (4).

`DOCKWindowTile::updateTransition` runs per frame. It derives the target image
rectangle inside the tile from the tile's rectangle and its icon rectangle in
1/128 units, inset by `tileInset`, then calls the dispatcher `0x100026ba8`,
which reads `minimizeEffect` (1 Genie, 2 Scale, 3 Suck), forces Scale when the
transition's flag byte is set, and calls one builder. Each builder ends in
`CGSSetWindowWarp(connection, windowID, columns, rows, mesh)` with a mesh of
`(local x, local y, screen x, screen y)` floats. The Genie builder also writes a
reveal value back into the transition, and `updateTransition` turns it into the
mask that shows the tile's thumbnail as the window arrives.

Coordinates are points with y increasing upward; the Dock's rectangles are
`(x, y, width, height)` doubles for the window and `(x0, y0, x1, y1)` floats
for the target.

## Genie (`0x100026c64`)

Let the window have leading and trailing edges across the travel axis, far and
near edges along it (far is the edge away from the Dock), length `h` along the
axis, and let the target have the same. With `ramp(v) = 0.5 − 0.5 · cos(π · v)`
and `steps(d) = floor(ln(|d| / 2 + 1)) · 50`:

```
L        = target.leading − window.leading
R        = target.trailing − window.trailing
overlap  = max(0, target.far − window.near)
travel   = −h if overlap > 0 else target.far − window.far        T = |travel|
A        = steps(max(2 · overlap, (|L| + |R|) / 8))               squeeze budget
B        = steps(T)                                               slide budget
enter    = B · acos(1 − 2 · |travel + h| / T) / π                 slide step at which the body reaches the tile
A, lead  = (A, A − enter) if A > enter else (enter, 0)
total    = p · (B + lead)
squeeze  = ramp(clamp(total, 0, A) / A)
slide    = ramp(clamp(total − lead, 0, B) / B)
centre   = window.far + overlap · squeeze
far      = centre + travel · slide                                 current far edge
σ(y)     = ramp((y − centre) / trunc(travel + 0.5))               funnel profile, fixed in space
edge(y)  = window.edge + L · squeeze · σ(y)   (and R for the trailing edge)
```

The squeeze forms the funnel in place while the window has not moved; the
slide then carries the body down the fixed profile. `enter` is chosen so that
the funnel is fully formed exactly when the body's natural near edge reaches
the target's far edge, which `testFunnelFinishesFormingAsTheBodyReachesTheTile`
checks.

Rows run from `far` to `max(far − h, target.far)` while sliding (to `far − h`
before), subdivided by `0x1000276d8`: a midpoint recursion that stops when a
segment is under 8 pt, or under 128 pt with the midpoint offsets within 0.6 pt
of the straight line between its ends, in single precision; a global call
counter of 64 and a row cap of 400 bound it. Once `|travel + h| < T · slide`
one more row is added at `max(far − h, target.near)` with the full squeeze, so
the mesh extends into the tile. The mesh is two points per row, local
coordinates `(0, v)` and `(width, v)` with `v` linear over the mesh's extent,
rows ordered by increasing screen coordinate; a horizontal Dock sends the same
rows as two rows of N columns.

The reveal written back is `clamp(1 − remaining / (h − target.length), 0, 1)`
with `remaining = T − T · slide`, or 1 only at the end when the window is no
longer than the target. It starts when the body's natural near edge passes the
target's near edge and reaches 1 as the far edge lands.

## Scale (`0x100037fb4`)

`e = ramp(p)` (the cosine applied a second time to the already eased clock),
each corner of the window moves `e` of the way to the matching target corner,
and the result is a 2 × 2 mesh. The transition flag the dispatcher checks
becomes 1 once `e ≥ 1`.

## Suck (`0x100038164`)

Not offered in System Settings but present and selectable as
`mineffect suck`. `e = ramp(p)` again. The grid has `clamp(trunc(size / 70), 1, 19)`
cells along each axis. `reach` is the largest displacement among the four
same-position corner pairs. Every grid point moves toward its place in the
target by `min(distance, reach · e)`: all points travel at the same speed, so
near ones arrive first and all have arrived at `e = 1`.

## Duration

`DockBar::effectDur` holds milliseconds. The helper that applies a changed
`mineffect` (`0x100059c80`) sets 500 for Genie, 400 for Suck and 200 for Scale;
`Tile::doCommand:`, the Dock's own context-menu command path, sets 400 for
Suck and 200 otherwise (`0x1000305a0`), so a Genie chosen from the Dock's menu
runs at 200 ms until the preference path next applies. `DockMinimise` carries
the 500/400/200 set as its defaults and takes any duration. The event
handler multiplies by 10 under the slow-motion modifier and by 2 under a
second modifier, read through `CGSInputModifierKeyState`; the masks are
recorded by value. `DockGlobals.genieSpeed` is read from the `genie-speed`
preference with a default of 0.5 and is not consulted on this path.

## Implementation and check

[`DockMinimise`](../Sources/AbsoluteCore/DockMinimise.swift) in `AbsoluteCore`
implements the clock, the direction choice, all three builders and the reveal,
computing the Genie in a canonical frame that mirrors the Dock's four direction
branches. [Its tests](../Tests/AbsoluteCoreTests/DockMinimiseTests.swift) check
the step budgets, the clock, the untouched window at rest, the landed window
inside the target, the funnel-formation invariant, the phase ordering, the
profile's monotonic offsets and segment rule, the reveal's onset and growth,
the upward and leftward mirrors, the Scale corners and double ease, the Suck
grid sizes and its equal-speed motion. All fifteen pass on macOS, alongside
the eleven magnification tests.

[`dock-minimise-demo.html`](dock-minimise-demo.html) draws the three effects
with the same arithmetic, with the real durations, the Shift slow motion, a
progress scrubber, three Dock positions and an optional mesh overlay. It was
rendered headlessly at several progress values without script errors.

## Limitations

The landed edges sit a few thousandths of a point short of the target because
the Dock truncates the travel to a whole number of points before shaping the
profile; the model keeps that. The second arrival pass that fades the warped
window out once the reveal completes, the restore direction, the window chrome
and the tile's icon art are outside this unit. Addresses are specific to build
26A5421a.

## Evidence ledger

| Subject | Operation | Canonical Evidence ID |
| --- | --- | --- |
| procedure search (minimise names) | search | `ev_bb4e0d190271f61881cd736bc5c0be77b60b8d268c1ef08964a0b2bcc6cc841b` |
| `0x100026ba8` effect dispatcher | function | `ev_6c636d1da3acb34c72df999ee26f91eb6d6d709333485c1226343fdf939520c4` |
| `0x100026c64` Genie builder | function | `ev_daad798ab9bed55ef4ca55415e56b49e2f5749ab7014dfd6ff0304e334667045` |
| `0x1000276d8` Genie subdivision | function | `ev_a45d93da01998aa7e105158189112bfc92ae4ef449d36482c49c179c8e32c6ff` |
| `0x100037fb4` Scale builder | function | `ev_155d930b8b220b21d2c92590c98cb70e00debc89bfbc0f72240a4200cce17b4b` |
| `0x100038164` Suck builder | function | `ev_1f8dfab4274777ee46cb7fa664beb320af7e66335a5600b886e8592722575fed` |
| `0x100026514` transition update | function | `ev_f35dea1b005012f14e9b788e060ab0162cc58ef2a7092d9d31af71f334ac7fc7` |
| `0x1000502b4` animated-property step | function | `ev_ddb9a9438558bab2f013487c4ed0bc0035c23cce746d82893a0893f2c08eca87` |
| `DOCKWindowTile::updateTransition` | function | `ev_22d0fa9bf9382d979937aeb9d3a618304b8e502e632e8d8a059a97f16264b894` |
| `DOCKWindowTile::beginMinMax:minimizing:animate:` | function | `ev_1634bf548c812b60e56513d7a4c750d5e57726c7136967e4be2be1411cf7fe55` |
| `DockBar::_handleMinimizeWindow:animate:duration:` | function | `ev_b6d990a468592f7cedba58597ddc8960942447fab6dae5e7a8a48caa9abb4afd` |
| `DockBar::handleDockEventMinimizeWindow:context:` | function | `ev_83d3780278cfacb6a4b08f7a80a3d9376b759b5d2d7af80569a07700b2dd495f` |
| `DockBar::setEffectDur:` | function | `ev_c38664f880d4c59fc85dcfa89f299af9776993279445b3fd6414d4bba3bf762d` |
| `Tile::doCommand:` duration site | function | `ev_dd82c068f5524324f52c03575863ce3636fad5d902244d0a49b24ec4bda081fc` |
| `0x100059c80` effect-change duration site | function | `ev_5477da3129b14d5b4b2b7e43ca6b58c2bdbbb26d8900326f3e364fe460f0d393` |

The duration constants were read from the disassembly inside those two
functions at the call sites of `setEffectDur:`, and the `genie-speed` default
from the preference loader at `0x100245a00`; the constants themselves are
`otool` readings, not REA records.
`python3 script/research_dock_minimise.py` reproduces the pass; with
`--skip-rea` it rebuilds the report from the retained records.
