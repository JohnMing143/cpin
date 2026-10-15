import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

func icon(pixels: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 204, yRadius: 204)
    NSGradient(starting: NSColor(red: 0.98, green: 0.59, blue: 0.35, alpha: 1), ending: NSColor(red: 0.86, green: 0.32, blue: 0.17, alpha: 1))!
        .draw(in: background, angle: -70)
    NSColor.white.withAlphaComponent(0.43).setFill()
    NSBezierPath(roundedRect: NSRect(x: 244, y: 394, width: 420, height: 390), xRadius: 74, yRadius: 74).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 362, y: 245, width: 420, height: 390), xRadius: 74, yRadius: 74).fill()
    NSColor(red: 0.90, green: 0.40, blue: 0.23, alpha: 1).withAlphaComponent(0.8).setFill()
    for (y, width) in [(492.0, 210.0), (414.0, 158.0)] {
        NSBezierPath(roundedRect: NSRect(x: 448, y: y, width: width, height: 25), xRadius: 12.5, yRadius: 12.5).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

func uint32(_ value: Int) -> Data {
    var bytes = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bytes) { Data($0) }
}

// ICNS supports embedded PNG representations; build the container directly so
// generating an app icon doesn't depend on Xcode or the iconutil service.
var representations = Data()
for (type, pixels) in [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)] {
    let png = try icon(pixels: pixels)
    representations.append(Data(type.utf8))
    representations.append(uint32(png.count + 8))
    representations.append(png)
}
var container = Data("icns".utf8)
container.append(uint32(representations.count + 8))
container.append(representations)
try container.write(to: output, options: .atomic)
