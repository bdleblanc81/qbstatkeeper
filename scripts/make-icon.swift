import AppKit

// App icon: a red quiz bowl buzzer on the blue tile, with "QBS" underneath.
func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.78, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.2, blue: 0.5, alpha: 1))!.draw(in: path, angle: -90)

    // buzzer: a big red dome on a dark base, centered
    let cx = s * 0.5
    let dome = NSBezierPath(ovalIn: NSRect(x: cx - s * 0.25, y: s * 0.37, width: s * 0.50, height: s * 0.50))
    NSGradient(starting: NSColor(calibratedRed: 1.0, green: 0.40, blue: 0.34, alpha: 1), ending: NSColor(calibratedRed: 0.74, green: 0.09, blue: 0.11, alpha: 1))!
        .draw(in: dome, angle: -90)
    let shine = NSBezierPath(ovalIn: NSRect(x: cx - s * 0.15, y: s * 0.66, width: s * 0.16, height: s * 0.085))
    NSColor(calibratedWhite: 1, alpha: 0.55).setFill(); shine.fill()
    // the base covers the lower part of the dome
    let base = NSBezierPath(roundedRect: NSRect(x: cx - s * 0.31, y: s * 0.32, width: s * 0.62, height: s * 0.10), xRadius: s * 0.045, yRadius: s * 0.045)
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill(); base.fill()

    // "QBS" underneath
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s * 0.19, weight: .heavy), .foregroundColor: NSColor.white, .paragraphStyle: para]
    let text = NSAttributedString(string: "QBS", attributes: attrs)
    let h = text.size().height
    text.draw(in: NSRect(x: 0, y: s * 0.13 + (s * 0.15 - h) / 2 + s * 0.005, width: s, height: h))

    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
