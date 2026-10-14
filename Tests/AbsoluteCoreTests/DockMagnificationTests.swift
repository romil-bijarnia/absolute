import XCTest
@testable import AbsoluteCore

final class DockMagnificationTests: XCTestCase {
    private func bar(fish: Double = 1, enabled: Bool = true, tile: Double = 48, large: Double = 128) -> DockMagnification {
        DockMagnification(tileSize: tile, largeSize: large, enabled: enabled, fish: fish, center: 1000)
    }

    func testBumpSpansThreeTilesAndUsesTheMeasuredConstants() {
        XCTAssertEqual(DockMagnification.bumpTiles, 3)
        XCTAssertEqual(DockMagnification.rampSpeed, 42)
        XCTAssertEqual(bar().bumpHalfWidth, 144)
    }

    func testCentreTileReachesLargeSizeExactly() {
        let magnified = bar()
        XCTAssertEqual(magnified.magnifiedSize(tileCentre: 1000), 128, accuracy: 1e-9)
        XCTAssertEqual(magnified.centreGrowth, 80, accuracy: 1e-12)
        let half = bar(fish: 0.5)
        XCTAssertEqual(half.magnifiedSize(tileCentre: 1000), 88, accuracy: 1e-9)
        XCTAssertEqual(half.centreGrowth, 40, accuracy: 1e-12)
    }

    func testTilesOutsideTheBumpKeepTheirSize() {
        let magnified = bar()
        for distance in [168.0, 200, 500, -168, -400] {
            XCTAssertEqual(magnified.magnifiedSize(tileCentre: 1000 + distance), 48, accuracy: 1e-9)
        }
    }

    func testSizesAreSymmetricAndFallOffMonotonically() {
        let magnified = bar()
        var previous = Double.infinity
        for step in stride(from: 0.0, through: 200, by: 5) {
            let right = magnified.magnifiedSize(tileCentre: 1000 + step)
            let left = magnified.magnifiedSize(tileCentre: 1000 - step)
            XCTAssertEqual(right, left, accuracy: 1e-9)
            XCTAssertLessThanOrEqual(right, previous + 1e-9)
            XCTAssertGreaterThanOrEqual(right, 48 - 1e-9)
            previous = right
        }
    }

    func testDisplacementIsContinuousAtTheBumpEdges() {
        let magnified = bar()
        for edge in [1000 + 144.0, 1000 - 144.0] {
            XCTAssertEqual(magnified.displacement(edge - 1e-6), magnified.displacement(edge + 1e-6), accuracy: 1e-4)
        }
        XCTAssertEqual(magnified.displacement(1000), 1000, accuracy: 1e-9)
        XCTAssertEqual(magnified.displacement(2000) - 2000, magnified.amplitude, accuracy: 1e-9)
        XCTAssertEqual(magnified.displacement(0), -magnified.amplitude, accuracy: 1e-9)
    }

    func testNeighboursGrowByTheIntegralOfTheBump() {
        let magnified = bar()
        let neighbour = magnified.magnifiedSize(tileCentre: 1048)
        let expected = magnified.amplitude * (sin(.pi * 72 / 288) - sin(.pi * 24 / 288))
        XCTAssertEqual(neighbour - 48, expected, accuracy: 1e-9)
        XCTAssertGreaterThan(neighbour, 48)
        XCTAssertLessThan(neighbour, 128)
    }

    func testDisabledOrNonGrowingSettingsProduceNoBump() {
        XCTAssertEqual(bar(enabled: false).amplitude, 0)
        XCTAssertEqual(bar(enabled: false).magnifiedSize(tileCentre: 1000), 48)
        XCTAssertEqual(bar(large: 48).amplitude, 0)
        XCTAssertEqual(bar(large: 32).magnifiedSize(tileCentre: 1000), 48)
        XCTAssertEqual(bar(fish: 0).magnifiedSize(tileCentre: 1000), 48, accuracy: 1e-12)
    }

    func testLayoutMapsBothEdgesAndKeepsTheRowContiguous() {
        let magnified = bar()
        let tiles = (0..<9).map { (position: 784.0 + Double($0) * 48, width: 48.0) }
        let laid = magnified.layout(tiles: tiles)
        for (previous, next) in zip(laid, laid.dropFirst()) {
            XCTAssertEqual(previous.end, next.start, accuracy: 1e-9)
        }
        let centre = laid[4]
        XCTAssertEqual(centre.length, 128, accuracy: 1e-9)
        XCTAssertEqual(centre.size, centre.length, accuracy: 1e-9)
        XCTAssertEqual(laid.first!.length, 48, accuracy: 1e-9)
        XCTAssertEqual(laid.last!.length, 48, accuracy: 1e-9)
        let total = laid.last!.end - laid.first!.start
        XCTAssertEqual(total, 9 * 48 + 2 * magnified.amplitude, accuracy: 1e-9)
    }

    func testRampDurationIsLogarithmicInTheSizeChange() {
        XCTAssertEqual(DockMagnification.rampDuration(sizeChange: 80), 156)
        XCTAssertEqual(DockMagnification.rampDuration(sizeChange: -80), 156)
        XCTAssertEqual(DockMagnification.rampDuration(sizeChange: 0), 1)
        XCTAssertEqual(DockMagnification.rampDuration(sizeChange: 16), 93)
        XCTAssertEqual(DockMagnification.rampDuration(sizeChange: 80, speed: 0), 1)
    }

    func testRampValueIsLinearAndClamped() {
        XCTAssertEqual(DockMagnification.rampValue(from: 0, to: 1, elapsed: 78, duration: 156), 0.5, accuracy: 1e-12)
        XCTAssertEqual(DockMagnification.rampValue(from: 0, to: 1, elapsed: 400, duration: 156), 1)
        XCTAssertEqual(DockMagnification.rampValue(from: 1, to: 0, elapsed: -3, duration: 156), 1)
        XCTAssertEqual(DockMagnification.rampValue(from: 0.4, to: 1, elapsed: 0, duration: 0), 1)
    }

    func testSinglePrecisionTranscriptionAgreesWithTheModel() {
        let magnified = bar()
        let tile: Float = 48, large: Float = 128, fish: Float = 1, centre: Float = 1000
        let fishSize = Float(3) * tile
        let realScale = Float(Double(fish) * Double((large - tile) * 0.5) / sin(Double(tile) * 0.5 * Double.pi / Double(fishSize + fishSize)))
        func displace(_ x: Float) -> Float {
            let d = x - centre
            if d <= -fishSize { return x - realScale }
            if d >= fishSize { return x + realScale }
            return x + sinf(d * Float.pi / fishSize * 0.5) * realScale
        }
        for offset in stride(from: -220, through: 220, by: 7) {
            let c = Float(1000 + offset)
            let native = displace(c + tile / 2) - displace(c - tile / 2)
            XCTAssertEqual(Double(native), magnified.magnifiedSize(tileCentre: Double(c)), accuracy: 1e-2)
        }
    }
}
