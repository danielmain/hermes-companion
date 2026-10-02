import AppKit
import CoreGraphics

struct ScreenshotSpec {
    let source: String
    let destination: String
    let kicker: String
    let title: String
    let subtitle: String
}

let workspace = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let outputDirectory = "\(workspace)/assets/screenshots/app-store"
let backgroundPath = "\(workspace)/assets/screenshots/source/generated-paper-background.png"

let specs = [
    ScreenshotSpec(
        source: "\(workspace)/assets/screenshots/big/Screenshot 2026-10-01 at 15.35.31.png",
        destination: "\(outputDirectory)/01-daily-context.png",
        kicker: "HERMES / DAILY CONTEXT",
        title: "Your day, in context.",
        subtitle: "Health, activity, and location at a glance."
    ),
    ScreenshotSpec(
        source: "\(workspace)/assets/screenshots/big/Screenshot 2026-10-01 at 16.38.38.png",
        destination: "\(outputDirectory)/02-private-archive.png",
        kicker: "ARCHIVE / PRIVATE ICLOUD",
        title: "A record that stays yours.",
        subtitle: "Location history filed through your private iCloud."
    ),
    ScreenshotSpec(
        source: "\(workspace)/assets/screenshots/big/Screenshot 2026-10-01 at 15.35.17.png",
        destination: "\(outputDirectory)/03-tracking-control.png",
        kicker: "HERMES / OBSERVATION",
        title: "Tracking on your terms.",
        subtitle: "Choose accuracy, battery use, and background behavior."
    )
]

let canvasSize = NSSize(width: 1242, height: 2688)
let screenshotWidth: CGFloat = 1040
let screenshotX = (canvasSize.width - screenshotWidth) / 2
let screenshotBottom: CGFloat = 54

let ivory = NSColor(calibratedRed: 0.961, green: 0.949, blue: 0.918, alpha: 1)
let ink = NSColor(calibratedWhite: 0.055, alpha: 1)
let secondaryInk = NSColor(calibratedWhite: 0.34, alpha: 1)

func aspectFill(_ image: NSImage, in rect: NSRect) {
    let imageRatio = image.size.width / image.size.height
    let rectRatio = rect.width / rect.height
    var source = NSRect(origin: .zero, size: image.size)

    if imageRatio > rectRatio {
        let desiredWidth = image.size.height * rectRatio
        source.origin.x = (image.size.width - desiredWidth) / 2
        source.size.width = desiredWidth
    } else {
        let desiredHeight = image.size.width / rectRatio
        source.origin.y = (image.size.height - desiredHeight) / 2
        source.size.height = desiredHeight
    }

    image.draw(in: rect, from: source, operation: .sourceOver, fraction: 1)
}

func makeFont(name: String, fallback: NSFont, size: CGFloat) -> NSFont {
    NSFont(name: name, size: size) ?? fallback
}

func drawText(_ text: String, rect: NSRect, attributes: [NSAttributedString.Key: Any]) {
    NSAttributedString(string: text, attributes: attributes).draw(in: rect)
}

func writeOpaquePNG(_ image: NSImage, to destination: String) throws {
    var proposedRect = NSRect(origin: .zero, size: canvasSize)
    guard let sourceCGImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
        throw NSError(domain: "ScreenshotComposer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render canvas"])
    }

    let width = Int(canvasSize.width)
    let height = Int(canvasSize.height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw NSError(domain: "ScreenshotComposer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create opaque bitmap"])
    }

    context.setFillColor(ivory.cgColor)
    context.fill(CGRect(origin: .zero, size: canvasSize))
    context.draw(sourceCGImage, in: CGRect(origin: .zero, size: canvasSize))

    guard let outputCGImage = context.makeImage() else {
        throw NSError(domain: "ScreenshotComposer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode bitmap"])
    }

    let representation = NSBitmapImageRep(cgImage: outputCGImage)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ScreenshotComposer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG data"])
    }

    try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
}

let background = NSImage(contentsOfFile: backgroundPath)

for spec in specs {
    guard let screenshot = NSImage(contentsOfFile: spec.source) else {
        fputs("Missing screenshot: \(spec.source)\n", stderr)
        exit(1)
    }

    let screenshotHeight = screenshotWidth * screenshot.size.height / screenshot.size.width
    let screenshotRect = NSRect(
        x: screenshotX,
        y: screenshotBottom,
        width: screenshotWidth,
        height: screenshotHeight
    )

    let canvas = NSImage(size: canvasSize)
    canvas.lockFocus()

    ivory.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
    if let background {
        aspectFill(background, in: NSRect(origin: .zero, size: canvasSize))
    }

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.13)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()

    NSColor.white.setFill()
    NSBezierPath(roundedRect: screenshotRect, xRadius: 48, yRadius: 48).fill()

    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(roundedRect: screenshotRect, xRadius: 48, yRadius: 48).addClip()
    screenshot.draw(in: screenshotRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.current?.restoreGraphicsState()

    ink.setStroke()
    let frame = NSBezierPath(roundedRect: screenshotRect, xRadius: 48, yRadius: 48)
    frame.lineWidth = 2
    frame.stroke()

    let kickerFont = makeFont(
        name: "SFMono-Semibold",
        fallback: NSFont.monospacedSystemFont(ofSize: 27, weight: .semibold),
        size: 27
    )
    let titleFont = makeFont(
        name: "NewYork-Regular",
        fallback: NSFont(name: "Georgia", size: 66) ?? NSFont.systemFont(ofSize: 66),
        size: 66
    )
    let subtitleFont = NSFont.systemFont(ofSize: 30, weight: .regular)

    drawText(
        spec.kicker,
        rect: NSRect(x: screenshotX, y: 2584, width: screenshotWidth, height: 42),
        attributes: [
            .font: kickerFont,
            .foregroundColor: secondaryInk,
            .kern: 2.0
        ]
    )
    drawText(
        spec.title,
        rect: NSRect(x: screenshotX, y: 2468, width: screenshotWidth, height: 92),
        attributes: [
            .font: titleFont,
            .foregroundColor: ink
        ]
    )
    drawText(
        spec.subtitle,
        rect: NSRect(x: screenshotX, y: 2385, width: screenshotWidth, height: 52),
        attributes: [
            .font: subtitleFont,
            .foregroundColor: secondaryInk
        ]
    )

    canvas.unlockFocus()

    do {
        try writeOpaquePNG(canvas, to: spec.destination)
        print("Created \(spec.destination)")
    } catch {
        fputs("Failed to create \(spec.destination): \(error)\n", stderr)
        exit(1)
    }
}
