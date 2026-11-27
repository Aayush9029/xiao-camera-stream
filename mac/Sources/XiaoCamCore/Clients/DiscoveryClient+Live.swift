import Dependencies
import Foundation

extension DiscoveryClient: DependencyKey {
    public static let defaultHostName = "xiao-cam.local"
    public static let accessPointHost = "192.168.4.1"

    public static var liveValue: DiscoveryClient {
        let probe = CameraHTTP(timeout: 2.5)
        return DiscoveryClient { savedHost in
            await withTaskGroup(of: [DiscoveredCamera].self) { group in
                var fixed: [(String, DiscoveredCamera.Source)] = []
                if let savedHost, !savedHost.isEmpty { fixed.append((savedHost, .saved)) }
                fixed.append((defaultHostName, .hostname))
                fixed.append((accessPointHost, .accessPoint))
                for (host, source) in fixed {
                    group.addTask { await probe.camera(host: host, source: source).map { [$0] } ?? [] }
                }
                group.addTask {
                    let names = await BonjourBrowser.hostNames(timeout: .seconds(1.5))
                    let candidates = names.filter { name in !fixed.contains { $0.0 == name } }
                    return await withTaskGroup(of: DiscoveredCamera?.self) { inner in
                        for name in candidates {
                            inner.addTask { await probe.camera(host: name, source: .bonjour) }
                        }
                        var cameras: [DiscoveredCamera] = []
                        for await camera in inner { if let camera { cameras.append(camera) } }
                        return cameras
                    }
                }
                var cameras: [DiscoveredCamera] = []
                for await batch in group { cameras += batch }
                return DiscoveredCamera.ranked(cameras)
            }
        }
    }
}

extension DiscoveredCamera {
    static func ranked(_ cameras: [DiscoveredCamera]) -> [DiscoveredCamera] {
        let order: [Source] = [.saved, .bonjour, .hostname, .accessPoint]
        var seen: Set<String> = []
        return cameras
            .sorted { order.firstIndex(of: $0.source)! < order.firstIndex(of: $1.source)! }
            .filter { seen.insert($0.status.ip.isEmpty ? $0.host : $0.status.ip).inserted }
    }
}

extension CameraHTTP {
    func camera(host: String, source: DiscoveredCamera.Source) async -> DiscoveredCamera? {
        guard let status = try? await status(host: host) else { return nil }
        let address = status.ip.isEmpty || source == .saved ? host : status.ip
        return DiscoveredCamera(host: address, source: source, status: status)
    }
}
