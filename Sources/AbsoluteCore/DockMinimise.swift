import Foundation

/// Window minimise effects as observed in macOS 27.0 (build 26A5421a) Dock.app.
///
/// When a window minimises, the Dock drives a transition value from 0 to 1 on a
/// cosine-eased clock and, on every frame, sends the screen server a warp mesh
/// for the window through `CGSSetWindowWarp`. Three effects build that mesh:
/// Genie (a two-column funnel), Scale (a rectangle sliding into the tile) and
/// the hidden Suck (a grid pulled toward the tile at uniform speed). The Genie
/// also reports how much of the tile's thumbnail to reveal as the window lands.
///
/// Coordinates are points with y increasing upward, the convention the Dock's
/// geometry uses. `target` is the image rectangle inside the Dock tile that the
/// window travels into. See `research/DOCK-MINIMISE.md` for the evidence.
public struct DockMinimise: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var minX: Double { x }
        public var maxX: Double { x + width }
        public var minY: Double { y }
        public var maxY: Double { y + height }
    }

    /// `com.apple.dock mineffect`, as the Dock numbers it.
    public enum Effect: Int, Sendable {
        case genie = 1, scale = 2, suck = 3
    }

    /// The direction the window travels into the Dock, as the Dock numbers it:
    /// a bottom Dock sends windows above it down (1) and windows below it up (2),
    /// a right Dock sends them right (3) and a left Dock sends them left (4).
    public enum Direction: Int, Sendable {
        case down = 1, up = 2, right = 3, left = 4

        public var isVertical: Bool { self == .down || self == .up }
    }

    /// One mesh vertex: a point in the window's own coordinates and where it lands on screen.
    public struct WarpPoint: Equatable, Sendable {
        public var local: Point
        public var global: Point
        public init(local: Point, global: Point) { self.local = local; self.global = global }
    }

    /// A `columns × rows` mesh in row-major order, the layout `CGSSetWindowWarp` takes.
    public struct Mesh: Equatable, Sendable {
        public var columns: Int
        public var rows: Int
        public var points: [WarpPoint]
        public init(columns: Int, rows: Int, points: [WarpPoint]) {
            self.columns = columns; self.rows = rows; self.points = points
        }
        public subscript(row: Int, column: Int) -> WarpPoint { points[row * columns + column] }
    }

    /// One Genie profile sample: a position along the travel axis and the two
    /// edge displacements, measured from the window's own edges toward the target's.
    public struct GenieRow: Equatable, Sendable {
        public var position: Double
        public var leadingOffset: Double
        public var trailingOffset: Double
        public init(position: Double, leadingOffset: Double, trailingOffset: Double) {
            self.position = position; self.leadingOffset = leadingOffset; self.trailingOffset = trailingOffset
        }
    }

    public struct GenieFrame: Equatable, Sendable {
        /// Profile rows ordered by increasing screen coordinate along the travel axis.
        public var rows: [GenieRow]
        public var mesh: Mesh
        /// How much of the tile's thumbnail the Dock shows, 0 until the window
        /// body enters the tile and 1 when it has landed.
        public var reveal: Double
        /// `0.5 − 0.5·cos` of the squeeze phase, 1 once the funnel is fully formed.
        public var squeeze: Double
        /// `0.5 − 0.5·cos` of the slide phase, 1 once the window has landed.
        public var slide: Double
    }

    /// The step budget grows by this per natural-log unit of distance.
    public static let stepsPerLogUnit: Double = 50
    /// The Suck effect places one grid line per this many points.
    public static let suckCellSize: Double = 70
    /// The Suck grid never exceeds this many cells along either axis.
    public static let suckMaxCells = 19
    /// The Genie subdivides profile segments until they are shorter than this.
    public static let genieMinimumSegment: Double = 8
    /// Segments shorter than this stop subdividing once their midpoint is within
    /// `genieLinearTolerance` of a straight line.
    public static let genieLinearSegment: Double = 128
    public static let genieLinearTolerance: Double = 0.6
    /// The Dock caps the profile at this many rows.
    public static let genieMaximumRows = 400

    public var window: Rect
    public var target: Rect
    public var direction: Direction
    /// The transition value the Dock feeds the effects: already cosine-eased in time, 0 to 1.
    public var progress: Double

    public init(window: Rect, target: Rect, direction: Direction, progress: Double) {
        self.window = window
        self.target = target
        self.direction = direction
        self.progress = progress
    }

    // MARK: Timing

    /// `DockBar::effectDur` in milliseconds as the Dock sets it when a
    /// `mineffect` preference is applied.
    public static func defaultDuration(for effect: Effect) -> Double {
        switch effect {
        case .genie: return 500
        case .scale: return 200
        case .suck: return 400
        }
    }

    /// The Dock multiplies the duration by this under the slow-motion modifier.
    public static let slowMotionFactor: Double = 10

    /// The transition value at `elapsed` milliseconds into a run of `duration`
    /// milliseconds: the Dock's animated property moves linearly and the
    /// minimise update maps it through `0.5 − 0.5·cos(π·p)`.
    public static func progress(elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        let linear = min(max(elapsed / duration, 0), 1)
        return 0.5 - 0.5 * cos(.pi * linear)
    }

    /// The direction the Dock picks for a window given the Dock's edge and
    /// whether the window sits above the Dock (only meaningful for a bottom Dock).
    public static func direction(dockEdge: DockEdge, windowAboveDock: Bool = true) -> Direction {
        switch dockEdge {
        case .bottom: return windowAboveDock ? .down : .up
        case .left: return .left
        case .right: return .right
        }
    }

    public enum DockEdge: Sendable { case bottom, left, right }

    // MARK: Genie

    /// Step budget for a distance: `floor(ln(d / 2 + 1)) · 50`, zero when there is nothing to cover.
    public static func steps(for distance: Double) -> Double {
        (log(abs(distance) * 0.5 + 1)).rounded(.down) * stepsPerLogUnit
    }

    private static func ramp(_ value: Double) -> Double { 0.5 - 0.5 * cos(.pi * value) }

    /// The Genie frame for the current progress.
    public func genie() -> GenieFrame {
        // Work in a canonical frame where the window travels toward decreasing `along`.
        let frame = CanonicalFrame(direction: direction)
        let w = frame.canonical(window)
        let t = frame.canonical(target)

        let leading = t.minAcross - w.minAcross
        let trailing = t.maxAcross - w.maxAcross
        let overlap = max(0, t.maxAlong - w.minAlong)
        let travel = overlap > 0 ? -w.length : t.maxAlong - w.maxAlong
        let distance = abs(travel)

        var squeezeBudget = Self.steps(for: max(2 * overlap, (abs(leading) + abs(trailing)) * 0.125))
        let slideBudget = Self.steps(for: distance)
        let entryArgument = distance > 0 ? 1 - 2 * abs(travel + w.length) / distance : 1
        let entryStep = slideBudget * acos(min(max(entryArgument, -1), 1)) / .pi
        let lead: Double
        if squeezeBudget > entryStep {
            lead = squeezeBudget - entryStep
        } else {
            squeezeBudget = entryStep
            lead = 0
        }

        let total = (slideBudget + lead) * progress
        let squeezeStep = min(max(total, 0), squeezeBudget)
        let slideStep = min(max(total - lead, 0), slideBudget)
        let squeeze = squeezeBudget > 0 ? Self.ramp(squeezeStep / squeezeBudget) : 1
        let slide = slideBudget > 0 ? Self.ramp(slideStep / slideBudget) : 1

        let leadingSqueezed = leading * squeeze
        let trailingSqueezed = trailing * squeeze
        let centre = w.maxAlong + overlap * squeeze
        let far = centre + travel * slide
        let naturalNear = far - w.length
        let anchor = slide > 0 ? max(naturalNear, t.maxAlong) : naturalNear
        let span = Double(Int(travel + 0.5))

        func profile(_ position: Double) -> Double {
            span != 0 ? Self.ramp((position - centre) / span) : 1
        }
        func row(_ position: Double) -> GenieRow {
            let factor = profile(position)
            return GenieRow(position: position, leadingOffset: leadingSqueezed * factor, trailingOffset: trailingSqueezed * factor)
        }

        var rows = [row(far)]
        var budget = GenieSubdivision()
        budget.subdivide(from: far, to: anchor, centre: centre, span: span,
                         leading: leadingSqueezed, trailing: trailingSqueezed, into: &rows)
        rows.append(row(anchor))
        if abs(travel + w.length) < abs(travel * slide) {
            rows.append(GenieRow(position: max(naturalNear, t.minAlong),
                                 leadingOffset: leadingSqueezed, trailingOffset: trailingSqueezed))
        }
        // Report positions as screen coordinates along the travel axis, ordered
        // the way the Dock lays the mesh out: increasing screen coordinate, with
        // the window-local coordinate running from 0 at the lowest row.
        for index in rows.indices { rows[index].position = frame.screenAlong(rows[index].position) }
        rows.sort { $0.position < $1.position }

        let lowest = rows.first!.position
        let extent = rows.last!.position - lowest
        var points: [WarpPoint] = []
        points.reserveCapacity(rows.count * 2)
        for sample in rows {
            let local = extent > 0 ? (sample.position - lowest) * (w.length / extent) : 0
            let leadingEdge = frame.screen(alongScreen: sample.position, across: w.minAcross + sample.leadingOffset)
            let trailingEdge = frame.screen(alongScreen: sample.position, across: w.maxAcross + sample.trailingOffset)
            points.append(WarpPoint(local: frame.local(along: local, across: 0), global: leadingEdge))
            points.append(WarpPoint(local: frame.local(along: local, across: w.breadth), global: trailingEdge))
        }
        let mesh = direction.isVertical
            ? Mesh(columns: 2, rows: rows.count, points: points)
            : Mesh(columns: rows.count, rows: 2, points: Self.transposed(points, rows: rows.count))

        let remaining = distance - abs(travel * slide)
        let reveal: Double
        if w.length <= t.length {
            reveal = remaining == 0 ? 1 : 0
        } else {
            let window = w.length - t.length
            reveal = remaining < window ? 1 - remaining / window : 0
        }
        return GenieFrame(rows: rows, mesh: mesh, reveal: reveal, squeeze: squeeze, slide: slide)
    }

    /// Reorders `[row][edge]` pairs into the `[edge][row]` layout a horizontal Genie sends.
    private static func transposed(_ points: [WarpPoint], rows: Int) -> [WarpPoint] {
        var result: [WarpPoint] = []
        result.reserveCapacity(points.count)
        for edge in 0..<2 {
            for row in 0..<rows { result.append(points[row * 2 + edge]) }
        }
        return result
    }

    /// The Dock's recursive midpoint subdivision of the funnel profile.
    private struct GenieSubdivision {
        var calls = 0
        var emitted = 0

        mutating func subdivide(from start: Double, to end: Double, centre: Double, span: Double,
                                leading: Double, trailing: Double, into rows: inout [GenieRow]) {
            guard calls < 64 else { calls += 1; return }
            calls += 1
            func profile(_ position: Double) -> Double {
                span != 0 ? DockMinimise.ramp((position - centre) / span) : 1
            }
            let endFactor = profile(end)
            var start = start
            while true {
                guard abs(end - start) >= DockMinimise.genieMinimumSegment else { return }
                let middle = (end + start) * 0.5
                let startFactor = profile(start)
                let middleFactor = profile(middle)
                let leadingMiddle = Float(leading * middleFactor)
                let trailingMiddle = Float(trailing * middleFactor)
                if abs(end - start) < DockMinimise.genieLinearSegment {
                    let leadingLinear = (Float(leading * endFactor) + Float(leading * startFactor)) * 0.5
                    let trailingLinear = (Float(trailing * endFactor) + Float(trailing * startFactor)) * 0.5
                    if abs(leadingLinear - leadingMiddle) < Float(DockMinimise.genieLinearTolerance)
                        && abs(trailingLinear - trailingMiddle) < Float(DockMinimise.genieLinearTolerance) {
                        return
                    }
                }
                subdivide(from: start, to: middle, centre: centre, span: span,
                          leading: leading, trailing: trailing, into: &rows)
                guard rows.count < DockMinimise.genieMaximumRows else { return }
                rows.append(GenieRow(position: middle, leadingOffset: Double(leadingMiddle), trailingOffset: Double(trailingMiddle)))
                emitted += 1
                guard calls < 64 else { return }
                calls += 1
                start = middle
            }
        }
    }

    // MARK: Scale

    /// The Scale frame: the window rectangle eased toward the target as a 2 × 2 mesh.
    /// `settled` is what the Dock stores once the eased value reaches 1.
    public func scale() -> (mesh: Mesh, settled: Bool) {
        let eased = Self.ramp(progress)
        func lerp(_ from: Double, _ to: Double) -> Double { (to - from) * eased + from }
        let minX = lerp(window.minX, target.minX), minY = lerp(window.minY, target.minY)
        let maxX = lerp(window.maxX, target.maxX), maxY = lerp(window.maxY, target.maxY)
        let points = [
            WarpPoint(local: Point(x: 0, y: 0), global: Point(x: minX, y: minY)),
            WarpPoint(local: Point(x: window.width, y: 0), global: Point(x: maxX, y: minY)),
            WarpPoint(local: Point(x: 0, y: window.height), global: Point(x: minX, y: maxY)),
            WarpPoint(local: Point(x: window.width, y: window.height), global: Point(x: maxX, y: maxY)),
        ]
        return (Mesh(columns: 2, rows: 2, points: points), eased >= 1)
    }

    // MARK: Suck

    /// Grid cells along an axis of the given length.
    public static func suckCells(for length: Double) -> Int {
        min(max(Int(length / suckCellSize), 1), suckMaxCells)
    }

    /// The Suck frame: every grid point moves toward its place in the target at
    /// the same speed, so near points arrive before far ones.
    public func suck() -> (mesh: Mesh, settled: Bool) {
        let eased = Self.ramp(progress)
        let columns = Self.suckCells(for: window.width)
        let rows = Self.suckCells(for: window.height)
        let corners: [(Point, Point)] = [
            (Point(x: window.minX, y: window.minY), Point(x: target.minX, y: target.minY)),
            (Point(x: window.maxX, y: window.minY), Point(x: target.maxX, y: target.minY)),
            (Point(x: window.minX, y: window.maxY), Point(x: target.minX, y: target.maxY)),
            (Point(x: window.maxX, y: window.maxY), Point(x: target.maxX, y: target.maxY)),
        ]
        let reach = corners.map { hypot($0.0.x - $0.1.x, $0.0.y - $0.1.y) }.max() ?? 0
        var points: [WarpPoint] = []
        points.reserveCapacity((columns + 1) * (rows + 1))
        for row in 0...rows {
            let sourceY = window.minY + window.height * Double(row) / Double(rows)
            let targetY = target.minY + (target.maxY - target.minY) * Double(row) / Double(rows)
            for column in 0...columns {
                let sourceX = window.minX + window.width * Double(column) / Double(columns)
                let targetX = target.minX + (target.maxX - target.minX) * Double(column) / Double(columns)
                let dx = targetX - sourceX, dy = targetY - sourceY
                let distance = hypot(dx, dy)
                var global = Point(x: sourceX, y: sourceY)
                if distance > 0 {
                    let remaining = min(max(distance - reach * eased, 0), reach)
                    let fraction = (distance - remaining) / distance
                    global = Point(x: sourceX + fraction * dx, y: sourceY + fraction * dy)
                }
                points.append(WarpPoint(local: Point(x: sourceX - window.minX, y: sourceY - window.minY), global: global))
            }
        }
        return (Mesh(columns: columns + 1, rows: rows + 1, points: points), eased >= 1)
    }

    // MARK: Canonical frame

    /// Maps screen coordinates to (along, across) so that the Dock lies toward
    /// decreasing `along`, mirroring the Dock's four direction branches.
    private struct CanonicalFrame {
        let direction: Direction

        struct Box {
            var minAlong: Double, maxAlong: Double, minAcross: Double, maxAcross: Double
            var length: Double { maxAlong - minAlong }
            var breadth: Double { maxAcross - minAcross }
        }

        func canonical(_ rect: Rect) -> Box {
            switch direction {
            case .down: return Box(minAlong: rect.minY, maxAlong: rect.maxY, minAcross: rect.minX, maxAcross: rect.maxX)
            case .up: return Box(minAlong: -rect.maxY, maxAlong: -rect.minY, minAcross: rect.minX, maxAcross: rect.maxX)
            case .right: return Box(minAlong: -rect.maxX, maxAlong: -rect.minX, minAcross: rect.minY, maxAcross: rect.maxY)
            case .left: return Box(minAlong: rect.minX, maxAlong: rect.maxX, minAcross: rect.minY, maxAcross: rect.maxY)
            }
        }

        /// The screen coordinate along the travel axis for a canonical `along` value.
        func screenAlong(_ along: Double) -> Double {
            switch direction {
            case .down, .left: return along
            case .up, .right: return -along
            }
        }

        func screen(alongScreen: Double, across: Double) -> Point {
            direction.isVertical ? Point(x: across, y: alongScreen) : Point(x: alongScreen, y: across)
        }

        /// Window-local coordinates: `along` runs from the edge nearest the Dock.
        func local(along: Double, across: Double) -> Point {
            direction.isVertical ? Point(x: across, y: along) : Point(x: along, y: across)
        }
    }
}
