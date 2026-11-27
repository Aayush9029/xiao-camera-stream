import CoreGraphics
import CoreText
import Foundation

enum LabelRenderer {
    static func draw(_ text: String, in context: CGContext, rect: CGRect) {
        let fontSize = max(11, rect.height * 0.032)
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let padding = fontSize * 0.45
        let margin = fontSize * 0.6
        let box = CGRect(
            x: rect.minX + margin,
            y: rect.minY + margin,
            width: min(textWidth + padding * 2, rect.width - margin * 2),
            height: ascent + descent + padding * 2
        )
        context.saveGState()
        context.addPath(CGPath(roundedRect: box, cornerWidth: padding, cornerHeight: padding, transform: nil))
        context.setFillColor(CGColor(gray: 0, alpha: 0.62))
        context.fillPath()
        context.clip(to: box)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: box.minX + padding, y: box.minY + padding + descent)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
