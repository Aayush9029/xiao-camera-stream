import Foundation

public struct FrameLabel: Equatable, Sendable {
    public enum Style: Sendable {
        case dateTime
        case time
    }

    public var date: Date
    public var index: Int?
    public var elapsed: Double?
    public var style: Style

    public init(date: Date, index: Int? = nil, elapsed: Double? = nil, style: Style = .dateTime) {
        self.date = date
        self.index = index
        self.elapsed = elapsed
        self.style = style
    }

    public func text(timeZone: TimeZone = .current) -> String {
        var parts: [String] = []
        if let index { parts.append("#\(index)") }
        parts.append(Self.format(date, style: style, timeZone: timeZone))
        if let elapsed { parts.append("+\(Self.formatElapsed(elapsed))") }
        return parts.joined(separator: "  ")
    }

    private static func format(_ date: Date, style: Style, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        switch style {
        case .time:
            return time
        case .dateTime:
            return String(format: "%04d-%02d-%02d ", c.year ?? 0, c.month ?? 0, c.day ?? 0) + time
        }
    }

    private static func formatElapsed(_ seconds: Double) -> String {
        let rounded = (seconds * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))s"
        }
        return String(format: "%.1fs", rounded)
    }
}
