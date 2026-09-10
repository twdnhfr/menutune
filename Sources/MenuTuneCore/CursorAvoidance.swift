import CoreGraphics
import Foundation

/// Chooses the next safe floating-window position when the pointer approaches it.
public struct CursorAvoidance {
    public private(set) var activeIndex: Int

    private var direction = 1
    private var lastSwitchTime: TimeInterval?
    private let safetyMargin: CGFloat = 72
    private let cooldown: TimeInterval = 0.75
    private let predictionHorizon: CGFloat = 0.15
    private let maximumPrediction: CGFloat = 140

    public init(activeIndex: Int = 0) {
        self.activeIndex = activeIndex
    }

    public mutating func reset(activeIndex: Int = 0) {
        self.activeIndex = activeIndex
        direction = 1
        lastSwitchTime = nil
    }

    /// Traverses positions back and forth, skipping unsafe candidates.
    public mutating func nextPosition(
        frames: [CGRect],
        pointer: CGPoint,
        previousPointer: CGPoint? = nil,
        now: TimeInterval
    ) -> Int? {
        guard !frames.isEmpty else { return nil }
        activeIndex = normalized(activeIndex, count: frames.count)
        guard isUsable(frames[activeIndex]) else { return nil }

        let predicted = predictedPointer(pointer: pointer, previousPointer: previousPointer)
        let currentZone = frames[activeIndex].insetBy(dx: -safetyMargin, dy: -safetyMargin)
        guard currentZone.contains(pointer) || currentZone.contains(predicted) else { return nil }
        if let lastSwitchTime, now - lastSwitchTime < cooldown { return nil }

        // Reverse at either end instead of wrapping straight to the opposite edge.
        let forward = stride(from: activeIndex + direction,
            through: direction > 0 ? frames.count - 1 : 0, by: direction)
        let backward = stride(from: activeIndex - direction,
            through: direction > 0 ? 0 : frames.count - 1, by: -direction)
        for candidateIndex in Array(forward) + Array(backward) {
            let candidate = frames[candidateIndex]
            guard isUsable(candidate) else { continue }
            let candidateZone = candidate.insetBy(dx: -safetyMargin, dy: -safetyMargin)
            guard !candidateZone.contains(pointer), !candidateZone.contains(predicted) else { continue }
            direction = candidateIndex > activeIndex ? 1 : -1
            activeIndex = candidateIndex
            lastSwitchTime = now
            return candidateIndex
        }
        return nil
    }

    private func normalized(_ index: Int, count: Int) -> Int {
        let remainder = index % count
        return remainder >= 0 ? remainder : remainder + count
    }

    private func isUsable(_ frame: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0 && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
    }

    private func predictedPointer(pointer: CGPoint, previousPointer: CGPoint?) -> CGPoint {
        guard let previousPointer else { return pointer }
        let dx = pointer.x - previousPointer.x
        let dy = pointer.y - previousPointer.y
        let length = hypot(dx, dy)
        guard length > 0 else { return pointer }
        let scale = min(predictionHorizon / 0.05, maximumPrediction / length)
        return CGPoint(x: pointer.x + dx * scale, y: pointer.y + dy * scale)
    }
}
