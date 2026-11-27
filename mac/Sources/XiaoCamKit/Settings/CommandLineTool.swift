import Foundation
import Observation

/// Links the `xiaocam` binary inside the app bundle into `~/.local/bin`, so it stays
/// current when XiaoCam updates.
@MainActor
@Observable
final class CommandLineTool {
    static let name = "xiaocam"
    static let linkURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".local/bin/\(name)")
    static let linkDisplayPath = "~/.local/bin"
    static let bundledSuffix = "/Contents/Helpers/\(name)"

    private(set) var isInstalled = false
    private(set) var isLinkDirectoryOnPath = true
    private(set) var failureMessage: String?

    private var linkPath: String { Self.linkURL.path(percentEncoded: false) }

    private var bundledPath: String? {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Helpers/\(Self.name)")
        let path = url.path(percentEncoded: false)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    func refresh() async {
        let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)
        isInstalled = destination != nil && destination == bundledPath
        let directory = Self.linkURL.deletingLastPathComponent().path(percentEncoded: false)
        if let path = await Self.loginShellPath() {
            isLinkDirectoryOnPath = path.split(separator: ":").contains { $0 == directory }
        }
    }

    func install() async {
        guard let bundledPath else {
            failureMessage = "The xiaocam tool is missing from the app bundle."
            return
        }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: Self.linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fileManager.destinationOfSymbolicLink(atPath: linkPath)) != nil {
                try fileManager.removeItem(atPath: linkPath)
            } else if fileManager.fileExists(atPath: linkPath) {
                failureMessage = "\(linkPath) already exists. Remove it, then try again."
                return
            }
            try fileManager.createSymbolicLink(atPath: linkPath, withDestinationPath: bundledPath)
            failureMessage = nil
        } catch {
            failureMessage = error.localizedDescription
        }
        await refresh()
    }

    func uninstall() async {
        let fileManager = FileManager.default
        do {
            // Remove only a link into a XiaoCam bundle, never a file the user put there.
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkPath),
                  destination.hasSuffix(Self.bundledSuffix)
            else {
                failureMessage = "\(linkPath) was not installed by XiaoCam. Remove it yourself."
                return
            }
            try fileManager.removeItem(atPath: linkPath)
            failureMessage = nil
        } catch {
            failureMessage = error.localizedDescription
        }
        await refresh()
    }

    /// The `PATH` of a new interactive login shell, which is what a user gets in Terminal or over SSH.
    private nonisolated static func loginShellPath() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let marker = "__XIAOCAM_PATH__"
        let process = Process()
        process.executableURL = URL(filePath: shell)
        process.arguments = ["-ilc", "printf '\(marker)%s\(marker)' \"$PATH\""]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = await Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        let parts = text.components(separatedBy: marker)
        return parts.count >= 3 ? parts[1] : nil
    }
}
