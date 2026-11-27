import Foundation

public enum LocalAPIPaths {
    public static let bundleIdentifier = "art.aayush.xiaocam"

    public static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "XiaoCam", directoryHint: .isDirectory)
    }

    public static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["XIAOCAM_SOCKET"], !override.isEmpty {
            return override
        }
        return directory.appending(path: "xiaocam.sock").path(percentEncoded: false)
    }

    static func prepareDirectory(for socketPath: String) throws {
        let directory = URL(filePath: socketPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
