import Cocoa
import Foundation

// Native Retina XDR Full-Screen Optical Test & Glass-to-Glass Latency Probe
// Controlled via tiny HTTP server on 127.0.0.1:8099:
//   GET /mode?m=chart|black|white|motion|lowlight|quit
// Returns JSON with exact mach/wall timestamp when the frame was committed.

enum TestPattern: String {
    case chart
    case black
    case white
    case motion
    case lowlight
}

class TestView: NSView {
    var pattern: TestPattern = .chart
    var phase: CGFloat = 0
    var frameCounter: Int = 0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let W = bounds.width
        let H = bounds.height

        switch pattern {
        case .black:
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(bounds)

        case .white:
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(bounds)

        case .lowlight:
            // Controlled low-light test (dark room / shadow noise & dynamic range test)
            ctx.setFillColor(NSColor(white: 0.08, alpha: 1).cgColor)
            ctx.fill(bounds)
            drawText("LOW-LIGHT NOISE & DYNAMIC RANGE TEST (8%–35% LUMA)", at: CGPoint(x: W*0.06, y: H*0.08), size: 32, color: NSColor(white: 0.35, alpha: 1))
            let steps = 8
            let bw = (W * 0.88) / CGFloat(steps)
            for i in 0..<steps {
                let lum = 0.04 + CGFloat(i) * 0.045
                ctx.setFillColor(NSColor(white: lum, alpha: 1).cgColor)
                ctx.fill(CGRect(x: W*0.06 + CGFloat(i)*bw, y: H*0.22, width: bw - 4, height: H*0.45))
                drawText("\(Int(lum*100))%", at: CGPoint(x: W*0.06 + CGFloat(i)*bw + 10, y: H*0.70), size: 22, color: NSColor(white: 0.45, alpha: 1))
            }
            drawText("The quick brown fox jumps over the lazy dog 0123456789", at: CGPoint(x: W*0.06, y: H*0.80), size: 28, color: NSColor(white: 0.32, alpha: 1))

        case .motion:
            ctx.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
            ctx.fill(bounds)
            // Fast sweeping high-contrast bars + frame counter
            let barW: CGFloat = 90
            let x = (phase.truncatingRemainder(dividingBy: W + barW)) - barW
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: x, y: 0, width: barW, height: H))
            let x2 = ((phase * 1.7 + W*0.5).truncatingRemainder(dividingBy: W + barW)) - barW
            ctx.setFillColor(NSColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 1).cgColor)
            ctx.fill(CGRect(x: x2, y: H*0.25, width: 60, height: H*0.5))
            drawText("MOTION & TEMPORAL NR TEST · FRAME #\(frameCounter)", at: CGPoint(x: 60, y: 50), size: 36, color: .white)

        case .chart:
            // Neutral dark-slate background so camera exposure settles naturally
            ctx.setFillColor(NSColor(white: 0.50, alpha: 1).cgColor)
            ctx.fill(bounds)

            let pad: CGFloat = 36
            let innerW = W - pad*2
            let innerH = H - pad*2

            // 1. Header Banner
            ctx.setFillColor(NSColor(white: 0.10, alpha: 1).cgColor)
            ctx.fill(CGRect(x: pad, y: pad, width: innerW, height: 74))
            drawText("XIAO ESP32-S3 OV3660 OPTICAL FIDELITY & RESOLUTION CHART", at: CGPoint(x: pad+20, y: pad+16), size: 34, color: .white)

            // 2. Macbeth-style 12-patch Color Checker (top row)
            let colors: [NSColor] = [
                NSColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1), // Red
                NSColor(red: 0.18, green: 0.72, blue: 0.25, alpha: 1), // Green
                NSColor(red: 0.16, green: 0.36, blue: 0.88, alpha: 1), // Blue
                NSColor(red: 0.12, green: 0.78, blue: 0.84, alpha: 1), // Cyan
                NSColor(red: 0.84, green: 0.22, blue: 0.74, alpha: 1), // Magenta
                NSColor(red: 0.95, green: 0.84, blue: 0.14, alpha: 1), // Yellow
                NSColor(red: 0.92, green: 0.52, blue: 0.16, alpha: 1), // Orange
                NSColor(red: 0.78, green: 0.58, blue: 0.46, alpha: 1), // Light Skin
                NSColor(red: 0.45, green: 0.32, blue: 0.26, alpha: 1), // Dark Skin
                NSColor(white: 0.95, alpha: 1),                       // White
                NSColor(white: 0.50, alpha: 1),                       // Mid Gray
                NSColor(white: 0.05, alpha: 1),                       // Black
            ]
            let colorY = pad + 90
            let colorH: CGFloat = innerH * 0.16
            let patchW = innerW / CGFloat(colors.count)
            for (i, col) in colors.enumerated() {
                ctx.setFillColor(col.cgColor)
                ctx.fill(CGRect(x: pad + CGFloat(i)*patchW + 3, y: colorY, width: patchW - 6, height: colorH))
            }

            // 3. Grayscale 10-step Dynamic Range Ramp
            let rampY = colorY + colorH + 18
            let rampH: CGFloat = innerH * 0.12
            let stepW = innerW / 10.0
            for i in 0..<10 {
                let lum = CGFloat(i) / 9.0
                ctx.setFillColor(NSColor(white: lum, alpha: 1).cgColor)
                ctx.fill(CGRect(x: pad + CGFloat(i)*stepW, y: rampY, width: stepW, height: rampH))
            }

            // 4. Lower Left: Multi-size Crisp Typography (Light & Dark Panels)
            let lowY = rampY + rampH + 20
            let lowH = H - lowY - pad
            let halfW = (innerW - 20) * 0.5

            // White card with black text
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: pad, y: lowY, width: halfW, height: lowH * 0.52))
            let sizes: [CGFloat] = [34, 26, 20, 15, 11]
            var ty = lowY + 12
            for sz in sizes {
                drawText("\(Int(sz))pt: ABCDEFGH abcdefgh 0123456789 Sharpness Test", at: CGPoint(x: pad + 16, y: ty), size: sz, color: .black)
                ty += sz + 11
            }

            // Dark card with white text (tests halation/bloom & shadow noise!)
            let darkY = lowY + lowH * 0.54
            ctx.setFillColor(NSColor(white: 0.07, alpha: 1).cgColor)
            ctx.fill(CGRect(x: pad, y: darkY, width: halfW, height: lowH * 0.46))
            ty = darkY + 12
            for sz in sizes {
                drawText("\(Int(sz))pt: DARK UI TEXT 0123456789 Crisp Edge Clarity", at: CGPoint(x: pad + 16, y: ty), size: sz, color: .white)
                ty += sz + 10
            }

            // 5. Lower Right: Spatial Frequency Line-Pair Gratings + Slanted Edge MTF + Flat Noise Patch
            let rightX = pad + halfW + 20
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: rightX, y: lowY, width: halfW, height: lowH))

            // Line-pair vertical gratings at pitches 12, 8, 5, 3, 2 pt
            let pitches: [CGFloat] = [12, 8, 5, 3, 2]
            let gw = (halfW - 40) / CGFloat(pitches.count)
            for (i, p) in pitches.enumerated() {
                let gx = rightX + 20 + CGFloat(i)*gw
                let gy = lowY + 18
                let gh = lowH * 0.42
                ctx.setFillColor(NSColor.black.cgColor)
                var lx: CGFloat = 0
                while lx < gw - 12 {
                    ctx.fill(CGRect(x: gx + lx, y: gy, width: p, height: gh))
                    lx += p * 2
                }
                drawText("\(Int(p))pt", at: CGPoint(x: gx, y: gy + gh + 4), size: 15, color: .black)
            }

            // Slanted black edge for MTF + large flat 40% gray patch for SNR measurement
            let botY = lowY + lowH * 0.54
            let botH = lowH * 0.42
            ctx.saveGState()
            ctx.addRect(CGRect(x: rightX + 20, y: botY, width: halfW*0.44, height: botH))
            ctx.clip()
            ctx.setFillColor(NSColor.black.cgColor)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rightX + 20, y: botY))
            path.addLine(to: CGPoint(x: rightX + 20 + halfW*0.24, y: botY))
            path.addLine(to: CGPoint(x: rightX + 20 + halfW*0.18, y: botY + botH))
            path.addLine(to: CGPoint(x: rightX + 20, y: botY + botH))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()

            // Flat neutral 40% gray patch for clean SNR / noise-floor measurement
            let patchX = rightX + 20 + halfW*0.48
            ctx.setFillColor(NSColor(white: 0.40, alpha: 1).cgColor)
            ctx.fill(CGRect(x: patchX, y: botY, width: halfW*0.46, height: botH))
            drawText("40% NEUTRAL GRAY (SNR)", at: CGPoint(x: patchX + 10, y: botY + 10), size: 14, color: NSColor(white: 0.78, alpha: 1))
        }
    }

    func drawText(_ s: String, at pt: CGPoint, size: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
            .foregroundColor: color
        ]
        (s as NSString).draw(at: pt, withAttributes: attrs)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: TestView!
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { exit(1) }
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .black
        window.isOpaque = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        view = TestView(frame: screen.frame)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self, self.view.pattern == .motion else { return }
            self.view.phase += 24
            self.view.frameCounter += 1
            self.view.needsDisplay = true
        }

        // Start tiny POSIX HTTP control listener on 127.0.0.1:8099
        DispatchQueue.global(qos: .userInteractive).async {
            self.runControlServer()
        }

        // Auto-exit safety timeout after 120s so we never leave the user's screen locked!
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            NSApp.terminate(nil)
        }
    }

    func runControlServer() {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(8099).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindOk = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOk == 0, listen(fd, 8) == 0 else { return }

        while true {
            let cli = accept(fd, nil, nil)
            if cli < 0 { continue }
            var buf = [UInt8](repeating: 0, count: 1024)
            let n = recv(cli, &buf, buf.count - 1, 0)
            var modeStr = "chart"
            if n > 0, let req = String(bytes: buf[0..<n], encoding: .utf8) {
                if let r = req.range(of: "m=") {
                    let sub = req[r.upperBound...]
                    modeStr = String(sub.prefix { $0 != " " && $0 != "&" && $0 != "\r" && $0 != "\n" })
                }
            }

            if modeStr == "quit" {
                let body = "{\"ok\":true,\"quit\":true}"
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n\(body)"
                _ = resp.withCString { send(cli, $0, strlen($0), 0) }
                close(cli)
                DispatchQueue.main.async { NSApp.terminate(nil) }
                return
            }

            let sem = DispatchSemaphore(value: 0)
            var tsNs: Int64 = 0
            DispatchQueue.main.async {
                if let p = TestPattern(rawValue: modeStr) {
                    self.view.pattern = p
                    self.view.displayIfNeeded()
                    self.view.needsDisplay = true
                    self.window.display()
                }
                tsNs = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
                sem.signal()
            }
            sem.wait()

            let body = "{\"ok\":true,\"mode\":\"\(modeStr)\",\"ts_ns\":\(tsNs)}"
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n\(body)"
            _ = resp.withCString { send(cli, $0, strlen($0), 0) }
            close(cli)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
