import SpriteKit

/// A pair of neon towers with a gap the mascot has to thread.
final class PillarPair: SKNode {
    let width: CGFloat
    let capHeight: CGFloat
    var gap: CGFloat
    var baseCenter: CGFloat
    var gapCenter: CGFloat
    var passed = false
    /// Vertical drift for later levels: amplitude (pts), angular speed, phase.
    var drift: (amp: CGFloat, speed: CGFloat, phase: CGFloat) = (0, 0, 0)

    private let top: SKSpriteNode
    private let bottom: SKSpriteNode
    private let topCap: SKSpriteNode
    private let bottomCap: SKSpriteNode

    init(art: PillarArt, gap: CGFloat, center: CGFloat) {
        width = art.width
        capHeight = art.capSize.height
        self.gap = gap
        baseCenter = center
        gapCenter = center
        top = SKSpriteNode(texture: art.body)
        bottom = SKSpriteNode(texture: art.body)
        topCap = SKSpriteNode(texture: art.cap)
        bottomCap = SKSpriteNode(texture: art.cap)
        super.init()
        for s in [top, bottom] {
            s.size = art.bodySize
            addChild(s)
        }
        top.anchorPoint = CGPoint(x: 0.5, y: 0)
        bottom.anchorPoint = CGPoint(x: 0.5, y: 1)
        top.yScale = -1  // mirror so the window pattern reads from the gap outward
        top.anchorPoint = CGPoint(x: 0.5, y: 1)
        for c in [topCap, bottomCap] {
            c.size = art.capSize
            c.zPosition = 1
            addChild(c)
        }
        layout()
    }

    required init?(coder: NSCoder) { fatalError() }

    var gapTop: CGFloat { gapCenter + gap / 2 }
    var gapBottom: CGFloat { gapCenter - gap / 2 }

    func layout() {
        top.position = CGPoint(x: 0, y: gapTop)
        bottom.position = CGPoint(x: 0, y: gapBottom)
        topCap.position = CGPoint(x: 0, y: gapTop + capHeight / 2)
        bottomCap.position = CGPoint(x: 0, y: gapBottom - capHeight / 2)
    }

    func update(time: TimeInterval, lo: CGFloat, hi: CGFloat) {
        guard drift.amp > 0 else { return }
        gapCenter = (baseCenter + drift.amp * sin(CGFloat(time) * drift.speed + drift.phase)).clamped(lo, hi)
        layout()
    }

    /// Circle-vs-rects test against both towers and their caps.
    func hits(center c: CGPoint, radius r: CGFloat) -> Bool {
        let x = position.x
        let capW = width * 1.14
        let rects = [
            CGRect(x: x - width / 2, y: gapTop, width: width, height: 10_000),
            CGRect(x: x - width / 2, y: gapBottom - 10_000, width: width, height: 10_000),
            CGRect(x: x - capW / 2, y: gapTop, width: capW, height: capHeight),
            CGRect(x: x - capW / 2, y: gapBottom - capHeight, width: capW, height: capHeight),
        ]
        return rects.contains { rect in
            let px = c.x.clamped(rect.minX, rect.maxX)
            let py = c.y.clamped(rect.minY, rect.maxY)
            return hypot(c.x - px, c.y - py) < r
        }
    }

    /// Little bounce when the mascot clears it.
    func celebrate() {
        for cap in [topCap, bottomCap] {
            cap.run(.sequence([
                .group([.scaleX(to: 1.12, duration: 0.07), .colorize(with: .white, colorBlendFactor: 0.6, duration: 0.07)]),
                .group([.scaleX(to: 1, duration: 0.25), .colorize(withColorBlendFactor: 0, duration: 0.25)]),
            ]))
        }
    }
}

/// Textures shared by every pillar at the current screen size.
struct PillarArt {
    let width: CGFloat
    let bodySize: CGSize
    let capSize: CGSize
    let body: SKTexture
    let cap: SKTexture

    init(sceneHeight H: CGFloat) {
        width = (H * 0.1).rounded()
        let pad: CGFloat = 10  // room for the neon glow
        bodySize = CGSize(width: width + pad * 2, height: H)
        capSize = CGSize(width: (width * 1.14).rounded() + pad * 2, height: (H * 0.042).rounded() + pad * 2)
        let w = width
        let bs = bodySize
        body = Art.texture(size: bs) { ctx in
            let rect = CGRect(x: pad, y: 0, width: w, height: bs.height)
            let space = CGColorSpaceCreateDeviceRGB()
            ctx.saveGState()
            ctx.addRect(rect)
            ctx.clip()
            let g = CGGradient(colorsSpace: space, colors: [
                UIColor(hex: 0x1D2127).cgColor, UIColor(hex: 0x14171B).cgColor, UIColor(hex: 0x0D0F12).cgColor,
            ] as CFArray, locations: [0, 0.55, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
            // Window grid, lit windows cluster near the cap.
            var rng = SeededRandom(seed: 5)
            let cols = 3
            let cw = w / CGFloat(cols + 1)
            var y: CGFloat = w * 0.25
            var row = 0
            while y < bs.height {
                for c in 0..<cols {
                    let x = rect.minX + cw * (CGFloat(c) + 0.5) + cw * 0.1
                    let nearCap = max(0, 1 - CGFloat(row) / 14)
                    let lit = rng.next(0, 1) < 0.1 + nearCap * 0.35
                    let color: UIColor = lit
                        ? (rng.next(0, 1) < 0.8 ? Palette.lime : Palette.orange).withAlphaComponent(rng.next(0.45, 0.9))
                        : UIColor(hex: 0x262B33)
                    ctx.setFillColor(color.cgColor)
                    ctx.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: cw * 0.8, height: cw * 0.95),
                                             cornerRadius: 2).cgPath)
                    ctx.fillPath()
                }
                y += cw * 1.5
                row += 1
            }
            // Bevel highlight on the left face.
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.06).cgColor)
            ctx.fill(CGRect(x: rect.minX, y: 0, width: w * 0.12, height: bs.height))
            ctx.restoreGState()
            // Neon trims with glow.
            ctx.setShadow(offset: .zero, blur: 8, color: Palette.lime.withAlphaComponent(0.9).cgColor)
            ctx.setFillColor(Palette.lime.cgColor)
            ctx.fill(CGRect(x: rect.minX, y: 0, width: 2, height: bs.height))
            ctx.fill(CGRect(x: rect.maxX - 2, y: 0, width: 2, height: bs.height))
        }

        let cs = capSize
        cap = Art.texture(size: cs) { ctx in
            let rect = CGRect(x: pad, y: pad, width: cs.width - pad * 2, height: cs.height - pad * 2)
            let shape = UIBezierPath(roundedRect: rect, cornerRadius: rect.height * 0.28).cgPath
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 10, color: Palette.orange.withAlphaComponent(0.85).cgColor)
            ctx.addPath(shape)
            ctx.setFillColor(Palette.orange.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            // Hazard stripes.
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.setFillColor(Palette.ink.withAlphaComponent(0.85).cgColor)
            let stripe = rect.height * 0.9
            var x = rect.minX - rect.height
            while x < rect.maxX + rect.height {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x, y: rect.maxY))
                p.addLine(to: CGPoint(x: x + stripe * 0.5, y: rect.maxY))
                p.addLine(to: CGPoint(x: x + stripe * 0.5 + rect.height, y: rect.minY))
                p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                p.closeSubpath()
                ctx.addPath(p)
                ctx.fillPath()
                x += stripe * 1.2
            }
            let shine = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor.white.withAlphaComponent(0.35).cgColor, UIColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray, locations: [0, 0.6])!
            ctx.drawLinearGradient(shine, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
            ctx.restoreGState()
            ctx.addPath(shape)
            ctx.setStrokeColor(Palette.ink.cgColor)
            ctx.setLineWidth(2)
            ctx.strokePath()
        }
    }
}

/// Orange "ray spark" pickup between towers.
final class Spark: SKNode {
    let radius: CGFloat
    var collected = false

    init(size: CGFloat) {
        radius = size * 0.5
        super.init()
        let glow = SKSpriteNode(texture: Art.softDot)
        glow.size = CGSize(width: size * 2.6, height: size * 2.6)
        glow.color = Palette.orange
        glow.colorBlendFactor = 1
        glow.alpha = 0.55
        glow.blendMode = .add
        addChild(glow)

        let star = SKSpriteNode(texture: Art.spark)
        star.size = CGSize(width: size * 1.25, height: size * 1.25)
        star.color = Palette.orange
        star.colorBlendFactor = 0.55
        addChild(star)
        star.run(.repeatForever(.rotate(byAngle: .pi, duration: 2)))
        run(.repeatForever(.sequence([
            .scale(to: 1.15, duration: 0.45), .scale(to: 0.95, duration: 0.45),
        ])))
        let bob = SKAction.sequence([.moveBy(x: 0, y: size * 0.18, duration: 0.6),
                                     .moveBy(x: 0, y: -size * 0.18, duration: 0.6)])
        bob.timingMode = .easeInEaseOut
        star.run(.repeatForever(bob))
    }

    required init?(coder: NSCoder) { fatalError() }
}
