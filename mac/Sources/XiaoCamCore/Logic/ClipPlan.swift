public struct ClipPlan: Codable, Equatable, Sendable {
    public static let durationLimits: ClosedRange<Double> = 1...60
    public static let fpsLimits: ClosedRange<Double> = 1...30

    public let duration: Double
    public let fps: Double

    public init(for requestedDuration: Double, fps requestedFPS: Double = 10) {
        duration = requestedDuration.clamped(to: Self.durationLimits)
        fps = requestedFPS.clamped(to: Self.fpsLimits)
    }

    public var minimumSpacing: Double { 1 / fps }

    public func accepts(elapsed: Double, sinceLastKept lastKept: Double?) -> Bool {
        guard elapsed <= duration else { return false }
        guard let lastKept else { return true }
        return elapsed - lastKept >= minimumSpacing * 0.9
    }
}

private extension Double {
    func clamped(to limits: ClosedRange<Double>) -> Double {
        guard isFinite else { return limits.lowerBound }
        return Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}
