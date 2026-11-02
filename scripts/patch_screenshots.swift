import Foundation
import AppKit
import CoreGraphics
import Vision

let paperColor = CGColor(red: 0.961, green: 0.949, blue: 0.918, alpha: 1.0)
let inkColor = NSColor(calibratedWhite: 0.055, alpha: 1.0)
let secondaryInk = NSColor(calibratedWhite: 0.34, alpha: 1.0)

let kickerFont = NSFont.systemFont(ofSize: 34, weight: .regular)
let serifTitleFont = NSFont(name: "NewYork-Regular", size: 120) ?? NSFont(name: "Georgia", size: 110) ?? NSFont.systemFont(ofSize: 110)
let bodyFont = NSFont.systemFont(ofSize: 42, weight: .regular)

struct TextPatch {
    let targetSubstring: String
    let exactMatch: Bool
    let replacementText: String
    let font: NSFont
    let color: NSColor
    let kern: CGFloat
    let padding: NSEdgeInsets
}

func patchImage(filePath: String, patches: [TextPatch]) {
    guard let nsImage = NSImage(contentsOfFile: filePath),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Cannot load \(filePath)")
        return
    }
    
    let w = CGFloat(cgImage.width)
    let h = CGFloat(cgImage.height)
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
        return
    }
    
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
    
    // Perform Vision OCR to find exact locations
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try? handler.perform([request])
    
    guard let observations = request.results else { return }
    
    let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext
    
    for patch in patches {
        for obs in observations {
            guard let top = obs.topCandidates(1).first else { continue }
            let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let isMatch = patch.exactMatch
                ? text == patch.targetSubstring
                : text.lowercased().contains(patch.targetSubstring.lowercased())
            
            if isMatch {
                let b = obs.boundingBox
                let rect = CGRect(
                    x: b.minX * w - patch.padding.left,
                    y: b.minY * h - patch.padding.bottom,
                    width: b.width * w + patch.padding.left + patch.padding.right,
                    height: b.height * h + patch.padding.top + patch.padding.bottom
                )
                
                // Clear background with paper color
                ctx.setFillColor(paperColor)
                ctx.fill(rect)
                
                // Render replacement text
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: patch.font,
                    .foregroundColor: patch.color,
                    .kern: patch.kern
                ]
                let str = NSAttributedString(string: patch.replacementText, attributes: attrs)
                str.draw(at: CGPoint(x: b.minX * w, y: b.minY * h))
                print("Replaced '\(top.string)' with '\(patch.replacementText)' at \(rect)")
            }
        }
    }
    
    NSGraphicsContext.restoreGraphicsState()
    
    guard let outCG = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: outCG)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: filePath))
    print("Saved \(filePath)")
}

let dir = "assets/screenshots/original"

// 1. Screenshot 10.48.52 (Daily Overview)
patchImage(
    filePath: "\(dir)/Screenshot 2026-10-12 at 10.48.52.png",
    patches: [
        TextPatch(
            targetSubstring: "HERMES / TODAY 01",
            exactMatch: true,
            replacementText: "AGENT / TODAY 01",
            font: kickerFont,
            color: secondaryInk,
            kern: 2.0,
            padding: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 20)
        )
    ]
)

// 2. Screenshot 10.49.14 (Postbox)
patchImage(
    filePath: "\(dir)/Screenshot 2026-10-12 at 10.49.14.png",
    patches: [
        TextPatch(
            targetSubstring: "HERMES / POST 04",
            exactMatch: true,
            replacementText: "AGENT / POST 04",
            font: kickerFont,
            color: secondaryInk,
            kern: 2.0,
            padding: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 20)
        ),
        TextPatch(
            targetSubstring: "Hermes",
            exactMatch: true,
            replacementText: "Agent",
            font: serifTitleFont,
            color: inkColor,
            kern: 0.0,
            padding: NSEdgeInsets(top: 15, left: 10, bottom: 15, right: 30)
        ),
        TextPatch(
            targetSubstring: "Hermes agent via iCloud.",
            exactMatch: true,
            replacementText: "personal agent via iCloud.",
            font: bodyFont,
            color: secondaryInk,
            kern: 0.0,
            padding: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 20)
        )
    ]
)

// 3. Screenshot 10.49.46 (Health)
patchImage(
    filePath: "\(dir)/Screenshot 2026-10-12 at 10.49.46.png",
    patches: [
        TextPatch(
            targetSubstring: "HERMES / HEALTH 02",
            exactMatch: true,
            replacementText: "AGENT / HEALTH 02",
            font: kickerFont,
            color: secondaryInk,
            kern: 2.0,
            padding: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 20)
        )
    ]
)

// 4. Screenshot 10.50.03 (Places)
patchImage(
    filePath: "\(dir)/Screenshot 2026-10-12 at 10.50.03.png",
    patches: [
        TextPatch(
            targetSubstring: "HERMES / PLACES 03",
            exactMatch: true,
            replacementText: "AGENT / PLACES 03",
            font: kickerFont,
            color: secondaryInk,
            kern: 2.0,
            padding: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 20)
        ),
        TextPatch(
            targetSubstring: "perimeters recognized by your Hermes",
            exactMatch: false,
            replacementText: "perimeters recognized by your personal agent.",
            font: bodyFont,
            color: secondaryInk,
            kern: 0.0,
            padding: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 20)
        )
    ]
)
