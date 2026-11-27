import Foundation
import Testing
import XiaoCamKit

struct CaptureFileStoreTests {
    @Test func prunesOnlyManagedCaptures() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appending(path: "xc-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        for index in 0..<30 {
            let name = CaptureFileStore.managedName(
                kind: .snap, date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                jobID: String(format: "%06x", index), fileExtension: "jpg"
            )
            let url = directory.appending(path: name)
            try Data([1]).write(to: url)
            try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))], ofItemAtPath: url.path(percentEncoded: false))
        }
        let unmanaged = ["notes.txt", "my-photo.jpg", "snap-keep.jpg", "snap-20260101-000000-ABCDEF.jpg"]
        for name in unmanaged { try Data([2]).write(to: directory.appending(path: name)) }

        let store = CaptureFileStore(directory: directory, keepCount: 24)
        let result = CaptureResult(
            kind: .grid, data: Data([3]), fileExtension: "jpg", width: 1, height: 1,
            mode: "balanced", enhanced: false, timestamped: false, frames: []
        )
        let named = try store.write(result, to: directory.appending(path: "kept.jpg").path(percentEncoded: false), jobID: "abcde0")
        let written = try store.write(result, to: nil, jobID: "abcdef")

        let names = try fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(names.filter(CaptureFileStore.isManagedName).count == 24)
        #expect(names.contains(written.lastPathComponent))
        #expect(!names.contains(CaptureFileStore.managedName(
            kind: .snap, date: Date(timeIntervalSince1970: 1_700_000_000), jobID: "000000", fileExtension: "jpg"
        )))
        for name in unmanaged + ["kept.jpg"] { #expect(names.contains(name)) }
        #expect(named.lastPathComponent == "kept.jpg")
    }
}
