import CoreGraphics
import XCTest
@testable import MenuTuneCore

final class CursorAvoidanceTests: XCTestCase {
    private let frames = [
        CGRect(x: 0, y: 0, width: 100, height: 100),
        CGRect(x: 300, y: 0, width: 100, height: 100),
        CGRect(x: 0, y: 300, width: 100, height: 100)
    ]

    func testMovesToNextSafeCandidateWhenPointerApproaches() {
        var avoidance = CursorAvoidance()
        XCTAssertEqual(avoidance.nextPosition(frames: frames, pointer: CGPoint(x: 160, y: 50), previousPointer: CGPoint(x: 230, y: 50), now: 1), 1)
        XCTAssertEqual(avoidance.activeIndex, 1)
    }

    func testUsesOrderedCandidatesAndSkipsUnsafeOnes() {
        var avoidance = CursorAvoidance()
        let candidates = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
            CGRect(x: 400, y: 0, width: 100, height: 100)
        ]
        XCTAssertEqual(avoidance.nextPosition(frames: candidates, pointer: CGPoint(x: 50, y: 50), now: 1), 2)
    }

    func testMovesThroughMiddleInBothDirections() {
        var avoidance = CursorAvoidance()
        let positions = [0, 300, 600].map { y in
            CGRect(x: 1000, y: y, width: 100, height: 100)
        }
        for (step, expectedIndex) in [1, 2, 1, 0, 1].enumerated() {
            let current = positions[avoidance.activeIndex]
            let pointer = CGPoint(x: current.midX, y: current.midY)
            XCTAssertEqual(avoidance.nextPosition(frames: positions, pointer: pointer,
                now: TimeInterval(step + 1)), expectedIndex, "Move \(step + 1)")
        }
    }

    /// Named for what it checks: after the window left, the pointer is no longer
    /// anywhere near it, so the proximity guard alone suppresses a second move.
    func testPointerLeftBehindTriggersNoFurtherMove() {
        var avoidance = CursorAvoidance()
        XCTAssertEqual(avoidance.nextPosition(frames: frames, pointer: CGPoint(x: 50, y: 50), now: 1), 1)
        XCTAssertNil(avoidance.nextPosition(frames: frames, pointer: CGPoint(x: 50, y: 50), now: 2))
    }

    /// The pointer is still outside the active window's safety zone, so only the
    /// extrapolated position can trigger the move.
    func testPredictedPositionAloneTriggersTheMove() {
        var approaching = CursorAvoidance()
        XCTAssertEqual(approaching.nextPosition(frames: frames, pointer: CGPoint(x: 260, y: 50),
                                                previousPointer: CGPoint(x: 300, y: 50), now: 1), 2)

        var stationary = CursorAvoidance()
        XCTAssertNil(stationary.nextPosition(frames: frames, pointer: CGPoint(x: 260, y: 50), now: 1),
                     "Without movement the same pointer sits outside the zone.")
    }

    /// Mirror image: the candidate is safe for the pointer itself and only the
    /// extrapolated position rules it out, leaving no alternative at all.
    func testPredictedPositionAloneRejectsACandidate() {
        let candidates = [CGRect(x: 0, y: 0, width: 100, height: 100),
                          CGRect(x: 300, y: 0, width: 100, height: 100)]
        var approaching = CursorAvoidance()
        XCTAssertNil(approaching.nextPosition(frames: candidates, pointer: CGPoint(x: 150, y: 50),
                                              previousPointer: CGPoint(x: 100, y: 50), now: 1))

        var stationary = CursorAvoidance()
        XCTAssertEqual(stationary.nextPosition(frames: candidates, pointer: CGPoint(x: 150, y: 50), now: 1), 1,
                       "Without prediction the second frame is a safe target.")
    }

    func testCooldownSuppressesImmediateSecondMove() {
        var avoidance = CursorAvoidance()
        let candidates = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 300, y: 0, width: 100, height: 100)]
        XCTAssertEqual(avoidance.nextPosition(frames: candidates, pointer: CGPoint(x: 50, y: 50), now: 1), 1)
        XCTAssertNil(avoidance.nextPosition(frames: candidates, pointer: CGPoint(x: 350, y: 50), now: 1.1))
    }

    func testReturnsNilWhenEveryAlternativeIsUnsafe() {
        var avoidance = CursorAvoidance()
        let candidates = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 120, y: 0, width: 100, height: 100)]
        XCTAssertNil(avoidance.nextPosition(frames: candidates, pointer: CGPoint(x: 110, y: 50), now: 1))
    }

    func testHandlesInvalidIndexNegativeCoordinatesAndEmptyFrames() {
        var avoidance = CursorAvoidance(activeIndex: -1)
        let negative = [CGRect(x: -500, y: -300, width: 100, height: 100), CGRect(x: -100, y: -300, width: 100, height: 100)]
        XCTAssertEqual(avoidance.nextPosition(frames: negative, pointer: CGPoint(x: -50, y: -250), now: 1), 0)
        XCTAssertNil(avoidance.nextPosition(frames: [], pointer: .zero, now: 2))
    }
}
