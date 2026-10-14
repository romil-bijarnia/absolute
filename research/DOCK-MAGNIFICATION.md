# Dock magnification

This records the first behavior unit under the 15 October 2026 direction:
one macOS behavior observed on the reference Mac, written as a specification
with an executable check, and implemented as an Absolute component. The
behavior is Dock magnification, which Dock.app calls "fish". The reference is
macOS 27.0, build 26A5421a. Hashed records are in
[dock-magnification-findings.json](dock-magnification-findings.json).

## Artifact and analysis boundary

The installed `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock` is a
thin arm64e executable of 4,843,616 bytes with SHA-256
`c8e55d01cbfa33eb68b6d90707da5fd4bd13b27349295e0e732f87eb5263488f`. A byte copy
under `research/local/dock-magnification/` was analysed with REA 6.4.0 and
Ghidra 12.1.3. The running Dock was not attached to, executed or modified, and
no Dock preference was changed. Everything below is a static reading of
machine code; the model has not been compared against a recording of the
real Dock.

Ghidra's Objective-C analysis named the accessor methods, which located the
state in `DockBar`: `fish` (a `DockFloatAnimatedProperty`), `fishCenter`,
`fishSize`, `realScale`, `currentFish`, `distanceSides`, `forcedFisheye`,
`largeSize`, `tileSize` and the `magnification` flag. Three unnamed functions
called from `-[DockBar updateWithContext:showDockWindow:transaction:]` and
`-[DockBar quitUpdate]` carry the geometry, in this order on every update:

| Address | Role |
| --- | --- |
| `0x100011b54` | Fish state: clamps the pointer to the bar, then sets `fishSize`, `realScale` and `currentFish`. |
| `0x100011de8` | Per tile: displaces both tile edges and sets the tile frame. |
| `0x1000128f0` | Bar frame: displaces the bar's two ends and pads them with `distanceSides`. |

## Observed model

Let `t` be `tileSize`, `L` be `largeSize`, `c` be `fishCenter` and `f` be the
animated `fish` value in `[0, 1]`. With magnification on and `L > t`:

```
fishSize    = 3 · t                                       (-[DockBar fSize] returns 3.0)
realScale   = f · (L − t) / 2 ÷ sin(π · t / (4 · fishSize))
currentFish = f · (L − t)
S(d)        = −1 if d ≤ −fishSize, +1 if d ≥ fishSize, else sin(π · d / (2 · fishSize))
D(x)        = x + realScale · S(x − c)
```

`D` displaces any coordinate along the bar axis (x for a bottom Dock, y for a
side Dock). A tile with unmagnified position `p`, width `w` and centre
`m = p + w/2` occupies `[D(p), D(p + w)]` along the bar, and its size across the
bar is `D(m + t/2) − D(m − t/2)`. For an ordinary tile these two lengths agree.
The bar itself spans `[D(barLeft) − distanceSides, D(barRight) + distanceSides]`.
Otherwise `realScale` and `currentFish` are zero and `D` is the identity.

The `sin` in the denominator is the normaliser that makes the tile under the
pointer measure exactly `L`: its edges sit at `±t/2`, so it grows by
`2 · realScale · sin(π · t / (4 · fishSize)) = f · (L − t)`. Tiles more than
`fishSize + t/2` from the pointer are shifted but not resized. The profile is
the integral of a cosine bump, which is why neighbours grow by the difference
of two sines rather than by a scale factor.

When an `externalFishTile` is set the centre is that tile's centre instead of
the pointer. Vertical placement adds `autoHideOffset − distanceBottom` and a
5-point inset; the bar-frame function also carries ±10 and 2-point window
slack. These are placement details outside this unit's contract.

## Ramp

`-[DockBar startFishing]` animates `fish` to 1 and `-[DockBar stopFishing]`
animates it to 0. Outside a drag the duration in milliseconds is

```
duration = floor(fishSpeed · ln(|Δ| / 2 + 1) + 1)        (-[DockBar fishSpeed] returns 42.0)
```

where `Δ` is the size still to change: `L − (t + currentFish)` on entry and
`currentFish` on exit. For the default 48 → 128 point magnification from rest
that is 156 ms. During a drag `moveSpeed` is used instead.

`DockFloatAnimatedProperty` keeps `from`, `now`, `to`, `easingFunction`, `start`
and `duration`. Its time step clamps `(now − start) / duration` to `[0, 1]`, maps
it through `0.5 − 0.5 · cos(π · p)` only when an easing function is attached,
and then interpolates linearly from `from` to `to`. No code in the executable
stores an easing function on an animated property, so the fish ramp is linear
in time.

## Implementation and check

[`DockMagnification`](../Sources/AbsoluteCore/DockMagnification.swift) in
`AbsoluteCore` implements the model and the ramp with the two measured
constants. [Its tests](../Tests/AbsoluteCoreTests/DockMagnificationTests.swift)
check the exact centre size, the untouched far tiles, symmetry and monotonic
fall-off, continuity at the bump edges, the neighbour growth as a difference
of sines, contiguous layout of a row, the ramp durations and a single-precision
transcription of the decompiled arithmetic. All eleven pass on macOS.

The GTK Linux host does not yet magnify its Dock; wiring this model into its
pointer handling is the next unit on the Dock.

## Evidence ledger

| Subject | Operation | Canonical Evidence ID |
| --- | --- | --- |
| Dock copy | inspect (29,434 procedures) | `ev_85af54bc9c359715bbf2f34409497c1ea1c752ddb3c67d4013d78c18eaf78996` |
| `0x100011b54` fish state | function | `ev_db14f49a6e9d93be3bb7f60016519034efa6ee7d19ffa58aefdea05590efc99d` |
| `0x100011de8` per-tile layout | function | `ev_f5f09a4463deb462cbbddae21369a5f8d63ed62648c88f3d38b15d8ed2e16c89` |
| `0x1000128f0` bar frame | function | `ev_9b463fd4f35d2e2be1ab991cf511c8c8115719c1ce2761ef14b3718351ea0766` |
| `0x10007e930` update loop | function | `ev_9143415d350ef71f5bd80b5deaf89759f97a6ac3ce31103e26f915bb15109220` |
| `0x1000502b4` animated-property step | function | `ev_ddb9a9438558bab2f013487c4ed0bc0035c23cce746d82893a0893f2c08eca87` |
| `DockBar::`/`DockFloatAnimatedProperty::` names | search | `ev_69ecb48060b8cba759377d332fc4e6d7c35e296bd97ecf804605f8107f1c39ba` |

The constants were decoded from the getters' first instructions:
`-[DockBar fSize]` at `0x10025324c` is `fmov s0, #3.0` (`1e211000`) and
`-[DockBar fishSpeed]` at `0x100253240` is `mov w8, #0x42280000; fmov s0, w8`.
`python3 script/research_dock_magnification.py` reproduces the pass; with
`--skip-rea` it rebuilds the report from the retained records.

## Side findings

The `cos` users first suspected of being the magnification curve are the
minimise effects: `0x100026c64` builds the Genie path and `0x100037fb4`,
`0x100038164` and `0x100026514` interpolate rects with `0.5 − 0.5 · cos(π · p)`.
Their dossiers are retained locally for a later minimise-effect unit.

## Limitations

Single-precision arithmetic in the Dock versus double precision here is
bounded at 0.01 pt by the transcription test, not measured on screen. The
addresses are specific to build 26A5421a. Pointer sampling rate, the
`forcedFisheye` toggle, the drag path and touch magnification are recorded in
the dossiers but not modelled.
