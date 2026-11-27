import Foundation

struct CameraHTTP: Sendable {
    let session: URLSession

    init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func status(host: String) async throws -> DeviceStatus {
        try Self.decodeStatus(await send("GET", host: host, path: "/api/status"), host: host)
    }

    func setMode(host: String, mode: CameraMode) async throws -> DeviceStatus {
        let query = [URLQueryItem(name: "mode", value: mode.rawValue)]
        return try Self.decodeStatus(await send("POST", host: host, path: "/api/mode", query: query), host: host)
    }

    func updateSettings(host: String, values: [CameraSettingValue]) async throws -> DeviceStatus {
        let query = values.map { URLQueryItem(name: $0.setting.key, value: String($0.value)) }
        return try Self.decodeStatus(await send("POST", host: host, path: "/api/settings", query: query), host: host)
    }

    func capture(host: String) async throws -> Data {
        let data = try await send("GET", host: host, path: "/capture")
        guard data.count > 128, data.starts(with: [0xFF, 0xD8]) else {
            throw CameraError.invalidResponse("the capture is not a JPEG image")
        }
        return data
    }

    static func decodeStatus(_ data: Data, host: String) throws(CameraError) -> DeviceStatus {
        let status: DeviceStatus
        do {
            status = try JSONDecoder().decode(DeviceStatus.self, from: data)
        } catch {
            throw .notACamera(host: host)
        }
        guard status.isXiaoCamera else { throw .notACamera(host: host) }
        return status
    }

    private func send(_ method: String, host: String, path: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw CameraError.unreachable(host: host, reason: "the host name is not valid")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw CameraError.timedOut(host: host)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CameraError.unreachable(host: host, reason: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CameraError.invalidResponse("no HTTP response")
        }
        let body = String(decoding: data.prefix(200), as: UTF8.self)
        switch http.statusCode {
        case 200..<300:
            return data
        case 503:
            throw CameraError.busy(body)
        default:
            throw CameraError.httpStatus(http.statusCode, body)
        }
    }
}
