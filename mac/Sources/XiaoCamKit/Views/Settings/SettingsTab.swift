import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case camera
    case agents

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .camera: "Camera"
        case .agents: "Agents"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .camera: "camera"
        case .agents: "terminal"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .camera: .indigo
        case .agents: .green
        }
    }
}
