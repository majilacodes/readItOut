// Draws the app icon: an open book with a highlighted line and a voice waveform above it.
// Run with: swift Resources/make_icon.swift (build.sh does this whenever this file changes).
import AppKit

let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw(_ ctx: CGContext) {
    // Background: the standard macOS icon shape, inset from the canvas, with a soft shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x1E2470))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(colorsSpace: nil, colors: [color(0x4A5CF0), color(0x1E2470)] as CFArray,
                                locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // The voice: a waveform above the book, loudest in the middle.
    let heights: [CGFloat] = [56, 110, 170, 230, 150, 196, 104, 60]
    let barWidth: CGFloat = 36, gap: CGFloat = 24
    let waveWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    for (i, height) in heights.enumerated() {
        let x = 512 - waveWidth / 2 + CGFloat(i) * (barWidth + gap)
        let bar = CGRect(x: x, y: 762 - height / 2, width: barWidth, height: height)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.setFillColor(color(0xFFFFFF, 0.95))
        ctx.fillPath()
    }

    // The book's cover, peeking out below the pages.
    func page(outerX: CGFloat, lift: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let spineBottom = CGPoint(x: 512, y: 245 - lift)
        let spineTop = CGPoint(x: 512, y: 575)
        path.move(to: spineBottom)
        path.addQuadCurve(to: CGPoint(x: outerX, y: 285 - lift), control: CGPoint(x: (512 + outerX) / 2, y: 290 - lift))
        path.addLine(to: CGPoint(x: outerX, y: 615))
        path.addQuadCurve(to: spineTop, control: CGPoint(x: (512 + outerX) / 2, y: 640))
        path.closeSubpath()
        return path
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.3))
    ctx.setFillColor(color(0xE8A93A))
    for outerX in [205.0, 819.0] as [CGFloat] {
        ctx.addPath(page(outerX: outerX, lift: 22))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Pages, slightly shaded toward the spine.
    for outerX in [228.0, 796.0] as [CGFloat] {
        ctx.saveGState()
        ctx.addPath(page(outerX: outerX, lift: 0))
        ctx.clip()
        let paper = CGGradient(colorsSpace: nil, colors: [color(0xFFFCF4), color(0xE9E1CF)] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(paper, start: CGPoint(x: outerX, y: 0), end: CGPoint(x: 512, y: 0), options: [])
        ctx.restoreGState()
    }

    // Lines of text, one of them highlighted on the right page.
    func line(from x0: CGFloat, to x1: CGFloat, y: CGFloat, _ fill: CGColor, height: CGFloat = 18, radius: CGFloat = 9) {
        let rect = CGRect(x: x0, y: y - height / 2, width: x1 - x0, height: height)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(fill)
        ctx.fillPath()
    }
    let ink = color(0xB9AF9C)
    line(from: 542, to: 766, y: 455, color(0xFFD23F), height: 46, radius: 8)
    for (i, y) in ([530, 455, 380, 315] as [CGFloat]).enumerated() {
        let shorten: CGFloat = i == 3 ? 70 : 0
        line(from: 272, to: 470 - shorten, y: y - 8, ink)
        line(from: 556, to: 752 - shorten, y: y, i == 1 ? color(0x9A8556) : ink)
    }
    ctx.restoreGState()
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
draw(NSGraphicsContext.current!.cgContext)
NSGraphicsContext.current = nil

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
