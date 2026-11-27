import Foundation
import Synchronization

/// Remembers the socket file that this process bound, so cleanup never removes
/// a socket that another XiaoCam instance made at the same path.
final class SocketOwnership: Sendable {
    private struct Identity: Equatable {
        var device: dev_t
        var inode: ino_t
    }

    private let identity = Mutex<Identity?>(nil)

    func claim(_ path: String) -> Bool {
        guard let current = Self.identity(of: path) else { return false }
        identity.withLock { $0 = current }
        return true
    }

    func release(_ path: String) {
        identity.withLock { owned in
            if let identity = owned, Self.identity(of: path) == identity { unlink(path) }
            owned = nil
        }
    }

    private static func identity(of path: String) -> Identity? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK else { return nil }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }
}
