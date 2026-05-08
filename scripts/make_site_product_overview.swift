#!/usr/bin/env swift
import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "site/public/product-overview.png"
let width = 1580
let height = 1041

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create bitmap")
}

let context = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255
    let green = CGFloat((hex >> 8) & 0xff) / 255
    let blue = CGFloat(hex & 0xff) / 255
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func topRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(height) - y - h, width: w, height: h)
}

func fillRound(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: topRect(x, y, w, h), xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func fillCircle(_ x: CGFloat, _ y: CGFloat, _ diameter: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(ovalIn: topRect(x, y, diameter, diameter)).fill()
}

func drawText(
    _ value: String,
    x: CGFloat,
    y: CGFloat,
    w: CGFloat,
    h: CGFloat,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color textColor: NSColor = color(0xffffff),
    alignment: NSTextAlignment = .left
) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byTruncatingTail
    style.maximumLineHeight = h
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: textColor,
        .paragraphStyle: style
    ]
    (value as NSString).draw(in: topRect(x, y, w, h), withAttributes: attrs)
}

func drawLine(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ stroke: NSColor, width lineWidth: CGFloat = 1) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x1, y: CGFloat(height) - y1))
    path.line(to: NSPoint(x: x2, y: CGFloat(height) - y2))
    stroke.setStroke()
    path.lineWidth = lineWidth
    path.stroke()
}

color(0x050505).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let windowX: CGFloat = 34
let windowY: CGFloat = 28
let windowW: CGFloat = 1512
let windowH: CGFloat = 985
fillRound(windowX, windowY, windowW, windowH, 24, color(0x1b1d1d), stroke: color(0x575b5b), lineWidth: 1.2)

let sidebarW: CGFloat = 250
fillRound(windowX, windowY, sidebarW, windowH, 24, color(0x272929))
fillRound(windowX + sidebarW - 1, windowY, 1, windowH, 0, color(0x3a3d3d))

fillCircle(54, 47, 14, color(0x6b6b6b))
fillCircle(77, 47, 14, color(0x5f5f5f))
fillCircle(100, 47, 14, color(0x555555))
drawText("Monitor", x: 56, y: 84, w: 120, h: 18, size: 11, weight: .semibold, color: color(0x858989))

let selectedY: CGFloat = 98
fillRound(52, selectedY, 220, 32, 7, color(0x555858))
drawText("Overview", x: 88, y: selectedY + 8, w: 150, h: 18, size: 14, weight: .medium, color: color(0xe7e7e7))
drawText("Requests", x: 88, y: 142, w: 150, h: 18, size: 14, weight: .medium, color: color(0xa2a5a5))
drawText("Issues", x: 88, y: 174, w: 150, h: 18, size: 14, weight: .medium, color: color(0xa2a5a5))
drawText("Logs", x: 88, y: 206, w: 150, h: 18, size: 14, weight: .medium, color: color(0xa2a5a5))
drawText("Configuration", x: 56, y: 245, w: 140, h: 18, size: 11, weight: .semibold, color: color(0x858989))
drawText("Providers", x: 88, y: 271, w: 150, h: 18, size: 14, weight: .medium, color: color(0xa2a5a5))
drawText("Models", x: 88, y: 303, w: 150, h: 18, size: 14, weight: .medium, color: color(0xa2a5a5))
drawText("Credentials", x: 88, y: 335, w: 150, h: 18, size: 14, weight: .medium, color: color(0xa2a5a5))

drawLine(54, 878, 270, 878, color(0x454747))
fillCircle(54, 899, 9, color(0x38d66b))
drawText("Gateway Running", x: 72, y: 891, w: 150, h: 17, size: 11, weight: .bold, color: color(0xf0f0f0))
drawText("127.0.0.1:4000", x: 72, y: 908, w: 140, h: 16, size: 11, weight: .medium, color: color(0xb7bbbb))
drawText("7", x: 54, y: 934, w: 34, h: 18, size: 12, weight: .bold, color: color(0xf2f2f2))
drawText("Requests", x: 54, y: 950, w: 62, h: 16, size: 10, weight: .medium, color: color(0xa6aaaa))
drawText("2", x: 128, y: 934, w: 34, h: 18, size: 12, weight: .bold, color: color(0xf2f2f2))
drawText("Providers", x: 128, y: 950, w: 70, h: 16, size: 10, weight: .medium, color: color(0xa6aaaa))
drawText("3", x: 204, y: 934, w: 34, h: 18, size: 12, weight: .bold, color: color(0xf2f2f2))
drawText("Models", x: 204, y: 950, w: 60, h: 16, size: 10, weight: .medium, color: color(0xa6aaaa))
drawText("v1.0.16", x: 54, y: 974, w: 70, h: 16, size: 10, weight: .medium, color: color(0x777b7b))

let contentX = windowX + sidebarW
drawText("Overview", x: contentX + 20, y: 48, w: 120, h: 24, size: 15, weight: .bold, color: color(0x6d7070))
drawText("Gateway Overview", x: contentX + 24, y: 138, w: 400, h: 34, size: 28, weight: .bold, color: color(0xf4f4f4))
drawText("Monitor local traffic and keep Claude routed through your configured providers.", x: contentX + 24, y: 173, w: 620, h: 22, size: 14, weight: .medium, color: color(0xb5b9b9))

fillRound(contentX + 24, 208, 1198, 140, 12, color(0x282a2a))
let factY: CGFloat = 226
drawText("Status", x: contentX + 72, y: factY, w: 140, h: 16, size: 11, weight: .semibold, color: color(0xa6aaaa))
drawText("Running", x: contentX + 72, y: factY + 18, w: 140, h: 22, size: 15, weight: .bold, color: color(0xf4f4f4))
drawText("LaunchAgent is active", x: contentX + 72, y: factY + 41, w: 180, h: 18, size: 11, weight: .medium, color: color(0xa6aaaa))
fillCircle(contentX + 46, factY + 1, 14, color(0x1f8848))

drawText("Endpoint", x: contentX + 440, y: factY, w: 180, h: 16, size: 11, weight: .semibold, color: color(0xa6aaaa))
drawText("127.0.0.1:4000", x: contentX + 440, y: factY + 18, w: 180, h: 22, size: 15, weight: .bold, color: color(0xf4f4f4))
drawText("Local Anthropic-compatible API", x: contentX + 440, y: factY + 41, w: 220, h: 18, size: 11, weight: .medium, color: color(0xa6aaaa))

drawText("Primary Provider", x: contentX + 838, y: factY, w: 180, h: 16, size: 11, weight: .semibold, color: color(0xa6aaaa))
drawText("Custom Provider", x: contentX + 838, y: factY + 18, w: 180, h: 22, size: 15, weight: .bold, color: color(0xf4f4f4))
drawText("https://provider.example.com/anthropic", x: contentX + 838, y: factY + 41, w: 260, h: 18, size: 11, weight: .medium, color: color(0xa6aaaa))

drawText("Models", x: contentX + 72, y: factY + 64, w: 140, h: 16, size: 11, weight: .semibold, color: color(0xa6aaaa))
drawText("3 advertised", x: contentX + 72, y: factY + 82, w: 160, h: 22, size: 15, weight: .bold, color: color(0xf4f4f4))
drawText("Explicit provider routes", x: contentX + 72, y: factY + 105, w: 200, h: 18, size: 11, weight: .medium, color: color(0xa6aaaa))

drawText("Default Route", x: contentX + 440, y: factY + 64, w: 140, h: 16, size: 11, weight: .semibold, color: color(0xa6aaaa))
drawText("custom / claude-sonnet-4-6", x: contentX + 440, y: factY + 82, w: 260, h: 22, size: 15, weight: .bold, color: color(0xf4f4f4))
drawText("Editable in Models", x: contentX + 440, y: factY + 105, w: 200, h: 18, size: 11, weight: .medium, color: color(0xa6aaaa))

drawText("Log Tail", x: contentX + 838, y: factY + 64, w: 140, h: 16, size: 11, weight: .semibold, color: color(0xa6aaaa))
drawText("6 loaded", x: contentX + 838, y: factY + 82, w: 160, h: 22, size: 15, weight: .bold, color: color(0xf4f4f4))
drawText("Recent traffic is available", x: contentX + 838, y: factY + 105, w: 210, h: 18, size: 11, weight: .medium, color: color(0xa6aaaa))

let cardY: CGFloat = 370
let cards = [
    ("Requests", "7", "New in this range"),
    ("Input Tokens", "1.1k", "New in this range"),
    ("Output Tokens", "2.4k", "New in this range"),
    ("Average Latency", "418 ms", "No comparison"),
    ("Error Rate", "0%", "No change")
]
for (index, card) in cards.enumerated() {
    let x = contentX + 24 + CGFloat(index) * 174
    fillRound(x, cardY, 162, 90, 10, color(0x262828))
    drawText(card.0, x: x + 16, y: cardY + 17, w: 128, h: 17, size: 10, weight: .semibold, color: color(0xa6aaaa))
    drawText(card.1, x: x + 16, y: cardY + 38, w: 128, h: 24, size: 20, weight: .bold, color: color(0xf6f6f6))
    drawText(card.2, x: x + 16, y: cardY + 65, w: 128, h: 17, size: 10, weight: .medium, color: color(0xa6aaaa))
}

drawText("Request Rate", x: contentX + 54, y: 486, w: 200, h: 20, size: 14, weight: .bold, color: color(0xf2f2f2))
fillRound(contentX + 24, 508, 1198, 246, 12, color(0x262828))
drawText("0.10 req/s", x: contentX + 42, y: 530, w: 128, h: 24, size: 18, weight: .bold, color: color(0xf7f7f7))
drawText("average", x: contentX + 166, y: 535, w: 80, h: 16, size: 10, weight: .medium, color: color(0xa6aaaa))
drawLine(contentX + 54, 554, contentX + 1182, 554, color(0x444747))
drawLine(contentX + 54, 736, contentX + 1182, 736, color(0x444747))
drawText("1", x: contentX + 40, y: 547, w: 20, h: 18, size: 10, weight: .medium, color: color(0xa6aaaa))
drawText("0", x: contentX + 40, y: 729, w: 20, h: 18, size: 10, weight: .medium, color: color(0xa6aaaa))

let graphPath = NSBezierPath()
let graphPoints: [(CGFloat, CGFloat)] = [
    (contentX + 156, 736), (contentX + 238, 560), (contentX + 338, 546),
    (contentX + 410, 730), (contentX + 536, 722), (contentX + 620, 556),
    (contentX + 708, 730), (contentX + 838, 734), (contentX + 928, 554),
    (contentX + 1008, 730), (contentX + 1102, 556), (contentX + 1182, 736)
]
for (index, point) in graphPoints.enumerated() {
    let converted = NSPoint(x: point.0, y: CGFloat(height) - point.1)
    if index == 0 {
        graphPath.move(to: converted)
    } else {
        graphPath.line(to: converted)
    }
}
color(0x0a84ff).setStroke()
graphPath.lineWidth = 2
graphPath.stroke()

drawText("Recent Requests", x: contentX + 54, y: 782, w: 200, h: 20, size: 14, weight: .bold, color: color(0xf2f2f2))
fillRound(contentX + 24, 803, 1198, 194, 12, color(0x262828))
let tableX = contentX + 42
let tableY: CGFloat = 827
let headers = [("Time", 0), ("Method", 120), ("Route", 230), ("Provider", 500), ("Status", 680), ("Latency", 790), ("Model", 900)]
for header in headers {
    drawText(header.0, x: tableX + CGFloat(header.1), y: tableY, w: 150, h: 18, size: 11, weight: .bold, color: color(0xd8d8d8))
}
drawLine(tableX, tableY + 22, contentX + 1184, tableY + 22, color(0x454747))
let rows = [
    ("22:31:43", "POST", "/v1/messages", "custom", "200", "95ms", "claude-sonnet-4-6"),
    ("22:31:35", "POST", "/v1/messages", "custom", "200", "420ms", "claude-haiku-4-5"),
    ("22:31:20", "POST", "/v1/messages/count_tokens", "backup", "200", "1.2s", "claude-opus-4-7"),
    ("22:30:59", "GET", "/v1/models", "gateway", "200", "18ms", "3 models")
]
for (index, row) in rows.enumerated() {
    let y = tableY + 42 + CGFloat(index) * 27
    if index % 2 == 1 {
        fillRound(tableX - 6, y - 2, 1150, 24, 6, color(0x303232))
    }
    drawText(row.0, x: tableX, y: y, w: 90, h: 18, size: 12, weight: .medium, color: color(0xe8e8e8))
    drawText(row.1, x: tableX + 120, y: y, w: 80, h: 18, size: 12, weight: .medium, color: color(0xe8e8e8))
    drawText(row.2, x: tableX + 230, y: y, w: 230, h: 18, size: 12, weight: .medium, color: color(0xe8e8e8))
    drawText(row.3, x: tableX + 500, y: y, w: 120, h: 18, size: 12, weight: .medium, color: color(0xe8e8e8))
    drawText(row.4, x: tableX + 680, y: y, w: 70, h: 18, size: 12, weight: .bold, color: color(0x28f06d))
    drawText(row.5, x: tableX + 790, y: y, w: 80, h: 18, size: 12, weight: .medium, color: color(0xe8e8e8))
    drawText(row.6, x: tableX + 900, y: y, w: 220, h: 18, size: 12, weight: .medium, color: color(0xe8e8e8))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)
print("Generated \(outputURL.path)")
