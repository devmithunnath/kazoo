// Renders Kazoo's app icon: a matte-black macOS squircle with the camera notch at the top
// and a grid of mint squares filling from the bottom — the same visual language as the notch panel.
// Usage: swift Scripts/make_icon.swift <AppIcon.appiconset dir>
import AppKit
import CoreGraphics

let mint = CGColor(red: 0.62, green: 0.96, blue: 0.55, alpha: 1)
let mintDeep = CGColor(red: 0.47, green: 0.88, blue: 0.40, alpha: 1)
let dim = CGColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 1)

func render(pixels: Int) -> CGImage {
    let s = CGFloat(pixels) / 1024
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1) // y down, like design tools
    let small = pixels <= 32

    // Body: Big Sur-style rounded square on a 1024 canvas (824 pt body, 100 pt margin) with a soft shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [CGColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1),
                                       CGColor(red: 0.06, green: 0.06, blue: 0.065, alpha: 1)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

    // Camera notch: pure black tab hanging from the top edge with concave shoulders.
    let notchW: CGFloat = small ? 380 : 330
    let notchH: CGFloat = small ? 150 : 118
    let fillet: CGFloat = 34
    let r: CGFloat = small ? 60 : 50
    let x0 = 512 - notchW / 2, x1 = 512 + notchW / 2, top: CGFloat = 100
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: x0 - fillet, y: top))
    notch.addQuadCurve(to: CGPoint(x: x0, y: top + fillet), control: CGPoint(x: x0, y: top))
    notch.addLine(to: CGPoint(x: x0, y: top + notchH - r))
    notch.addQuadCurve(to: CGPoint(x: x0 + r, y: top + notchH), control: CGPoint(x: x0, y: top + notchH))
    notch.addLine(to: CGPoint(x: x1 - r, y: top + notchH))
    notch.addQuadCurve(to: CGPoint(x: x1, y: top + notchH - r), control: CGPoint(x: x1, y: top + notchH))
    notch.addLine(to: CGPoint(x: x1, y: top + fillet))
    notch.addQuadCurve(to: CGPoint(x: x1 + fillet, y: top), control: CGPoint(x: x1, y: top))
    notch.closeSubpath()
    ctx.addPath(notch)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    if !small {
        // Camera lens.
        let lens = CGRect(x: 512 - 22, y: top + notchH / 2 - 18, width: 44, height: 44)
        ctx.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1))
        ctx.fillEllipse(in: lens)
        ctx.setFillColor(CGColor(red: 0.22, green: 0.26, blue: 0.36, alpha: 1))
        ctx.fillEllipse(in: lens.insetBy(dx: 12, dy: 12))
    }

    // Square grid, lit from the bottom-left (the panel's fraction gauge).
    let cols = small ? 3 : 5
    let rows = small ? 3 : 4
    let lit = small ? 5 : 13
    let gridW: CGFloat = small ? 560 : 600
    let gap: CGFloat = small ? 50 : 34
    let cell = (gridW - gap * CGFloat(cols - 1)) / CGFloat(cols)
    let gridH = cell * CGFloat(rows) + gap * CGFloat(rows - 1)
    let gx = 512 - gridW / 2
    let gy: CGFloat = small ? 290 : 312 + (520 - gridH) / 2
    for row in 0..<rows {
        for col in 0..<cols {
            let indexFromBottom = (rows - 1 - row) * cols + col
            let rect = CGRect(x: gx + CGFloat(col) * (cell + gap), y: gy + CGFloat(row) * (cell + gap),
                              width: cell, height: cell)
            let path = CGPath(roundedRect: rect, cornerWidth: cell * 0.28, cornerHeight: cell * 0.28, transform: nil)
            if indexFromBottom < lit {
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                   colors: [mint, mintDeep] as CFArray, locations: [0, 1])!
                ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY),
                                       end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
                ctx.restoreGState()
            } else {
                ctx.addPath(path)
                ctx.setFillColor(dim)
                ctx.fillPath()
            }
        }
    }
    ctx.restoreGState()

    // Hairline edge highlight.
    if !small {
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
        ctx.setLineWidth(3)
        ctx.strokePath()
    }
    return ctx.makeImage()!
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let rep = NSBitmapImageRep(cgImage: render(pixels: px))
        try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons to \(outDir.path)")
