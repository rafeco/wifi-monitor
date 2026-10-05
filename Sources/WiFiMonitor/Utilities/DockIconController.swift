import AppKit

/// Keeps the installed app icon unchanged, but tints the WiFi arcs in the
/// running Dock icon when the current connection is degraded, and adds a
/// prominent Ethernet badge while the monitored route uses a wired interface.
@MainActor
enum DockIconController {
    private static var originalIcon: NSImage?
    private struct Appearance: Hashable {
        let rating: FeelsLikeScore.Rating
        let isWired: Bool
    }
    private static var icons: [Appearance: NSImage] = [:]
    private static var currentAppearance: Appearance?

    static func update(for rating: FeelsLikeScore.Rating, isWired: Bool) {
        let appearance = Appearance(rating: rating, isWired: isWired)
        guard appearance != currentAppearance else { return }

        if originalIcon == nil {
            originalIcon = NSApplication.shared.applicationIconImage.copy() as? NSImage
        }
        guard let originalIcon else { return }

        guard let icon = icons[appearance] ?? makeIcon(from: originalIcon, rating: rating, isWired: isWired) else { return }
        icons[appearance] = icon
        NSApplication.shared.applicationIconImage = icon

        currentAppearance = appearance
    }

    /// Shares the production renderer with the preview script.
    static func makeIcon(from image: NSImage, rating: FeelsLikeScore.Rating, isWired: Bool) -> NSImage? {
        let base: NSImage
        if rating == .smooth {
            base = image
        } else {
            guard let tinted = makeTintedIcon(from: image, color: color(for: rating)) else { return nil }
            base = tinted
        }
        guard isWired else { return base }

        // Draw the <•••> badge as vectors so it stays crisp at every Dock size.
        return NSImage(size: image.size, flipped: false) { rect in
            base.draw(in: rect)
            // Center the badge beneath the arcs, covering the original dot.
            // The wide white capsule remains recognizable at a 32-point Dock size.
            let badge = NSRect(x: rect.width * 0.19, y: rect.height * 0.06,
                               width: rect.width * 0.62, height: rect.height * 0.27)
            let pill = NSBezierPath(roundedRect: badge, xRadius: badge.height / 2, yRadius: badge.height / 2)
            NSColor.white.setFill()
            pill.fill()
            let ink = NSColor(calibratedRed: 0.02, green: 0.10, blue: 0.24, alpha: 1)
            ink.setStroke()
            pill.lineWidth = rect.width * 0.008
            pill.stroke()

            let brackets = NSBezierPath()
            brackets.lineWidth = badge.height * 0.13
            brackets.lineCapStyle = .round
            brackets.lineJoinStyle = .round
            for right in [false, true] {
                let innerX = badge.minX + badge.width * (right ? 0.78 : 0.22)
                let outerX = badge.minX + badge.width * (right ? 0.88 : 0.12)
                brackets.move(to: NSPoint(x: innerX, y: badge.minY + badge.height * 0.72))
                brackets.line(to: NSPoint(x: outerX, y: badge.midY))
                brackets.line(to: NSPoint(x: innerX, y: badge.minY + badge.height * 0.28))
            }
            brackets.stroke()
            ink.setFill()
            let diameter = badge.height * 0.18
            for position in [0.36, 0.50, 0.64] {
                NSBezierPath(ovalIn: NSRect(x: badge.minX + badge.width * position - diameter / 2,
                                           y: badge.midY - diameter / 2,
                                           width: diameter, height: diameter)).fill()
            }
            return true
        }
    }

    private static func color(for rating: FeelsLikeScore.Rating) -> NSColor {
        switch rating {
        case .smooth: return .white
        case .usable: return .systemYellow
        case .rough: return .systemOrange
        case .down: return .systemRed
        }
    }

    /// The source artwork has a blue gradient with a pure-white WiFi glyph.
    /// Its three arcs occupy the upper two-thirds; the dot is below them. The
    /// red channel therefore acts as the antialiased glyph mask, letting us
    /// recolor the arcs while preserving their smooth edges and the white dot.
    private static func makeTintedIcon(from image: NSImage, color: NSColor) -> NSImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else { return nil }

        let width = source.width
        let height = source.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let tint = color.usingColorSpace(.deviceRGB) else { return nil }
        let tintComponents = [tint.redComponent, tint.greenComponent, tint.blueComponent]

        // The pixel buffer is top-origin. All three arcs end above 67% of the
        // image height, while the dot begins just below that line.
        let rowAfterArcs = Int(Double(height) * 0.67)
        for y in 0..<rowAfterArcs {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = pixels[offset]

                // The gradient has effectively no red. Red in this region is
                // the coverage of the antialiased white glyph over it.
                guard red > 8 else { continue }
                let coverage = CGFloat(red) / 255

                for component in 0..<3 {
                    let original = CGFloat(pixels[offset + component])
                    let tinted = original + coverage * (tintComponents[component] * 255 - 255)
                    pixels[offset + component] = UInt8(clamping: Int(tinted.rounded()))
                }
            }
        }

        guard let output = context.makeImage() else { return nil }
        let result = NSImage(size: image.size)
        result.addRepresentation(NSBitmapImageRep(cgImage: output))
        return result
    }
}
