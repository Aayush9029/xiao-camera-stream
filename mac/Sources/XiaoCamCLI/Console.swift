import ArgumentParser
import Foundation
import XiaoCamKit

enum Console {
    static func out(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func error(_ line: String) {
        FileHandle.standardError.write(Data(("xiaocam: " + line + "\n").utf8))
    }

    static func json(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        out(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    static func exitCode(for code: XiaoCamError.Code) -> Int32 {
        switch code {
        case .cameraOffline: 2
        case .appNotRunning, .connectionLost: 3
        case .busy: 4
        case .notFound: 5
        case .badRequest: 64
        case .failed: 1
        }
    }

    static func run(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error as XiaoCamError {
            Console.error(error.message)
            throw ExitCode(exitCode(for: error.code))
        } catch let error as CameraSettingError {
            Console.error(error.localizedDescription)
            throw ExitCode(64)
        } catch let error as ExitCode {
            throw error
        } catch {
            Console.error(error.localizedDescription)
            throw ExitCode(1)
        }
    }
}
