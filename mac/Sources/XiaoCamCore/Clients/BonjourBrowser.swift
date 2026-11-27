import Foundation
import Network
import Synchronization

enum BonjourBrowser {
    static let serviceTypes = ["_xiao-camera._udp", "_http._tcp"]

    static func hostNames(timeout: Duration) async -> [String] {
        let found = Mutex<[String]>([])
        let queue = DispatchQueue(label: "art.aayush.xiaocam.bonjour")
        let browsers = serviceTypes.map { type in
            NWBrowser(for: .bonjour(type: type, domain: "local."), using: NWParameters())
        }
        for browser in browsers {
            browser.browseResultsChangedHandler = { results, _ in
                let names = results.compactMap { result -> String? in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return name.lowercased().hasPrefix("xiao") ? "\(name).local" : nil
                }
                found.withLock { hosts in
                    for name in names where !hosts.contains(name) { hosts.append(name) }
                }
            }
            browser.start(queue: queue)
        }
        try? await Task.sleep(for: timeout)
        browsers.forEach { $0.cancel() }
        return found.withLock { $0 }
    }
}
