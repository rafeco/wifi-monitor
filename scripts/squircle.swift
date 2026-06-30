import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3 else {
    print("Usage: squircle <input.png> <output.png>")
    exit(1)
}

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])

guard let src = NSImage(contentsOf: inputURL) else {
    print("Failed to load \(args[1])")
    exit(1)
}

let size = src.size

// Inset the squircle shape itself so the icon appears ~80% of the Dock slot,
// matching Apple's HIG guidance on visual weight. The source image fills the
// squircle edge-to-edge; transparent canvas outside the squircle is the padding.
let padding = size.width * 0.05
let squircleRect = NSRect(x: padding, y: padding,
                          width: size.width - padding * 2,
                          height: size.height - padding * 2)
let radius = squircleRect.width * 0.225

let result = NSImage(size: size)
result.lockFocus()

let path = NSBezierPath(roundedRect: squircleRect, xRadius: radius, yRadius: radius)
path.addClip()
src.draw(in: NSRect(origin: .zero, size: size))

result.unlockFocus()

guard let tiff = result.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to encode output")
    exit(1)
}

try! png.write(to: outputURL)
print("Wrote \(outputURL.path)")
