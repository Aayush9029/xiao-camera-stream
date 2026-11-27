import Foundation
import Observation

@MainActor
@Observable
final class SkillInstaller {
    enum State: Equatable {
        case missingFromBundle
        case notInstalled
        case outdated
        case installed
    }

    static let destination = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".agents/skills/xiaocam", directoryHint: .isDirectory)
    static let displayPath = "~/.agents/skills/xiaocam"

    private(set) var state = State.notInstalled
    private(set) var failureMessage: String?

    private var bundledSkill: URL? {
        guard let url = Bundle.main.resourceURL?.appending(path: "skills/xiaocam", directoryHint: .isDirectory),
              FileManager.default.fileExists(atPath: url.appending(path: "SKILL.md").path(percentEncoded: false))
        else { return nil }
        return url
    }

    func refresh() {
        guard let bundledSkill else {
            state = .missingFromBundle
            return
        }
        let installed = try? Data(contentsOf: Self.destination.appending(path: "SKILL.md"))
        let bundled = try? Data(contentsOf: bundledSkill.appending(path: "SKILL.md"))
        state = switch installed {
        case nil: .notInstalled
        case bundled: .installed
        default: .outdated
        }
    }

    func install() {
        guard let bundledSkill else {
            failureMessage = "The skill is missing from the app bundle."
            refresh()
            return
        }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: Self.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: Self.destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: Self.destination)
            }
            try fileManager.copyItem(at: bundledSkill, to: Self.destination)
            failureMessage = nil
        } catch {
            failureMessage = error.localizedDescription
        }
        refresh()
    }
}
