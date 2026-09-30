import AppKit
import SwiftUI
import SmartFanCore
import SmartFanLocalization

struct MenuBarLabel: View {
    @EnvironmentObject var language: AppLanguageStore
    @Environment(\.colorScheme) private var colorScheme
    let state: MonitorState
    let maxTemp: Float?
    var fahrenheit: Bool = false
    var needsDaemonUpdate: Bool = false

    var body: some View {
        Image(nsImage: MenuBarLabelImage.make(
            symbol: iconName, text: temperatureText,
            needsWarning: needsDaemonUpdate, colorScheme: colorScheme
        ))
        .help(language.text("SmartFan: {reading}", ["reading": accessibleReading]))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SmartFan")
        .accessibilityValue(accessibleReading)
    }

    var temperatureText: String? {
        Self.temperatureText(maxTemp, fahrenheit: fahrenheit)
    }

    /// Integer degree reading (`48°`), or nil when the value is missing or cannot
    /// be represented. Shared by the SwiftUI label and the `NSStatusItem` renderer.
    static func temperatureText(_ tempC: Float?, fahrenheit: Bool) -> String? {
        guard let tempC else { return nil }
        let display = fahrenheit ? tempC * 9 / 5 + 32 : tempC
        guard display.isFinite, let integer = Int(exactly: Double(display.rounded(.towardZero))) else { return nil }
        return "\(integer)°"
    }

    private var accessibleReading: String {
        guard let temperatureText else { return language.text("Temperature unavailable") }
        return temperatureText + (fahrenheit ? "F" : "C")
    }

    private var iconName: String { Self.symbol(for: state) }

    /// SF Symbol for a monitor state. Shared by the SwiftUI label and the status item.
    static func symbol(for state: MonitorState) -> String {
        switch state {
        case .safetyOverride: return "exclamationmark.triangle.fill"
        case .active: return "fan.fill"
        case .idle: return "fan"
        }
    }
}

/// The menu bar item draws one hand-built `NSImage`; AppKit renders the drawing
/// handler at the destination screen's backing scale. A minimum logical width keeps
/// the item from resizing as the digit count changes.@MainActor
enum MenuBarLabelImage {
    private static let font = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular
    )
    private static let symbols = ["fan", "fan.fill", "exclamationmark.triangle.fill"]
        .compactMap { name -> (String, NSImage)? in
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular))
            else { return nil }
            return (name, image)
        }
    private static let iconWidth = ceil(symbols.map { $0.1.size.width }.max() ?? font.pointSize)
    private static let iconHeight = ceil(symbols.map { $0.1.size.height }.max() ?? font.pointSize)
    private static let fieldSize = ("88°" as NSString).size(withAttributes: [.font: font])
    private static let gap: CGFloat = 3
    static let minimumSize = NSSize(width: iconWidth + gap + ceil(fieldSize.width),
                                    height: max(20, iconHeight, ceil(fieldSize.height)))

    static func make(symbol: String, text: String?, needsWarning: Bool, colorScheme: ColorScheme) -> NSImage {
        let glyph = symbols.first { $0.0 == symbol }?.1
        // Normal labels are templates for native contrast/selection. A warning tints
        // the whole icon red, so that drawing is non-template and redraws for the
        // appearance (there is no badge dot).
        let color: NSColor = needsWarning && colorScheme == .dark ? .white : .black
        let iconColor: NSColor = needsWarning ? .systemRed : color
        let title = text.map { NSAttributedString(string: $0, attributes: [.font: font, .foregroundColor: color]) }
        let glyphWidth = glyph?.size.width ?? iconWidth
        let contentWidth = glyphWidth + (title.map { gap + $0.size().width } ?? (needsWarning ? gap : 0))
        // Reserve two digits for normal readings; longer content can grow.
        // Center the complete icon + reading while retaining the same inner gap.
        let size = NSSize(width: max(minimumSize.width, ceil(contentWidth)), height: minimumSize.height)
        let contentX = (size.width - contentWidth) / 2
        let image = NSImage(size: size, flipped: false) { _ in
            if let glyph {
                let rect = NSRect(x: contentX,
                                  y: (size.height - glyph.size.height) / 2,
                                  width: glyph.size.width, height: glyph.size.height)
                glyph.draw(in: rect)
                iconColor.setFill()
                rect.fill(using: .sourceAtop)
            }
            if let title {
                title.draw(at: NSPoint(x: contentX + glyphWidth + gap, y: (size.height - title.size().height) / 2))
            }
            return true
        }
        image.isTemplate = !needsWarning
        return image
    }

    /// Widest the whole item may get before it starts shoving its neighbours
    /// (plan §4 V4). The gap is squeezed first; text is never truncated.
    static let maximumWidth: CGFloat = 72

    /// Width of the sparkline plot itself (plan §4 V2/V4).
    static let curveWidth: CGFloat = 40
    /// Blank space either side of the plot. The curve is the whole item, so without it
    /// it butts up against the neighbouring menu bar icons.
    static let curveHorizontalPadding: CGFloat = 4

    /// One or more sparklines filling the menu bar height.
    ///
    /// - **Vertical reference**: faint quarter lines, since the item has no room for
    ///   axis labels but a normalised curve still needs something to read against.
    /// - **Two curves get their own band** (temperature above, RPM below). They have
    ///   different units, so a shared scale would be meaningless — and because the
    ///   readings are strongly correlated, independently-normalised curves trace the
    ///   same line and the upper one is drawn over entirely.
    /// - Fewer than two points draws a flat mid line rather than nothing.
    /// - Coloured (never a template): a template can only be black or white.
    static func makeCurve(curves: [(values: [Float], color: NSColor)],
                          needsWarning: Bool,
                          statusBarThickness: CGFloat = NSStatusBar.system.thickness) -> NSImage {
        let padding = curveHorizontalPadding
        let size = NSSize(width: curveWidth + 2 * padding, height: max(statusBarThickness, 14))
        let verticalInset: CGFloat = 1.5
        let image = NSImage(size: size, flipped: false) { _ in
            // The stroke's round cap extends half its width past an endpoint, so the
            // plot is inset further than the padding: that keeps every pixel of ink
            // inside the plot and the padding genuinely blank.
            let capInset: CGFloat = 1
            let x0 = padding + capInset, x1 = size.width - padding - capInset
            let y0 = verticalInset, usable = size.height - 2 * verticalInset

            // Scale reference: nothing to label in 22pt, so faint quarter lines. They
            // span the plot, not the padding.
            let guides = NSBezierPath()
            guides.lineWidth = 0.5
            for fraction in [0.25, 0.5, 0.75] as [CGFloat] {
                let y = y0 + usable * fraction
                guides.move(to: NSPoint(x: x0, y: y))
                guides.line(to: NSPoint(x: x1, y: y))
            }
            NSColor.gray.withAlphaComponent(0.30).setStroke()
            guides.stroke()

            for (index, curve) in curves.enumerated() {
                // An alert is signalled by turning the item red, matching the icon.
                let color = needsWarning ? NSColor.systemRed : curve.color
                // One curve uses the whole canvas; two split it into bands.
                let lower: CGFloat = curves.count > 1 && index == 1 ? 0 : (curves.count > 1 ? 0.5 : 0)
                let upper: CGFloat = curves.count > 1 && index == 1 ? 0.5 : 1

                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.lineJoinStyle = .round
                path.lineCapStyle = .round
                let values = curve.values.filter { $0.isFinite }
                func y(_ norm: CGFloat) -> CGFloat { y0 + usable * (lower + (upper - lower) * norm) }
                if values.count < 2 {
                    let mid = y(0.5)
                    path.move(to: NSPoint(x: x0, y: mid))
                    path.line(to: NSPoint(x: x1, y: mid))
                } else {
                    let low = values.min() ?? 0
                    let span = (values.max() ?? 0) - low
                    for (i, value) in values.enumerated() {
                        let x = x0 + (x1 - x0) * CGFloat(i) / CGFloat(values.count - 1)
                        let norm = span > 0 ? CGFloat((value - low) / span) : 0.5
                        let point = NSPoint(x: x, y: y(norm))
                        if i == 0 { path.move(to: point) } else { path.line(to: point) }
                    }
                }
                color.setStroke()
                path.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Two-line variant: temperature above, RPM below, to the right of the icon.
    /// With a single value it falls back to the one-line layout, so the menu bar
    /// keeps its shipped look when only one number is shown. `statusBarThickness`
    /// should be the status button's real height when available, so the line size
    /// follows the actual bar rather than the (legacy) system constant.
    static func make(symbol: String, temperature: String?, rpm: String?,
                     needsWarning: Bool, colorScheme: ColorScheme,
                     statusBarThickness: CGFloat = NSStatusBar.system.thickness) -> NSImage {
        guard let temperature, let rpm else {
            return make(symbol: symbol, text: temperature ?? rpm,
                        needsWarning: needsWarning, colorScheme: colorScheme)
        }
        return makeTwoLine(symbol: symbol, top: temperature, bottom: rpm,
                           needsWarning: needsWarning, colorScheme: colorScheme,
                           statusBarThickness: statusBarThickness)
    }

    /// Line-height-to-point-size ratio of the monospaced digit font, measured once
    /// so the two-line size can be solved instead of hard-coded (a fixed size would
    /// mis-fit under a different status bar height or accessibility text size).
    private static let lineHeightRatio: CGFloat = {
        let probe = NSFont.monospacedDigitSystemFont(ofSize: 100, weight: .regular)
        return max(1.0, (probe.ascender - probe.descender + probe.leading) / 100)
    }()

    /// Largest font size whose two lines fit the status bar, capped at the menu bar
    /// font so a two-line reading never looks bigger than a one-line one.
    static func twoLineFont(statusBarThickness: CGFloat = NSStatusBar.system.thickness) -> NSFont {
        let menuSize = NSFont.menuBarFont(ofSize: 0).pointSize
        let available = max(statusBarThickness - 2, 14)   // 1pt margin top and bottom
        let size = min(menuSize, max(8, available / 2 / lineHeightRatio))
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    private static func makeTwoLine(symbol: String, top: String, bottom: String,
                                    needsWarning: Bool, colorScheme: ColorScheme,
                                    statusBarThickness: CGFloat) -> NSImage {
        let lineFont = twoLineFont(statusBarThickness: statusBarThickness)
        let glyph = symbols.first { $0.0 == symbol }?.1
        let color: NSColor = needsWarning && colorScheme == .dark ? .white : .black
        let iconColor: NSColor = needsWarning ? .systemRed : color
        let topLine = NSAttributedString(string: top, attributes: [.font: lineFont, .foregroundColor: color])
        let bottomLine = NSAttributedString(string: bottom, attributes: [.font: lineFont, .foregroundColor: color])
        let textWidth = ceil(max(topLine.size().width, bottomLine.size().width))
        let glyphWidth = glyph?.size.width ?? iconWidth

        // Reserve room for a two-digit temperature and a four-digit RPM so a digit
        // change does not resize the item, then squeeze the gap before exceeding
        // the width cap.
        let reserve = ceil(max(("88°" as NSString).size(withAttributes: [.font: lineFont]).width,
                               ("8888" as NSString).size(withAttributes: [.font: lineFont]).width))
        var gap = self.gap
        if glyphWidth + gap + max(textWidth, reserve) > maximumWidth { gap = 1 }
        let contentWidth = glyphWidth + gap + max(textWidth, reserve)
        let linesHeight = ceil(topLine.size().height + bottomLine.size().height)
        let size = NSSize(width: max(minimumSize.width, contentWidth),
                          height: max(minimumSize.height, linesHeight))

        let image = NSImage(size: size, flipped: false) { _ in
            let contentX = (size.width - contentWidth) / 2
            if let glyph {
                let rect = NSRect(x: contentX, y: (size.height - glyph.size.height) / 2,
                                  width: glyph.size.width, height: glyph.size.height)
                glyph.draw(in: rect)
                iconColor.setFill()
                rect.fill(using: .sourceAtop)
            }
            let textX = contentX + glyphWidth + gap
            let topY = (size.height + linesHeight) / 2 - topLine.size().height
            topLine.draw(at: NSPoint(x: textX, y: topY))
            bottomLine.draw(at: NSPoint(x: textX, y: topY - bottomLine.size().height))
            return true
        }
        image.isTemplate = !needsWarning
        return image
    }
}
