import Foundation
import XiaoCamKit

enum AppConnection {
    static let launchTimeout: Duration = .seconds(15)

    static func send(_ request: LocalRequest) async throws(XiaoCamError) -> LocalResponse {
        let client = LocalAPIClient()
        var response: LocalResponse
        do {
            response = try await client.send(request)
        } catch where error.code == .appNotRunning {
            try await launchApp(client: client)
            response = try await client.send(request)
        }
        if let error = response.error { throw error }
        return response
    }

    private static func launchApp(client: LocalAPIClient) async throws(XiaoCamError) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        if let bundle = siblingAppBundle {
            process.arguments = ["-g", bundle.path(percentEncoded: false)]
        } else {
            process.arguments = ["-g", "-b", LocalAPIPaths.bundleIdentifier]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw XiaoCamError(.appNotRunning, "app not running, and /usr/bin/open failed: \(error.localizedDescription)")
        }
        guard process.terminationStatus == 0 else {
            throw XiaoCamError(.appNotRunning, "app not running, and macOS could not open XiaoCam.app. Open it one time by hand.")
        }
        var waited = Duration.zero
        while waited < launchTimeout {
            if await client.isReachable() { return }
            try? await Task.sleep(for: .milliseconds(250))
            waited += .milliseconds(250)
        }
        throw XiaoCamError(.appNotRunning, "app not running: XiaoCam opened but did not answer in \(launchTimeout).")
    }

    private static var siblingAppBundle: URL? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard contents.lastPathComponent == "Contents", app.pathExtension == "app" else { return nil }
        return app
    }
}
