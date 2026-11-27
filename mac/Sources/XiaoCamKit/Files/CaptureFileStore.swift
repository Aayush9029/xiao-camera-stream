import Foundation

/// Writes CLI capture results. Pruning touches only files in `directory` whose names
/// match `managedName`, so user files and named `--out` results stay.
public struct CaptureFileStore: Sendable {
    public static let defaultKeepCount = 24

    public static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "XiaoCam/captures", directoryHint: .isDirectory)
    }

    public let directory: URL
    public let keepCount: Int

    public init(directory: URL = defaultDirectory, keepCount: Int = defaultKeepCount) {
        self.directory = directory
        self.keepCount = keepCount
    }

    public static func managedName(kind: CaptureKind, date: Date, jobID: String, fileExtension: String) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d%02d%02d-%02d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
        return "\(kind.rawValue)-\(stamp)-\(jobID).\(fileExtension)"
    }

    public static func isManagedName(_ name: String) -> Bool {
        name.wholeMatch(of: #/(snap|grid|clip)-\d{8}-\d{6}-[0-9a-f]{6}\.(jpg|mp4)/#) != nil
    }

    public func write(_ result: CaptureResult, to out: String?, jobID: String, date: Date = Date()) throws -> URL {
        let fileManager = FileManager.default
        let filename = Self.managedName(kind: result.kind, date: date, jobID: jobID, fileExtension: result.fileExtension)
        let url: URL
        if let out {
            let path = (out as NSString).expandingTildeInPath
            let base = URL(filePath: path, relativeTo: .currentDirectory()).standardizedFileURL
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: base.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue {
                url = base.appending(path: filename)
            } else {
                try fileManager.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
                url = base
            }
        } else {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            url = directory.appending(path: filename)
        }
        try result.data.write(to: url, options: .atomic)
        if out == nil { prune() }
        return url
    }

    public func prune() {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let managed = files.compactMap { url -> (URL, Date)? in
            guard Self.isManagedName(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true
            else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }
        for (url, _) in managed.sorted(by: { $0.1 > $1.1 }).dropFirst(keepCount) {
            try? fileManager.removeItem(at: url)
        }
    }
}
