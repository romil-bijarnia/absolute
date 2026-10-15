// SPDX-License-Identifier: MIT
// Dock magnification as measured from macOS 27's Dock ("fish"); the same arithmetic
// as DockMagnification in AbsoluteCore. See research/DOCK-MAGNIFICATION.md.
.pragma library

var bumpTiles = 3;      // the bump reaches three tile widths either side of the pointer
var rampSpeed = 42;     // scales the logarithmic ramp duration in milliseconds

function amplitude(tile, large, fish) {
    if (large <= tile || fish <= 0) {
        return 0;
    }
    var bump = bumpTiles * tile;
    return fish * (large - tile) / 2 / Math.sin(Math.PI * tile / (4 * bump));
}

function profile(distance, tile) {
    var bump = bumpTiles * tile;
    if (distance <= -bump) {
        return -1;
    }
    if (distance >= bump) {
        return 1;
    }
    return Math.sin(Math.PI * distance / (2 * bump));
}

// Displaces one unmagnified bar coordinate.
function displace(x, center, tile, large, fish) {
    return x + amplitude(tile, large, fish) * profile(x - center, tile);
}

// Duration in milliseconds of the fish ramp for a size change.
function rampDuration(sizeChange) {
    return Math.floor(Math.log(Math.abs(sizeChange) * 0.5 + 1) * rampSpeed + 1);
}
