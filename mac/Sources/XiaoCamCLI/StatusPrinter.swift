import Foundation
import XiaoCamKit

enum StatusPrinter {
    static func print(_ status: AppStatus) {
        row("camera", connection(status.connection))
        guard let device = status.device else { return }
        row("mode", "\(device.mode) \(device.width)x\(device.height)")
        row("fps", "\(format(device.captureFPS)) camera, \(format(status.receiveFPS)) here")
        row("signal", device.wifiMode == "AP" ? "camera network \(device.ssid)" : "\(device.rssi) dBm \(device.ssid)")
        row("temp", "\(format(device.temperatureC)) C")
        row("firmware", "\(device.firmware) \(device.sensor)")
        row("defaults", "enhance \(status.enhanceImage ? "on" : "off"), timestamp \(status.timestampOverlay ? "on" : "off")")
    }

    static func device(_ device: DeviceStatus) -> String {
        "\(device.mode) \(device.width)x\(device.height)"
    }

    static func connection(_ state: ConnectionState) -> String {
        switch state {
        case .searching: "searching"
        case let .connecting(host): "connecting \(host)"
        case let .live(host): "live \(host)"
        case let .offline(reason): "offline: \(reason)"
        }
    }

    private static func row(_ label: String, _ value: String) {
        Console.out(label.padding(toLength: 10, withPad: " ", startingAt: 0) + value)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
