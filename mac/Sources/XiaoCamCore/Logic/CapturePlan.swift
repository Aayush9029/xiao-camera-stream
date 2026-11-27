public struct CapturePlan: Codable, Equatable, Sendable {
    public static let minimumInterval: Double = 0.5
    public static let maximumDuration: Double = 3600
    public static let maximumFrames = 36

    public let interval: Double
    public let duration: Double
    public let offsets: [Double]

    public init(every requestedInterval: Double, for requestedDuration: Double) {
        let duration = min(max(requestedDuration.finiteOrZero, 0), Self.maximumDuration)
        var interval = max(requestedInterval.finiteOrZero, Self.minimumInterval)
        if duration > 0, (duration / interval).rounded(.down) + 1 > Double(Self.maximumFrames) {
            interval = duration / Double(Self.maximumFrames - 1)
        }
        let steps = duration > 0 ? Int((duration / interval + 1e-9).rounded(.down)) : 0
        self.interval = interval
        self.duration = duration
        self.offsets = (0...steps).map { Double($0) * interval }
    }

    public var frameCount: Int { offsets.count }
}

private extension Double {
    var finiteOrZero: Double { isFinite ? self : 0 }
}
