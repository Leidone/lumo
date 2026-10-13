// Renders the Lumo app icon (dark squircle + two glowing Apple-gradient rings)
// into an .iconset folder. Usage: swift make_icon.swift <output.iconset>
import AppKit
import CoreGraphics

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let cpuLoop = [0x4C7DFF, 0x5E5CE6, 0xBF5AF2, 0x8E9BFF, 0x0A84FF, 0x4C7DFF].map { color(UInt32($0)) }
let memoryLoop = [0x64D2FF, 0x0A84FF, 0x5E5CE6, 0x0A84FF, 0x64D2FF].map { color(UInt32($0)) }

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

func ring(_ ctx: CGContext, center: CGPoint, radius: CGFloat, width: CGFloat, fraction: CGFloat,
          colors: [CGColor], glow: CGColor, angle: CGFloat) {
    let path = CGMutablePath()
    path.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - fraction * 2 * .pi, clockwise: true)

    // Track
    ctx.setStrokeColor(color(0xFFFFFF, 0.08))
    ctx.setLineWidth(width)
    ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

    // Glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: width * 1.4, color: glow)
    ctx.setStrokeColor(color(0xFFFFFF, 0.35))
    ctx.setLineWidth(width * 0.8)
    ctx.setLineCap(.round)
    ctx.addPath(path)
    ctx.strokePath()
    ctx.restoreGState()

    // Gradient arc
    ctx.saveGState()
    ctx.addPath(path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1))
    ctx.clip()
    CGContextDrawConicGradient(ctx, gradient(colors), center, angle)
    ctx.restoreGState()
}

func render(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let inset = s * 0.1
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)

    // Drop shadow + dark body
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: color(0x000000, 0.45))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x060A1C))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bg = gradient([color(0x1B2A5C), color(0x0B1230)])
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    let halo = gradient([color(0x5E5CE6, 0.32), color(0x5E5CE6, 0)])
    let center = CGPoint(x: body.midX, y: body.midY)
    ctx.drawRadialGradient(halo, startCenter: center, startRadius: 0, endCenter: center, endRadius: body.width * 0.55, options: [])

    let width = body.width * 0.105
    ring(ctx, center: center, radius: body.width * 0.3, width: width, fraction: 0.78, colors: cpuLoop,
         glow: color(0x8E9BFF, 0.8), angle: 0.6)
    ring(ctx, center: center, radius: body.width * 0.3 - width * 1.35, width: width, fraction: 0.62, colors: memoryLoop,
         glow: color(0x64D2FF, 0.7), angle: -0.4)

    let dot = body.width * 0.035
    ctx.setShadow(offset: .zero, blur: dot * 3, color: color(0xFFFFFF, 0.9))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
    ctx.restoreGState()

    // Hairline edge highlight
    ctx.addPath(squircle)
    ctx.setStrokeColor(color(0xFFFFFF, 0.12))
    ctx.setLineWidth(max(1, s * 0.004))
    ctx.strokePath()
    return ctx.makeImage()!
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = NSBitmapImageRep(cgImage: render(size: base * scale))
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
print("Icon set written to \(output.path)")
