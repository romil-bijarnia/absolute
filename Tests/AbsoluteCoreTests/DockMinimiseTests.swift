import XCTest
@testable import AbsoluteCore

final class DockMinimiseTests: XCTestCase {
    private typealias Rect = DockMinimise.Rect
    private typealias Point = DockMinimise.Point

    /// A 1200 × 800 window with its bottom 300 points up, above a bottom Dock
    /// whose target image sits at x 600–664, y 10–74.
    private let window = Rect(x: 0, y: 300, width: 1200, height: 800)
    private let target = Rect(x: 600, y: 10, width: 64, height: 64)

    private func genie(_ progress: Double, direction: DockMinimise.Direction = .down) -> DockMinimise.GenieFrame {
        DockMinimise(window: window, target: target, direction: direction, progress: progress).genie()
    }

    /// The step budgets this geometry produces, worked by hand from the formulas.
    private var budgets: (squeeze: Double, slide: Double, entry: Double, lead: Double) {
        let slide = 300.0, squeeze = 200.0
        let entry = slide * acos(1 - 2 * (1026.0 - 800) / 1026) / .pi
        return (squeeze, slide, entry, squeeze - entry)
    }

    func testStepBudgetIsLogarithmicInDistance() {
        XCTAssertEqual(DockMinimise.steps(for: 1026), 300)
        XCTAssertEqual(DockMinimise.steps(for: -1026), 300)
        XCTAssertEqual(DockMinimise.steps(for: 0), 0)
        XCTAssertEqual(DockMinimise.steps(for: 3), 0)
        XCTAssertEqual(DockMinimise.steps(for: 4), 50)
        XCTAssertEqual(DockMinimise.steps(for: 142), 200)
    }

    func testDefaultDurationsAreTheDockPreferenceValues() {
        XCTAssertEqual(DockMinimise.defaultDuration(for: .genie), 500)
        XCTAssertEqual(DockMinimise.defaultDuration(for: .scale), 200)
        XCTAssertEqual(DockMinimise.defaultDuration(for: .suck), 400)
        XCTAssertEqual(DockMinimise.slowMotionFactor, 10)
        XCTAssertEqual(DockMinimise.Effect.suck.rawValue, 3)
    }

    func testProgressIsCosineEasedAndClamped() {
        XCTAssertEqual(DockMinimise.progress(elapsed: 0, duration: 400), 0, accuracy: 1e-12)
        XCTAssertEqual(DockMinimise.progress(elapsed: 200, duration: 400), 0.5, accuracy: 1e-12)
        XCTAssertEqual(DockMinimise.progress(elapsed: 100, duration: 400), 0.5 - 0.5 * cos(.pi / 4), accuracy: 1e-12)
        XCTAssertEqual(DockMinimise.progress(elapsed: 400, duration: 400), 1, accuracy: 1e-12)
        XCTAssertEqual(DockMinimise.progress(elapsed: 900, duration: 400), 1)
        XCTAssertEqual(DockMinimise.progress(elapsed: -5, duration: 400), 0)
        XCTAssertEqual(DockMinimise.progress(elapsed: 5, duration: 0), 1)
    }

    func testDirectionFollowsTheDockEdge() {
        XCTAssertEqual(DockMinimise.direction(dockEdge: .bottom), .down)
        XCTAssertEqual(DockMinimise.direction(dockEdge: .bottom, windowAboveDock: false), .up)
        XCTAssertEqual(DockMinimise.direction(dockEdge: .left), .left)
        XCTAssertEqual(DockMinimise.direction(dockEdge: .right), .right)
        XCTAssertEqual(DockMinimise.Direction.down.rawValue, 1)
        XCTAssertEqual(DockMinimise.Direction.left.rawValue, 4)
    }

    func testGenieAtRestIsTheUntouchedWindow() {
        let frame = genie(0)
        XCTAssertEqual(frame.squeeze, 0, accuracy: 1e-12)
        XCTAssertEqual(frame.slide, 0, accuracy: 1e-12)
        XCTAssertEqual(frame.reveal, 0)
        XCTAssertEqual(frame.rows.first!.position, 300, accuracy: 1e-9)
        XCTAssertEqual(frame.rows.last!.position, 1100, accuracy: 1e-9)
        for row in frame.rows {
            XCTAssertEqual(row.leadingOffset, 0, accuracy: 1e-9)
            XCTAssertEqual(row.trailingOffset, 0, accuracy: 1e-9)
        }
        XCTAssertEqual(frame.mesh.columns, 2)
        XCTAssertEqual(frame.mesh.rows, frame.rows.count)
        for row in 0..<frame.mesh.rows {
            let left = frame.mesh[row, 0], right = frame.mesh[row, 1]
            XCTAssertEqual(left.global.x, 0, accuracy: 1e-9)
            XCTAssertEqual(right.global.x, 1200, accuracy: 1e-9)
            XCTAssertEqual(left.local.x, 0)
            XCTAssertEqual(right.local.x, 1200)
            XCTAssertEqual(left.local.y, left.global.y - 300, accuracy: 1e-9)
        }
    }

    func testGenieLandsInsideTheTargetWithTheThumbnailRevealed() {
        let frame = genie(1)
        XCTAssertEqual(frame.squeeze, 1, accuracy: 1e-12)
        XCTAssertEqual(frame.slide, 1, accuracy: 1e-12)
        XCTAssertEqual(frame.reveal, 1, accuracy: 1e-12)
        XCTAssertEqual(frame.rows.first!.position, 10, accuracy: 1e-9)
        XCTAssertEqual(frame.rows.last!.position, 74, accuracy: 1e-9)
        // The Dock rounds the travel to a whole number of points before shaping the
        // funnel, which leaves the landed edges a few thousandths of a point short.
        for point in frame.mesh.points {
            XCTAssertTrue(abs(point.global.x - 600) < 1e-2 || abs(point.global.x - 664) < 1e-2)
            XCTAssertGreaterThanOrEqual(point.global.y, 10 - 1e-9)
            XCTAssertLessThanOrEqual(point.global.y, 74 + 1e-9)
        }
    }

    func testFunnelFinishesFormingAsTheBodyReachesTheTile() {
        let b = budgets
        let frame = genie(b.squeeze / (b.slide + b.lead))
        XCTAssertEqual(frame.squeeze, 1, accuracy: 1e-9)
        XCTAssertEqual(frame.slide, 0.5 - 0.5 * cos(.pi * b.entry / b.slide), accuracy: 1e-9)
        XCTAssertEqual(frame.rows.first!.position, 74, accuracy: 1e-6)
        XCTAssertEqual(frame.rows.last!.position, 1100 - 1026 * frame.slide, accuracy: 1e-9)
    }

    func testSqueezeLeadsTheSlideAndBothAreCosineRamps() {
        let b = budgets
        let early = genie(0.5 * b.lead / (b.slide + b.lead))
        XCTAssertGreaterThan(early.squeeze, 0)
        XCTAssertEqual(early.slide, 0, accuracy: 1e-12)
        XCTAssertEqual(early.rows.last!.position, 1100, accuracy: 1e-9)
        let late = genie(0.9)
        XCTAssertEqual(late.squeeze, 1, accuracy: 1e-12)
        XCTAssertGreaterThan(late.slide, 0.5)
        XCTAssertLessThan(late.slide, 1)
    }

    func testProfileOffsetsFollowTheFunnelTowardTheTile() {
        let frame = genie(0.6)
        XCTAssertGreaterThanOrEqual(frame.rows.count, 3)
        XCTAssertLessThanOrEqual(frame.rows.count, DockMinimise.genieMaximumRows)
        for (lower, upper) in zip(frame.rows, frame.rows.dropFirst()) {
            XCTAssertLessThan(lower.position, upper.position)
            XCTAssertGreaterThanOrEqual(lower.leadingOffset, upper.leadingOffset - 1e-6)
            XCTAssertLessThanOrEqual(lower.trailingOffset, upper.trailingOffset + 1e-6)
        }
        for row in frame.rows {
            XCTAssertGreaterThanOrEqual(row.leadingOffset, -1e-9)
            XCTAssertLessThanOrEqual(row.leadingOffset, 600 + 1e-9)
            XCTAssertLessThanOrEqual(row.trailingOffset, 1e-9)
            XCTAssertGreaterThanOrEqual(row.trailingOffset, -536 - 1e-9)
        }
        for sample in stride(from: 0.0, through: 1, by: 0.05) {
            let rows = genie(sample).rows
            for (lower, upper) in zip(rows, rows.dropFirst()) where upper.position - lower.position < 128 {
                XCTAssertLessThan(upper.position - lower.position, 128)
            }
        }
    }

    func testRevealStartsWhenTheBodyEntersTheTileAndGrowsToOne() {
        XCTAssertEqual(genie(0.3).reveal, 0)
        var previous = 0.0
        var seenPartial = false
        for sample in stride(from: 0.0, through: 1, by: 0.02) {
            let reveal = genie(sample).reveal
            XCTAssertGreaterThanOrEqual(reveal, previous - 1e-12)
            if reveal > 0 && reveal < 1 { seenPartial = true }
            previous = reveal
        }
        XCTAssertTrue(seenPartial)
        XCTAssertEqual(genie(1).reveal, 1, accuracy: 1e-12)
    }

    func testUpwardGenieMirrorsTheDownwardOne() {
        let mirroredWindow = Rect(x: 0, y: -1100, width: 1200, height: 800)
        let mirroredTarget = Rect(x: 600, y: -74, width: 64, height: 64)
        for sample in [0.0, 0.3, 0.55, 0.8, 1] {
            let down = genie(sample)
            let up = DockMinimise(window: mirroredWindow, target: mirroredTarget, direction: .up, progress: sample).genie()
            XCTAssertEqual(up.mesh.rows, down.mesh.rows)
            XCTAssertEqual(up.reveal, down.reveal, accuracy: 1e-12)
            for row in 0..<down.mesh.rows {
                let mirrorRow = down.mesh.rows - 1 - row
                for column in 0..<2 {
                    let a = down.mesh[row, column], b = up.mesh[mirrorRow, column]
                    XCTAssertEqual(a.global.x, b.global.x, accuracy: 1e-6)
                    XCTAssertEqual(a.global.y, -b.global.y, accuracy: 1e-6)
                    XCTAssertEqual(a.local.x, b.local.x, accuracy: 1e-6)
                    XCTAssertEqual(a.local.y, 800 - b.local.y, accuracy: 1e-6)
                }
            }
        }
    }

    func testLeftwardGenieIsTheDownwardOneWithAxesSwapped() {
        let turnedWindow = Rect(x: 300, y: 0, width: 800, height: 1200)
        let turnedTarget = Rect(x: 10, y: 600, width: 64, height: 64)
        for sample in [0.0, 0.3, 0.55, 0.8, 1] {
            let down = genie(sample)
            let left = DockMinimise(window: turnedWindow, target: turnedTarget, direction: .left, progress: sample).genie()
            XCTAssertEqual(left.mesh.rows, 2)
            XCTAssertEqual(left.mesh.columns, down.mesh.rows)
            for row in 0..<down.mesh.rows {
                for edge in 0..<2 {
                    let a = down.mesh[row, edge], b = left.mesh[edge, row]
                    XCTAssertEqual(a.global.x, b.global.y, accuracy: 1e-6)
                    XCTAssertEqual(a.global.y, b.global.x, accuracy: 1e-6)
                    XCTAssertEqual(a.local.x, b.local.y, accuracy: 1e-6)
                    XCTAssertEqual(a.local.y, b.local.x, accuracy: 1e-6)
                }
            }
        }
    }

    func testScaleSlidesTheRectangleWithADoubleCosineEase() {
        let rest = DockMinimise(window: window, target: target, direction: .down, progress: 0).scale()
        XCTAssertFalse(rest.settled)
        XCTAssertEqual(rest.mesh.points.map(\.global), [Point(x: 0, y: 300), Point(x: 1200, y: 300), Point(x: 0, y: 1100), Point(x: 1200, y: 1100)])
        let half = DockMinimise(window: window, target: target, direction: .down, progress: 0.5).scale()
        XCTAssertEqual(half.mesh[0, 0].global.x, 300, accuracy: 1e-9)
        XCTAssertEqual(half.mesh[0, 0].global.y, 155, accuracy: 1e-9)
        XCTAssertEqual(half.mesh[1, 1].global.x, 932, accuracy: 1e-9)
        XCTAssertEqual(half.mesh[1, 1].global.y, 587, accuracy: 1e-9)
        let quarter = DockMinimise(window: window, target: target, direction: .down, progress: 0.25).scale()
        let eased = 0.5 - 0.5 * cos(.pi * 0.25)
        XCTAssertEqual(quarter.mesh[0, 0].global.x, 600 * eased, accuracy: 1e-9)
        let done = DockMinimise(window: window, target: target, direction: .down, progress: 1).scale()
        XCTAssertTrue(done.settled)
        XCTAssertEqual(done.mesh.points.map(\.global), [Point(x: 600, y: 10), Point(x: 664, y: 10), Point(x: 600, y: 74), Point(x: 664, y: 74)])
        XCTAssertEqual(done.mesh.points.map(\.local), [Point(x: 0, y: 0), Point(x: 1200, y: 0), Point(x: 0, y: 800), Point(x: 1200, y: 800)])
    }

    func testSuckGridIsOneLinePerSeventyPointsCappedAtNineteen() {
        XCTAssertEqual(DockMinimise.suckCells(for: 1200), 17)
        XCTAssertEqual(DockMinimise.suckCells(for: 800), 11)
        XCTAssertEqual(DockMinimise.suckCells(for: 2000), 19)
        XCTAssertEqual(DockMinimise.suckCells(for: 50), 1)
        let rest = DockMinimise(window: window, target: target, direction: .down, progress: 0).suck()
        XCTAssertEqual(rest.mesh.columns, 18)
        XCTAssertEqual(rest.mesh.rows, 12)
        XCTAssertEqual(rest.mesh.points.count, 18 * 12)
    }

    func testSuckMovesEveryPointAtTheSameSpeedUntilAllArrive() {
        let rest = DockMinimise(window: window, target: target, direction: .down, progress: 0).suck()
        XCTAssertFalse(rest.settled)
        for point in rest.mesh.points {
            XCTAssertEqual(point.global.x, point.local.x, accuracy: 1e-9)
            XCTAssertEqual(point.global.y, point.local.y + 300, accuracy: 1e-9)
        }
        let reach = hypot(600.0, 1100.0 - 74)
        func steps(at progress: Double) -> [(distance: Double, step: Double)] {
            let frame = DockMinimise(window: window, target: target, direction: .down, progress: progress).suck()
            return frame.mesh.points.enumerated().map { index, point in
                let source = rest.mesh.points[index].global
                let column = index % 18, row = index / 18
                let goal = Point(x: 600 + 64 * Double(column) / 17, y: 10 + 64 * Double(row) / 11)
                return (hypot(goal.x - source.x, goal.y - source.y), hypot(point.global.x - source.x, point.global.y - source.y))
            }
        }
        let early = 0.5 - 0.5 * cos(.pi * 0.3)
        for sample in steps(at: 0.3) {
            XCTAssertEqual(sample.step, reach * early, accuracy: 1e-6)
        }
        let later = 0.5 - 0.5 * cos(.pi * 0.5)
        var arrived = 0, travelling = 0
        for sample in steps(at: 0.5) {
            XCTAssertEqual(sample.step, min(sample.distance, reach * later), accuracy: 1e-6)
            if sample.distance <= reach * later { arrived += 1 } else { travelling += 1 }
        }
        XCTAssertGreaterThan(arrived, 0)
        XCTAssertGreaterThan(travelling, 0)
        let done = DockMinimise(window: window, target: target, direction: .down, progress: 1).suck()
        XCTAssertTrue(done.settled)
        for (row, column, point) in done.mesh.points.enumerated().map({ ($0 / 18, $0 % 18, $1) }) {
            XCTAssertEqual(point.global.x, 600 + 64 * Double(column) / 17, accuracy: 1e-9)
            XCTAssertEqual(point.global.y, 10 + 64 * Double(row) / 11, accuracy: 1e-9)
        }
    }
}
