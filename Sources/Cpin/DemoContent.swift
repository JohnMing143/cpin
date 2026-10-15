import AppKit
import CpinCore

/// An isolated, opt-in preview. It never observes or writes the system clipboard.
enum DemoContent {
    static func populate(_ history: ClipboardHistory) throws {
        let now = Date()
        try history.addText("少一点打断，多一点专注。\n\n常用的文字、链接和图片，\n随手复制，随时找回。", sourceName: "备忘录", sourceBundleIdentifier: "com.apple.Notes", at: now.addingTimeInterval(-1920))
        try history.addText("https://github.com/apple/swift", sourceName: "Safari", sourceBundleIdentifier: "com.apple.Safari", at: now.addingTimeInterval(-960))
        try history.addText("周末的小计划\n\n☐ 买一束鲜花\n☐ 去海边走走\n☐ 整理这一周的灵感", sourceName: "备忘录", sourceBundleIdentifier: "com.apple.Notes", at: now.addingTimeInterval(-720))
        try history.addText("struct LittleThings {\n    let ideas: [String]\n\n    func keep() {\n        ideas.forEach(save)\n    }\n}", sourceName: "Xcode", sourceBundleIdentifier: "com.apple.dt.Xcode", at: now.addingTimeInterval(-300))
        try history.addText("https://www.swift.org/documentation/", sourceName: "Safari", sourceBundleIdentifier: "com.apple.Safari", at: now.addingTimeInterval(-180))
        try history.addImage(landscape(), width: 960, height: 640, sourceName: "预览", sourceBundleIdentifier: "com.apple.Preview", at: now.addingTimeInterval(-60))
        if let note = try history.addText("把灵感留住。\n\n一段文字，一个链接，\n还有稍纵即逝的好想法。", sourceName: "备忘录", sourceBundleIdentifier: "com.apple.Notes", at: now.addingTimeInterval(-30)) {
            try history.togglePin(note.id)
        }
    }

    private static func landscape() throws -> Data {
        let size = NSSize(width: 960, height: 640)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 640, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSGradient(colors: [NSColor(red: 0.98, green: 0.77, blue: 0.61, alpha: 1), NSColor(red: 0.62, green: 0.75, blue: 0.76, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: 90)
        NSColor(red: 1, green: 0.93, blue: 0.74, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 635, y: 345, width: 126, height: 126)).fill()
        let hills: [(NSColor, CGFloat, CGFloat)] = [
            (NSColor(red: 0.28, green: 0.47, blue: 0.49, alpha: 1), 280, 190),
            (NSColor(red: 0.16, green: 0.36, blue: 0.38, alpha: 1), 175, 150),
            (NSColor(red: 0.10, green: 0.27, blue: 0.31, alpha: 1), 70, 90)
        ]
        for (color, level, variation) in hills {
            color.setFill()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: 0))
            path.line(to: NSPoint(x: 0, y: level))
            path.curve(to: NSPoint(x: 960, y: level - 30), controlPoint1: NSPoint(x: 260, y: level + variation), controlPoint2: NSPoint(x: 560, y: level - variation))
            path.line(to: NSPoint(x: 960, y: 0))
            path.close()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
