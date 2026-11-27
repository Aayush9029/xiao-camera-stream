import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct PhotoLibraryClient: Sendable {
    public var save: @Sendable (_ jpeg: Data, _ date: Date) async throws -> URL
}

extension PhotoLibraryClient: DependencyKey {
    public static var liveValue: PhotoLibraryClient {
        PhotoLibraryClient { jpeg, date in
            let directory = URL.picturesDirectory.appending(path: "XiaoCam", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let base = "XiaoCam " + FrameLabel(date: date).text().replacingOccurrences(of: ":", with: ".")
            var url = directory.appending(path: "\(base).jpg")
            var copy = 2
            while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                url = directory.appending(path: "\(base) \(copy).jpg")
                copy += 1
            }
            try jpeg.write(to: url, options: .withoutOverwriting)
            return url
        }
    }

    public static var testValue: PhotoLibraryClient { PhotoLibraryClient() }
}

extension DependencyValues {
    public var photoLibrary: PhotoLibraryClient {
        get { self[PhotoLibraryClient.self] }
        set { self[PhotoLibraryClient.self] = newValue }
    }
}
