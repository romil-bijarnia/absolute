import Foundation

/// Dock magnification as observed in macOS 27.0 (build 26A5421a) Dock.app.
///
/// The Dock calls this effect "fish". The bar keeps a `fish` value animated
/// between 0 and 1, a `fishCenter` under the pointer, a bump half-width
/// `fishSize` of three tiles, and a `realScale` amplitude. Every point `x`
/// along the unmagnified bar is displaced to `x + realScale * S(x - center)`,
/// where `S` is a sine S-curve that saturates at the bump edges. A tile's
/// magnified extent is the displacement of its two edges; the amplitude is
/// normalised so the tile under the pointer measures exactly `largeSize`.
/// See `research/DOCK-MAGNIFICATION.md` for the evidence.
public struct DockMagnification: Equatable, Sendable {
    /// `-[DockBar fSize]`: the bump reaches three tile widths either side of the pointer.
    public static let bumpTiles: Double = 3
    /// `-[DockBar fishSpeed]`: scales the logarithmic ramp duration in milliseconds.
    public static let rampSpeed: Double = 42

    public var tileSize: Double
    public var largeSize: Double
    /// `com.apple.dock magnification`; when false the bar never magnifies.
    public var enabled: Bool
    /// The animated `fish` value, 0 at rest and 1 fully magnified.
    public var fish: Double
    /// `fishCenter`: the pointer position along the bar axis, already clamped to the bar.
    public var center: Double

    public init(tileSize: Double, largeSize: Double, enabled: Bool = true, fish: Double = 1, center: Double) {
        self.tileSize = tileSize
        self.largeSize = largeSize
        self.enabled = enabled
        self.fish = fish
        self.center = center
    }

    /// `fishSize`: half-width of the bump along the bar.
    public var bumpHalfWidth: Double { Self.bumpTiles * tileSize }

    /// Whether the Dock computes a non-zero bump for these settings.
    public var isActive: Bool { enabled && largeSize > tileSize }

    /// `realScale`: displacement amplitude, zero when inactive.
    public var amplitude: Double {
        guard isActive else { return 0 }
        let normaliser = sin(.pi * tileSize / (4 * bumpHalfWidth))
        return fish * (largeSize - tileSize) / 2 / normaliser
    }

    /// `currentFish`: the extra size the centre tile currently carries.
    public var centreGrowth: Double {
        isActive ? fish * (largeSize - tileSize) : 0
    }

    /// The saturating S-curve for a signed distance from the centre.
    public func profile(distance: Double) -> Double {
        if distance <= -bumpHalfWidth { return -1 }
        if distance >= bumpHalfWidth { return 1 }
        return sin(.pi * distance / (2 * bumpHalfWidth))
    }

    /// Displaces one unmagnified bar coordinate.
    public func displacement(_ x: Double) -> Double {
        x + amplitude * profile(distance: x - center)
    }

    /// The magnified size of a tile whose unmagnified centre is `centre`.
    public func magnifiedSize(tileCentre centre: Double) -> Double {
        displacement(centre + tileSize / 2) - displacement(centre - tileSize / 2)
    }

    /// One laid-out tile: its magnified span along the bar and its size across it.
    public struct Tile: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var size: Double
        public var length: Double { end - start }
        public init(start: Double, end: Double, size: Double) {
            self.start = start
            self.end = end
            self.size = size
        }
    }

    /// Lays out tiles given their unmagnified start positions and widths.
    public func layout(tiles: [(position: Double, width: Double)]) -> [Tile] {
        tiles.map { tile in
            let centre = tile.position + tile.width / 2
            return Tile(
                start: displacement(tile.position),
                end: displacement(tile.position + tile.width),
                size: magnifiedSize(tileCentre: centre)
            )
        }
    }

    /// Duration in milliseconds of the fish ramp for a size change, as
    /// `-[DockBar startFishing]` and `-[DockBar stopFishing]` compute it.
    public static func rampDuration(sizeChange: Double, speed: Double = rampSpeed) -> Double {
        (log(abs(sizeChange) * 0.5 + 1) * speed + 1).rounded(.down)
    }

    /// The fish value during a ramp: linear in time, clamped to the end points.
    public static func rampValue(from start: Double, to end: Double, elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return end }
        let progress = min(max(elapsed / duration, 0), 1)
        return start + (end - start) * progress
    }
}
