import Foundation

public struct FPSMeter: Sendable {
    public let window: TimeInterval
    private var timestamps: [TimeInterval] = []

    public init(window: TimeInterval = 2) {
        self.window = window
    }

    public mutating func record(_ time: TimeInterval) {
        timestamps.append(time)
        timestamps.removeAll { $0 < time - window }
    }

    public mutating func reset() {
        timestamps.removeAll()
    }

    public var framesPerSecond: Double {
        guard timestamps.count >= 2, let first = timestamps.first, let last = timestamps.last, last > first else {
            return 0
        }
        return Double(timestamps.count - 1) / (last - first)
    }
}
