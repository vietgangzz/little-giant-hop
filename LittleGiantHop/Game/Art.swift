import SpriteKit
import UIKit

enum Palette {
    static let ink = UIColor(hex: 0x0A0A0A)
    static let night = UIColor(hex: 0x0E1013)
    static let lime = UIColor(hex: 0xD5F64B)
    static let limeDeep = UIColor(hex: 0x9FBF1E)
    static let orange = UIColor(hex: 0xFF7447)
    static let ember = UIColor(hex: 0xD15422)
    static let paper = UIColor(hex: 0xFAFAFA)
    static let mute = UIColor(hex: 0xA1A1AA)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        var (r1, g1, b1, a1) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var (r2, g2, b2, a2) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

/// Minimal SVG path parser (M/L/H/V/Q/C/Z, absolute and relative). The brand
/// vectors only use M, L, Q and Z, so the mascot is drawn from the exact
/// approved geometry rather than a traced bitmap.
struct SVGPath {
    let cgPath: CGPath
    let points: [CGPoint]

    init(_ d: String) {
        let path = CGMutablePath()
        var pts: [CGPoint] = []
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == "," || ch == " " {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch == "-" && !current.isEmpty && !current.hasSuffix("e") {
                tokens.append(current); current = "-"
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var i = 0
        var cmd: Character = "M"
        var pos = CGPoint.zero
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func pt(_ rel: Bool) -> CGPoint {
            let x = num(), y = num()
            return rel ? CGPoint(x: pos.x + x, y: pos.y + y) : CGPoint(x: x, y: y)
        }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = c; i += 1 }
            let rel = cmd.isLowercase
            switch cmd.uppercased().first! {
            case "M":
                pos = pt(rel); path.move(to: pos); pts.append(pos)
                cmd = rel ? "l" : "L"
            case "L":
                pos = pt(rel); path.addLine(to: pos); pts.append(pos)
            case "H":
                let x = num(); pos = CGPoint(x: rel ? pos.x + x : x, y: pos.y)
                path.addLine(to: pos); pts.append(pos)
            case "V":
                let y = num(); pos = CGPoint(x: pos.x, y: rel ? pos.y + y : y)
                path.addLine(to: pos); pts.append(pos)
            case "Q":
                let c = pt(rel); let p = pt(rel)
                path.addQuadCurve(to: p, control: c); pos = p; pts.append(p)
            case "C":
                let c1 = pt(rel); let c2 = pt(rel); let p = pt(rel)
                path.addCurve(to: p, control1: c1, control2: c2); pos = p; pts.append(p)
            case "Z":
                path.closeSubpath()
            default:
                i += 1
            }
        }
        cgPath = path
        self.points = pts
    }
}

enum Art {
    /// Renders with a CoreGraphics closure into a texture. `size` is in points;
    /// `scale` pixels per point.
    static func texture(size: CGSize, scale: CGFloat = UIScreen.main.scale,
                        _ draw: (CGContext) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(ctx.cgContext)
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }

    static let softDot: SKTexture = texture(size: CGSize(width: 32, height: 32), scale: 2) { ctx in
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                               endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
    }

    static let hardDot: SKTexture = texture(size: CGSize(width: 16, height: 16), scale: 2) { ctx in
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: 1, y: 1, width: 14, height: 14))
    }

    static let confettiBit: SKTexture = texture(size: CGSize(width: 10, height: 16), scale: 2) { ctx in
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.addPath(UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 10, height: 16),
                                 cornerRadius: 2).cgPath)
        ctx.fillPath()
    }

    static let spark: SKTexture = texture(size: CGSize(width: 64, height: 64), scale: 2) { ctx in
        // Four-point twinkle star.
        let c = CGPoint(x: 32, y: 32)
        let p = CGMutablePath()
        for k in 0..<8 {
            let a = CGFloat(k) * .pi / 4 - .pi / 2
            let r: CGFloat = k % 2 == 0 ? 30 : 8
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            k == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        ctx.setShadow(offset: .zero, blur: 6, color: UIColor.white.cgColor)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.addPath(p)
        ctx.fillPath()
    }
}

extension CGFloat {
    static func random(_ a: CGFloat, _ b: CGFloat) -> CGFloat { .random(in: Swift.min(a, b)...Swift.max(a, b)) }
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(hi, Swift.max(lo, self)) }
}
