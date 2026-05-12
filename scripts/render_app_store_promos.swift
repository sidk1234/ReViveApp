import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDir = repoRoot.appendingPathComponent("Marketing/AppStorePromos", isDirectory: true)
let assetsDir = repoRoot.appendingPathComponent("ReVive/Assets.xcassets", isDirectory: true)

let logoURL = assetsDir.appendingPathComponent("LandscapeLogo.imageset/ReViveLogo.png")
let iconURL = assetsDir.appendingPathComponent("AppLogo.imageset/revivesquarelogo.png")
let deviceFrameURL = outputDir.appendingPathComponent("source-iphone-frame.png")
let promo0URL = outputDir.appendingPathComponent("source-promo-0.png")
let promo1URL = outputDir.appendingPathComponent("source-promo-1.png")
let promo2URL = outputDir.appendingPathComponent("source-promo-2.png")

guard
    let logoImage = NSImage(contentsOf: logoURL),
    let iconImage = NSImage(contentsOf: iconURL),
    let deviceFrameImage = NSImage(contentsOf: deviceFrameURL),
    let promo0Image = NSImage(contentsOf: promo0URL),
    let promo1Image = NSImage(contentsOf: promo1URL),
    let promo2Image = NSImage(contentsOf: promo2URL)
else {
    fputs("Failed to load required assets.\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let canvas = CGSize(width: 1290, height: 2796)

enum Palette {
    static let ink = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.12, alpha: 1.0)
    static let slate = NSColor(calibratedRed: 0.34, green: 0.38, blue: 0.42, alpha: 1.0)
    static let white = NSColor.white
    static let paper = NSColor(calibratedRed: 0.985, green: 0.985, blue: 0.975, alpha: 1.0)
    static let mint = NSColor(calibratedRed: 0.58, green: 0.83, blue: 0.41, alpha: 1.0)
    static let mintSoft = NSColor(calibratedRed: 0.90, green: 0.97, blue: 0.86, alpha: 1.0)
    static let sky = NSColor(calibratedRed: 0.39, green: 0.77, blue: 0.96, alpha: 1.0)
    static let skySoft = NSColor(calibratedRed: 0.87, green: 0.96, blue: 1.0, alpha: 1.0)
    static let silverTop = NSColor(calibratedWhite: 0.97, alpha: 1.0)
    static let silverMid = NSColor(calibratedWhite: 0.86, alpha: 1.0)
    static let silverBottom = NSColor(calibratedWhite: 0.78, alpha: 1.0)
    static let darkScreen = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.10, alpha: 1.0)
    static let forest = NSColor(calibratedRed: 0.15, green: 0.31, blue: 0.22, alpha: 1.0)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: w, height: h)
}

func roundedRect(_ frame: CGRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
}

func strokeRoundedRect(_ frame: CGRect, radius: CGFloat, color: NSColor, lineWidth: CGFloat) {
    color.setStroke()
    let path = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    path.lineWidth = lineWidth
    path.stroke()
}

func drawGradient(_ colors: [NSColor], in frame: CGRect, angle: CGFloat) {
    guard let gradient = NSGradient(colors: colors) else { return }
    gradient.draw(in: frame, angle: angle)
}

func drawCircle(_ frame: CGRect, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: frame).fill()
}

func drawLine(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat) {
    color.setStroke()
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineWidth = width
    path.lineCapStyle = .round
    path.stroke()
}

func font(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func textStyle(font: NSFont, color: NSColor, lineHeight: CGFloat = 1.0, alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byWordWrapping
    style.minimumLineHeight = font.pointSize * lineHeight
    style.maximumLineHeight = font.pointSize * lineHeight
    return [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style
    ]
}

func drawText(_ text: String, frame: CGRect, attributes: [NSAttributedString.Key: Any]) {
    NSString(string: text).draw(with: frame, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
}

func drawImageFit(_ image: NSImage, in target: CGRect, alpha: CGFloat = 1.0) {
    let source = image.size
    let scale = min(target.width / source.width, target.height / source.height)
    let size = CGSize(width: source.width * scale, height: source.height * scale)
    let origin = CGPoint(x: target.midX - size.width / 2, y: target.midY - size.height / 2)
    image.draw(in: CGRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: alpha)
}

func drawImageFill(_ image: NSImage, in target: CGRect, alpha: CGFloat = 1.0) {
    let source = image.size
    let scale = max(target.width / source.width, target.height / source.height) * 1.03
    let size = CGSize(width: source.width * scale, height: source.height * scale)
    let origin = CGPoint(x: target.midX - size.width / 2, y: target.midY - size.height / 2)
    image.draw(in: CGRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: alpha)
}

func withClip(_ path: NSBezierPath, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func drawPosterBackground(tint: NSColor) {
    Palette.paper.setFill()
    NSBezierPath(rect: rect(0, 0, canvas.width, canvas.height)).fill()
    drawCircle(rect(920, 1080, 220, 220), color: tint.withAlphaComponent(0.10))
    drawCircle(rect(130, 860, 180, 180), color: Palette.sky.withAlphaComponent(0.08))
}

func drawBrandHeader() {
    drawImageFit(logoImage, in: rect(355, 2530, 580, 130))
}

func drawHeadline(_ title: String) {
    drawText(
        title,
        frame: rect(120, 2230, 1050, 210),
        attributes: textStyle(font: font(104, weight: .bold), color: Palette.ink, lineHeight: 0.93, alignment: .center)
    )
}

func drawSubheadline(_ text: String) {
    drawText(
        text,
        frame: rect(170, 2110, 950, 80),
        attributes: textStyle(font: font(30, weight: .regular), color: Palette.slate, lineHeight: 1.18, alignment: .center)
    )
}

func drawPill(_ frame: CGRect, text: String, fill: NSColor = Palette.white, color: NSColor = Palette.ink) {
    roundedRect(frame, radius: frame.height / 2, color: fill)
    drawText(text, frame: frame.insetBy(dx: 18, dy: 12), attributes: textStyle(font: font(24, weight: .semibold), color: color, alignment: .center))
}

func drawPhoneFrame(screenRenderer: (CGRect) -> Void) {
    let phoneFrame = rect(242, 232, 806, 1648)
    let screenFrame = rect(
        phoneFrame.minX + 30,
        phoneFrame.minY + 54,
        phoneFrame.width - 60,
        phoneFrame.height - 108
    )
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = CGSize(width: 0, height: -6)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    drawImageFit(deviceFrameImage, in: phoneFrame)
    NSGraphicsContext.restoreGraphicsState()

    let screenPath = NSBezierPath(roundedRect: screenFrame, xRadius: 96, yRadius: 96)
    withClip(screenPath) {
        screenRenderer(screenFrame)
    }

    drawImageFit(deviceFrameImage, in: phoneFrame)
}

func drawPhoneFrame(with screenshot: NSImage) {
    drawPhoneFrame { screenFrame in
        drawImageFill(screenshot, in: screenFrame)
    }
}

func drawStatusBar(in screen: CGRect, dark: Bool) {
    let color = dark ? Palette.white : Palette.ink
    drawText("9:41", frame: rect(screen.minX + 42, screen.maxY - 78, 100, 30), attributes: textStyle(font: font(24, weight: .semibold), color: color))
    for index in 0..<3 {
        drawRoundedBar(rect(screen.maxX - 108 + CGFloat(index * 10), screen.maxY - 64, 6, CGFloat(12 + index * 5)), radius: 3, color: color)
    }
    roundedRect(rect(screen.maxX - 62, screen.maxY - 64, 28, 16), radius: 5, color: color)
}

func drawRoundedBar(_ frame: CGRect, radius: CGFloat, color: NSColor) {
    roundedRect(frame, radius: radius, color: color)
}

func drawScreenCard(_ frame: CGRect, color: NSColor = Palette.white, dark: Bool = false) {
    roundedRect(frame, radius: 30, color: color)
    strokeRoundedRect(frame, radius: 30, color: dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.06), lineWidth: 1)
}

func drawScanScreen(in screen: CGRect) {
    drawGradient([Palette.darkScreen, NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.12, alpha: 1)], in: screen, angle: 90)
    drawStatusBar(in: screen, dark: true)

    drawCircle(rect(screen.minX + 32, screen.maxY - 146, 58, 58), color: NSColor.white.withAlphaComponent(0.12))
    drawText("×", frame: rect(screen.minX + 50, screen.maxY - 132, 22, 26), attributes: textStyle(font: font(26, weight: .medium), color: Palette.white, alignment: .center))
    drawCircle(rect(screen.maxX - 90, screen.maxY - 146, 58, 58), color: NSColor.white.withAlphaComponent(0.12))
    drawText("?", frame: rect(screen.maxX - 72, screen.maxY - 132, 22, 26), attributes: textStyle(font: font(24, weight: .bold), color: Palette.white, alignment: .center))

    drawImageFit(iconImage, in: rect(screen.midX - 110, screen.maxY - 162, 220, 54), alpha: 1)

    let itemCard = rect(screen.minX + 90, screen.minY + 500, screen.width - 180, 560)
    roundedRect(itemCard, radius: 58, color: NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.11, alpha: 1))
    drawCircle(rect(itemCard.midX - 150, itemCard.midY - 150, 300, 300), color: NSColor(calibratedRed: 0.78, green: 0.16, blue: 0.08, alpha: 1))
    drawRoundedBar(rect(itemCard.midX - 112, itemCard.midY + 112, 224, 26), radius: 13, color: NSColor(calibratedWhite: 0.82, alpha: 1))
    drawRoundedBar(rect(itemCard.midX - 128, itemCard.midY - 138, 256, 36), radius: 18, color: NSColor(calibratedWhite: 0.86, alpha: 1))
    drawText("AL", frame: rect(itemCard.midX - 72, itemCard.midY - 32, 144, 86), attributes: textStyle(font: font(84, weight: .bold), color: Palette.white, alignment: .center))
    drawText("sparkling water", frame: rect(itemCard.midX - 120, itemCard.midY - 90, 240, 30), attributes: textStyle(font: font(24, weight: .medium), color: Palette.white.withAlphaComponent(0.86), alignment: .center))

    let neon = Palette.mint
    let s = itemCard.insetBy(dx: -20, dy: -20)
    drawLine(from: CGPoint(x: s.minX, y: s.maxY - 120), to: CGPoint(x: s.minX, y: s.maxY - 24), color: neon, width: 10)
    drawLine(from: CGPoint(x: s.minX, y: s.maxY - 24), to: CGPoint(x: s.minX + 96, y: s.maxY - 24), color: neon, width: 10)
    drawLine(from: CGPoint(x: s.maxX - 96, y: s.maxY - 24), to: CGPoint(x: s.maxX, y: s.maxY - 24), color: neon, width: 10)
    drawLine(from: CGPoint(x: s.maxX, y: s.maxY - 120), to: CGPoint(x: s.maxX, y: s.maxY - 24), color: neon, width: 10)
    drawLine(from: CGPoint(x: s.minX, y: s.minY + 24), to: CGPoint(x: s.minX, y: s.minY + 120), color: neon, width: 10)
    drawLine(from: CGPoint(x: s.minX, y: s.minY + 24), to: CGPoint(x: s.minX + 96, y: s.minY + 24), color: neon, width: 10)
    drawLine(from: CGPoint(x: s.maxX - 96, y: s.minY + 24), to: CGPoint(x: s.maxX, y: s.minY + 24), color: neon, width: 10)
    drawLine(from: CGPoint(x: s.maxX, y: s.minY + 24), to: CGPoint(x: s.maxX, y: s.minY + 120), color: neon, width: 10)

    drawPill(rect(screen.minX + 24, screen.minY + 800, 170, 58), text: "Aluminum", fill: Palette.white, color: Palette.ink)
    drawPill(rect(screen.maxX - 216, screen.minY + 660, 190, 58), text: "Low CO2e", fill: Palette.white, color: Palette.ink)
    drawPill(rect(screen.minX + 44, screen.minY + 482, 190, 58), text: "Drink can", fill: Palette.white, color: Palette.ink)

    drawScreenCard(rect(screen.minX + 116, screen.minY + 168, screen.width - 232, 116), color: Palette.white.withAlphaComponent(0.14), dark: true)
    drawText("Tap capture to identify and sort", frame: rect(screen.minX + 150, screen.minY + 206, screen.width - 300, 32), attributes: textStyle(font: font(26, weight: .semibold), color: Palette.white, alignment: .center))

    let bottomY = screen.minY + 64
    drawPill(rect(screen.minX + 100, bottomY + 90, 188, 66), text: "Scan Food", fill: Palette.white, color: Palette.ink)
    drawPill(rect(screen.midX - 94, bottomY + 90, 188, 66), text: "Barcode", fill: NSColor.black.withAlphaComponent(0.28), color: Palette.white)
    drawPill(rect(screen.maxX - 288, bottomY + 90, 188, 66), text: "Label", fill: NSColor.black.withAlphaComponent(0.28), color: Palette.white)
    drawCircle(rect(screen.midX - 58, bottomY - 4, 116, 116), color: Palette.white)
}

func drawResultScreen(in screen: CGRect) {
    drawGradient([Palette.paper, Palette.white], in: screen, angle: 90)
    drawStatusBar(in: screen, dark: false)
    drawText("Result", frame: rect(screen.midX - 60, screen.maxY - 124, 120, 34), attributes: textStyle(font: font(28, weight: .semibold), color: Palette.ink, alignment: .center))
    drawCircle(rect(screen.minX + 30, screen.maxY - 146, 58, 58), color: NSColor.black.withAlphaComponent(0.06))
    drawText("←", frame: rect(screen.minX + 48, screen.maxY - 132, 22, 28), attributes: textStyle(font: font(24, weight: .bold), color: Palette.ink, alignment: .center))

    let preview = rect(screen.minX + 70, screen.maxY - 700, screen.width - 140, 460)
    roundedRect(preview, radius: 52, color: Palette.mintSoft)
    drawCircle(rect(preview.midX - 118, preview.midY - 118, 236, 236), color: NSColor(calibratedRed: 0.79, green: 0.16, blue: 0.09, alpha: 1))
    drawText("AL", frame: rect(preview.midX - 70, preview.midY - 16, 140, 84), attributes: textStyle(font: font(80, weight: .bold), color: Palette.white, alignment: .center))

    let resultCard = rect(screen.minX + 36, screen.minY + 250, screen.width - 72, 620)
    drawScreenCard(resultCard)
    drawText("Sparkling Water Can", frame: rect(resultCard.minX + 36, resultCard.maxY - 96, 420, 42), attributes: textStyle(font: font(40, weight: .bold), color: Palette.ink))
    drawPill(rect(resultCard.maxX - 212, resultCard.maxY - 106, 176, 54), text: "Recycle", fill: Palette.mintSoft, color: Palette.forest)

    drawScreenCard(rect(resultCard.minX + 24, resultCard.maxY - 236, resultCard.width - 48, 126))
    drawImageFit(iconImage, in: rect(resultCard.minX + 34, resultCard.maxY - 216, 42, 42))
    drawText("CO2e saved", frame: rect(resultCard.minX + 84, resultCard.maxY - 168, 180, 28), attributes: textStyle(font: font(24, weight: .medium), color: Palette.slate))
    drawText("0.17 kg", frame: rect(resultCard.minX + 84, resultCard.maxY - 208, 240, 44), attributes: textStyle(font: font(48, weight: .bold), color: Palette.ink))

    let metricTitles = ["Material", "Points", "Bin"]
    let metricValues = ["Aluminum", "+10", "Blue cart"]
    for index in 0..<3 {
        let x = resultCard.minX + 24 + CGFloat(index) * 218
        let tile = rect(x, resultCard.maxY - 404, 194, 138)
        drawScreenCard(tile)
        drawText(metricTitles[index], frame: rect(x + 18, tile.maxY - 50, 160, 24), attributes: textStyle(font: font(20, weight: .medium), color: Palette.slate))
        drawText(metricValues[index], frame: rect(x + 18, tile.minY + 34, 160, 42), attributes: textStyle(font: font(30, weight: .bold), color: Palette.ink))
    }

    drawText("Quick prep", frame: rect(resultCard.minX + 28, resultCard.minY + 160, 180, 32), attributes: textStyle(font: font(28, weight: .bold), color: Palette.ink))
    drawText("Empty the can and drop it in your curbside recycling bin.", frame: rect(resultCard.minX + 28, resultCard.minY + 92, resultCard.width - 56, 54), attributes: textStyle(font: font(24, weight: .regular), color: Palette.slate, lineHeight: 1.18))

    drawPill(rect(resultCard.minX + 26, resultCard.minY + 26, 240, 60), text: "Fix result", fill: Palette.white, color: Palette.ink)
    roundedRect(rect(resultCard.maxX - 266, resultCard.minY + 22, 240, 68), radius: 34, color: Palette.ink)
    drawText("Mark recycled", frame: rect(resultCard.maxX - 266, resultCard.minY + 44, 240, 28), attributes: textStyle(font: font(24, weight: .semibold), color: Palette.white, alignment: .center))
}

func drawProgressScreen(in screen: CGRect) {
    drawGradient([Palette.paper, Palette.skySoft], in: screen, angle: 90)
    drawStatusBar(in: screen, dark: false)
    drawText("Progress", frame: rect(screen.minX + 34, screen.maxY - 124, 180, 36), attributes: textStyle(font: font(32, weight: .bold), color: Palette.ink))

    let topLeft = rect(screen.minX + 34, screen.maxY - 340, 300, 182)
    drawScreenCard(topLeft)
    drawText("This month", frame: rect(topLeft.minX + 22, topLeft.maxY - 44, 140, 24), attributes: textStyle(font: font(20, weight: .medium), color: Palette.slate))
    drawText("28 items", frame: rect(topLeft.minX + 22, topLeft.minY + 90, 180, 38), attributes: textStyle(font: font(36, weight: .bold), color: Palette.ink))
    drawText("recycled", frame: rect(topLeft.minX + 22, topLeft.minY + 50, 120, 28), attributes: textStyle(font: font(22, weight: .regular), color: Palette.slate))

    let topRight = rect(screen.maxX - 334, screen.maxY - 340, 300, 182)
    drawScreenCard(topRight, color: Palette.mintSoft)
    drawText("Current streak", frame: rect(topRight.minX + 22, topRight.maxY - 44, 160, 24), attributes: textStyle(font: font(20, weight: .medium), color: Palette.slate))
    drawText("12 days", frame: rect(topRight.minX + 22, topRight.minY + 90, 180, 38), attributes: textStyle(font: font(36, weight: .bold), color: Palette.forest))
    for index in 0..<7 {
        drawCircle(rect(topRight.minX + 24 + CGFloat(index) * 34, topRight.minY + 30, 18, 18), color: index < 5 ? Palette.mint : Palette.white)
    }

    let chart = rect(screen.minX + 34, screen.minY + 460, screen.width - 68, 540)
    drawScreenCard(chart)
    drawText("Weekly CO2e saved", frame: rect(chart.minX + 26, chart.maxY - 48, 280, 28), attributes: textStyle(font: font(28, weight: .bold), color: Palette.ink))
    let bars: [CGFloat] = [150, 210, 190, 280, 330, 390, 340]
    for (index, value) in bars.enumerated() {
        let x = chart.minX + 54 + CGFloat(index) * 96
        roundedRect(rect(x, chart.minY + 78, 58, value), radius: 20, color: index == bars.count - 1 ? Palette.sky : Palette.mint)
    }
    drawText("Mon     Tue     Wed     Thu     Fri     Sat     Sun", frame: rect(chart.minX + 46, chart.minY + 28, chart.width - 92, 24), attributes: textStyle(font: font(18, weight: .medium), color: Palette.slate))

    let summary = rect(screen.minX + 34, screen.minY + 220, screen.width - 68, 184)
    drawScreenCard(summary)
    drawText("Great job. Your recycling streak is up 18% from last week.", frame: rect(summary.minX + 24, summary.minY + 92, summary.width - 48, 44), attributes: textStyle(font: font(28, weight: .semibold), color: Palette.ink, lineHeight: 1.08))
    drawText("Next badge: Earthkeeper", frame: rect(summary.minX + 24, summary.minY + 42, 280, 28), attributes: textStyle(font: font(22, weight: .regular), color: Palette.slate))
}

func drawLeaderboardScreen(in screen: CGRect) {
    drawGradient([Palette.paper, Palette.white], in: screen, angle: 90)
    drawStatusBar(in: screen, dark: false)
    drawText("Ranks", frame: rect(screen.minX + 34, screen.maxY - 124, 160, 36), attributes: textStyle(font: font(32, weight: .bold), color: Palette.ink))

    drawPill(rect(screen.minX + 200, screen.maxY - 134, 260, 54), text: "Campus League", fill: Palette.white, color: Palette.ink)
    drawCircle(rect(screen.maxX - 90, screen.maxY - 146, 58, 58), color: NSColor.black.withAlphaComponent(0.06))
    drawText("≡", frame: rect(screen.maxX - 72, screen.maxY - 132, 22, 26), attributes: textStyle(font: font(24, weight: .bold), color: Palette.ink, alignment: .center))

    let podium = rect(screen.minX + 34, screen.maxY - 620, screen.width - 68, 420)
    drawScreenCard(podium)
    drawText("Top recyclers this week", frame: rect(podium.minX + 24, podium.maxY - 48, 320, 28), attributes: textStyle(font: font(28, weight: .bold), color: Palette.ink))

    let names = [("1", "You", "1280"), ("2", "Maya", "1210"), ("3", "Leo", "1120")]
    let heights: [CGFloat] = [208, 170, 138]
    let colors: [NSColor] = [Palette.mint, Palette.sky, Palette.slate]
    for index in 0..<3 {
        let x = podium.minX + 70 + CGFloat(index) * 214
        roundedRect(rect(x, podium.minY + 62, 154, heights[index]), radius: 30, color: colors[index])
        drawCircle(rect(x + 36, podium.minY + heights[index] + 80, 82, 82), color: Palette.paper)
        drawText(names[index].1.prefix(1).description, frame: rect(x + 63, podium.minY + heights[index] + 106, 28, 34), attributes: textStyle(font: font(34, weight: .bold), color: colors[index], alignment: .center))
        drawText(names[index].1, frame: rect(x + 22, podium.minY + 74, 110, 24), attributes: textStyle(font: font(24, weight: .bold), color: Palette.white, alignment: .center))
        drawText("\(names[index].2) pts", frame: rect(x + 18, podium.minY + 36, 118, 22), attributes: textStyle(font: font(18, weight: .semibold), color: Palette.white, alignment: .center))
    }

    let feed = rect(screen.minX + 34, screen.minY + 130, screen.width - 68, 760)
    drawScreenCard(feed)
    drawText("Friends activity", frame: rect(feed.minX + 24, feed.maxY - 46, 220, 28), attributes: textStyle(font: font(28, weight: .bold), color: Palette.ink))

    for index in 0..<3 {
        let row = rect(feed.minX + 22, feed.maxY - 156 - CGFloat(index) * 200, feed.width - 44, 152)
        roundedRect(row, radius: 26, color: index == 0 ? Palette.mintSoft : Palette.white)
        drawCircle(rect(row.minX + 20, row.maxY - 70, 50, 50), color: index == 1 ? Palette.sky : Palette.mint)
        let name = index == 0 ? "Maya" : index == 1 ? "Jordan" : "Chris"
        let action = index == 0 ? "recycled 4 cans" : index == 1 ? "saved 0.9 kg CO2e" : "hit a 7 day streak"
        drawText(name, frame: rect(row.minX + 86, row.maxY - 56, 180, 26), attributes: textStyle(font: font(24, weight: .bold), color: Palette.ink))
        drawText(action, frame: rect(row.minX + 86, row.minY + 54, row.width - 120, 26), attributes: textStyle(font: font(22, weight: .regular), color: Palette.slate))
        drawPill(rect(row.maxX - 148, row.minY + 44, 122, 48), text: index == 0 ? "+42" : index == 1 ? "Nice" : "React", fill: Palette.white, color: Palette.ink)
    }
}

func savePoster(named name: String, renderer: () -> Void) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width),
        pixelsHigh: Int(canvas.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = canvas

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    renderer()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let url = outputDir.appendingPathComponent(name)
    try rep.representation(using: .png, properties: [:])?.write(to: url)
}

func posterScanCycle() {
    drawPosterBackground(tint: Palette.mint)
    drawBrandHeader()
    drawHeadline("One Scan At A Time.")
    drawPhoneFrame(with: promo0Image)
}

func posterScanRecycle() {
    drawPosterBackground(tint: Palette.mint)
    drawBrandHeader()
    drawHeadline("Scan & Recycle")
    drawPhoneFrame(with: promo1Image)
}

func posterTrackImpactReal() {
    drawPosterBackground(tint: Palette.sky)
    drawBrandHeader()
    drawHeadline("Track Impact...")
    drawPhoneFrame(with: promo2Image)
}

func contactSheet() {
    Palette.paper.setFill()
    NSBezierPath(rect: rect(0, 0, canvas.width, canvas.height)).fill()
    drawText("ReVive App Store Promos", frame: rect(84, 2620, 900, 70), attributes: textStyle(font: font(56, weight: .bold), color: Palette.ink))
    let files = [
        "promo-scan-cycle.png",
        "promo-scan-recycle.png",
        "promo-track-impact-real.png"
    ]
    let positions: [CGRect] = [
        rect(74, 700, 360, 1780),
        rect(464, 700, 360, 1780),
        rect(854, 700, 360, 1780)
    ]
    for (index, file) in files.enumerated() {
        let url = outputDir.appendingPathComponent(file)
        if let image = NSImage(contentsOf: url) {
            drawImageFit(image, in: positions[index])
        }
    }
}

try savePoster(named: "promo-scan-cycle.png", renderer: posterScanCycle)
try savePoster(named: "promo-scan-recycle.png", renderer: posterScanRecycle)
try savePoster(named: "promo-track-impact-real.png", renderer: posterTrackImpactReal)
try savePoster(named: "promo-contact-sheet.png", renderer: contactSheet)

print(outputDir.path)
