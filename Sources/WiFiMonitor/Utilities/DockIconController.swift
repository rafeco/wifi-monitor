import AppKit

/// Keeps the installed app icon unchanged, but tints the WiFi arcs in the
/// running Dock icon when the current connection is degraded.
@MainActor
enum DockIconController {
    private static var originalIcon: NSImage?
    private static var tintedIcons: [FeelsLikeScore.Rating: NSImage] = [:]
    private static var currentRating: FeelsLikeScore.Rating?

    static func update(for rating: FeelsLikeScore.Rating) {
        guard rating != currentRating else { return }

        if originalIcon == nil {
            originalIcon = NSApplication.shared.applicationIconImage.copy() as? NSImage
        }
        guard let originalIcon else { return }

        switch rating {
        case .smooth:
            NSApplication.shared.applicationIconImage = originalIcon
        case .usable, .rough, .down:
            let icon = tintedIcons[rating] ?? makeTintedIcon(
                from: originalIcon,
                color: color(for: rating)
            )
            if let icon {
                tintedIcons[rating] = icon
                NSApplication.shared.applicationIconImage = icon
            }
        }

        currentRating = rating
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
