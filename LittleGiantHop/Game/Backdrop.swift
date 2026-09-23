import SpriteKit

/// Night-city parallax: sky, retro sun, stars, two skyline layers and a
/// perspective neon floor whose grid lines slide with the camera.
final class Backdrop: SKNode {
    struct Theme {
        let top: UIColor
        let horizon: UIColor
        let grid: UIColor
    }

    static let themes: [Theme] = [
        Theme(top: UIColor(hex: 0x060709), horizon: UIColor(hex: 0x1C2113), grid: Palette.lime),
        Theme(top: UIColor(hex: 0x0B0710), horizon: UIColor(hex: 0x43190E), grid: Palette.orange),
        Theme(top: UIColor(hex: 0x03100D), horizon: UIColor(hex: 0x0F3B2A), grid: UIColor(hex: 0x6CF5C2)),
        Theme(top: UIColor(hex: 0x0A0716), horizon: UIColor(hex: 0x33174D), grid: UIColor(hex: 0xC99BFF)),
    ]

    let size: CGSize
    let groundY: CGFloat
    private var skies: [SKSpriteNode] = []
    private(set) var themeIndex = 0
    private let sun = SKNode()
    private var farTiles: [SKSpriteNode] = []
    private var nearTiles: [SKSpriteNode] = []
    private let grid = SKShapeNode()
    private let horizonLine = SKSpriteNode()
    private let floorGlow = SKSpriteNode(texture: Art.softDot)
    private var stars: [SKSpriteNode] = []

    init(size: CGSize, theme: Int = 0) {
        self.size = size
        groundY = (size.height * 0.13).rounded()
        themeIndex = theme % Backdrop.themes.count
        super.init()
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let W = size.width, H = size.height

        for (i, theme) in Backdrop.themes.enumerated() {
            let sky = SKSpriteNode(texture: Backdrop.skyTexture(size: size, theme: theme))
            sky.anchorPoint = .zero
            sky.size = size
            sky.zPosition = -100
            sky.alpha = i == themeIndex ? 1 : 0
            addChild(sky)
            skies.append(sky)
        }

        for _ in 0..<80 {
            let s = SKSpriteNode(texture: Art.softDot)
            let r = CGFloat.random(1.5, 4.5)
            s.size = CGSize(width: r, height: r)
            s.position = CGPoint(x: .random(0, W), y: .random(groundY + H * 0.2, H))
            s.alpha = .random(0.25, 0.9)
            s.zPosition = -95
            s.blendMode = .add
            let a = s.alpha
            s.run(.repeatForever(.sequence([
                .wait(forDuration: .random(in: 0...3)),
                .fadeAlpha(to: a * 0.2, duration: .random(in: 0.4...1.2)),
                .fadeAlpha(to: a, duration: .random(in: 0.4...1.2)),
            ])))
            addChild(s)
            stars.append(s)
        }

        let sunR = min(W * 0.34, H * 0.26)
        let sunSprite = SKSpriteNode(texture: Backdrop.sunTexture(radius: sunR))
        sunSprite.size = CGSize(width: sunR * 2.8, height: sunR * 2.8)
        sun.addChild(sunSprite)
        sun.position = CGPoint(x: W * 0.62, y: groundY + sunR * 0.72)
        sun.zPosition = -90
        addChild(sun)
        sunSprite.run(.repeatForever(.sequence([
            .scale(to: 1.02, duration: 2.4), .scale(to: 1, duration: 2.4),
        ])))

        let tileW = max(W, H * 0.6) * 1.2
        for i in 0..<2 {
            let far = SKSpriteNode(texture: Backdrop.skylineTexture(
                size: CGSize(width: tileW, height: H * 0.3), seed: 11, color: UIColor(hex: 0x14171C),
                windows: 0.05, minH: 0.2, maxH: 0.75, widths: (0.04, 0.09)))
            far.anchorPoint = .zero
            far.position = CGPoint(x: CGFloat(i) * tileW, y: groundY - 1)
            far.zPosition = -80
            addChild(far)
            farTiles.append(far)

            let near = SKSpriteNode(texture: Backdrop.skylineTexture(
                size: CGSize(width: tileW, height: H * 0.2), seed: 29, color: UIColor(hex: 0x0A0B0E),
                windows: 0.16, minH: 0.2, maxH: 0.8, widths: (0.06, 0.13)))
            near.anchorPoint = .zero
            near.position = CGPoint(x: CGFloat(i) * tileW, y: groundY - 1)
            near.zPosition = -70
            addChild(near)
            nearTiles.append(near)
        }

        let floor = SKSpriteNode(texture: Backdrop.floorTexture(size: CGSize(width: W, height: groundY)))
        floor.anchorPoint = .zero
        floor.size = CGSize(width: W, height: groundY)
        floor.zPosition = -60
        addChild(floor)

        grid.zPosition = -59
        grid.lineWidth = 1.2
        grid.glowWidth = 0
        grid.alpha = 0.55
        grid.isAntialiased = true
        addChild(grid)

        horizonLine.texture = Art.softDot
        horizonLine.size = CGSize(width: W * 1.4, height: 10)
        horizonLine.position = CGPoint(x: W / 2, y: groundY)
        horizonLine.zPosition = -58
        horizonLine.blendMode = .add
        addChild(horizonLine)

        let edge = SKSpriteNode(color: .white, size: CGSize(width: W, height: 2))
        edge.anchorPoint = CGPoint(x: 0, y: 0.5)
        edge.position = CGPoint(x: 0, y: groundY)
        edge.zPosition = -57
        edge.name = "edge"
        addChild(edge)

        floorGlow.size = CGSize(width: W * 1.6, height: H * 0.22)
        floorGlow.position = CGPoint(x: W / 2, y: groundY)
        floorGlow.alpha = 0.16
        floorGlow.zPosition = -75
        floorGlow.blendMode = .add
        addChild(floorGlow)

        applyGridColor(Backdrop.themes[themeIndex].grid)
    }

    private func applyGridColor(_ c: UIColor) {
        grid.strokeColor = c
        horizonLine.color = c
        horizonLine.colorBlendFactor = 1
        floorGlow.color = c
        floorGlow.colorBlendFactor = 1
        (childNode(withName: "edge") as? SKSpriteNode)?.color = c
    }

    func setTheme(_ index: Int) {
        let next = index % Backdrop.themes.count
        guard next != themeIndex else { return }
        let old = skies[themeIndex]
        let new = skies[next]
        new.zPosition = -99
        old.zPosition = -100
        new.run(.fadeIn(withDuration: 1.2)) { old.alpha = 0 }
        themeIndex = next
        let target = Backdrop.themes[next].grid
        let from = grid.strokeColor
        run(.customAction(withDuration: 1.2) { [weak self] _, t in
            self?.applyGridColor(from.mixed(with: target, t / 1.2))
        })
    }

    /// `distance` is how far the world has scrolled, in points.
    func update(distance: CGFloat, time: TimeInterval) {
        scroll(farTiles, by: distance * 0.12)
        scroll(nearTiles, by: distance * 0.3)
        drawGrid(distance: distance)
    }

    private func scroll(_ tiles: [SKSpriteNode], by offset: CGFloat) {
        guard let w = tiles.first?.size.width else { return }
        let o = offset.truncatingRemainder(dividingBy: w)
        for (i, t) in tiles.enumerated() { t.position.x = CGFloat(i) * w - o }
    }

    private func drawGrid(distance: CGFloat) {
        let W = size.width
        let path = CGMutablePath()
        let top = groundY - 1, bottom: CGFloat = 0
        // Receding lines: the near end moves at full speed, the far end slower.
        let spacing = size.height * 0.09
        let farScale: CGFloat = 0.35
        let cx = W / 2
        let shift = distance.truncatingRemainder(dividingBy: spacing)
        let count = Int(W / (spacing * farScale)) / 2 + 3
        for i in -count...count {
            let wx = CGFloat(i) * spacing - shift
            let xNear = cx + wx
            let xFar = cx + wx * farScale
            path.move(to: CGPoint(x: xFar, y: top))
            path.addLine(to: CGPoint(x: xNear * 1.0 + (xNear - cx) * 0.9, y: bottom))
        }
        // Horizontal rungs, bunched toward the horizon.
        for k in 1...6 {
            let t = CGFloat(k) / 6
            let y = top - (top - bottom) * t * t
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: W, y: y))
        }
        grid.path = path
    }

    // MARK: textures

    static func skyTexture(size: CGSize, theme: Theme) -> SKTexture {
        Art.texture(size: CGSize(width: 8, height: 256), scale: 1) { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                theme.top.cgColor, theme.top.mixed(with: theme.horizon, 0.35).cgColor, theme.horizon.cgColor,
            ] as CFArray, locations: [0, 0.5, 0.88])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [.drawsAfterEndLocation])
        }
    }

    static func sunTexture(radius r: CGFloat) -> SKTexture {
        let side = r * 2.8
        return Art.texture(size: CGSize(width: side, height: side)) { ctx in
            let c = CGPoint(x: side / 2, y: side / 2)
            let space = CGColorSpaceCreateDeviceRGB()
            let halo = CGGradient(colorsSpace: space, colors: [
                Palette.orange.withAlphaComponent(0.35).cgColor, Palette.orange.withAlphaComponent(0).cgColor,
            ] as CFArray, locations: [0.5, 1])!
            ctx.drawRadialGradient(halo, startCenter: c, startRadius: 0, endCenter: c, endRadius: side / 2, options: [])

            ctx.saveGState()
            let disc = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.addEllipse(in: disc)
            // Synthwave slits: bands of increasing height toward the bottom.
            var y = c.y + r * 0.1
            var gap = r * 0.035
            while y < c.y + r {
                ctx.addRect(CGRect(x: c.x - r, y: y, width: r * 2, height: gap))
                y += gap + r * 0.11
                gap *= 1.35
            }
            ctx.clip(using: .evenOdd)
            let body = CGGradient(colorsSpace: space, colors: [
                Palette.lime.cgColor, UIColor(hex: 0xFFC94A).cgColor, Palette.orange.cgColor, Palette.ember.cgColor,
            ] as CFArray, locations: [0, 0.4, 0.72, 1])!
            ctx.drawLinearGradient(body, start: CGPoint(x: c.x, y: c.y - r), end: CGPoint(x: c.x, y: c.y + r), options: [])
            ctx.restoreGState()
        }
    }

    static func skylineTexture(size: CGSize, seed: UInt64, color: UIColor, windows: CGFloat,
                               minH: CGFloat, maxH: CGFloat, widths: (CGFloat, CGFloat)) -> SKTexture {
        var rng = SeededRandom(seed: seed)
        return Art.texture(size: size) { ctx in
            var x: CGFloat = 0
            let W = size.width, H = size.height
            let unit = H
            var blocks: [CGRect] = []
            while x < W {
                let w = unit * rng.next(widths.0, widths.1)
                let h = H * rng.next(minH, maxH)
                // Seam-safe: last building is clipped so tiles repeat cleanly.
                blocks.append(CGRect(x: x, y: H - h, width: min(w, W - x), height: h))
                x += w + unit * rng.next(0, 0.012)
            }
            for b in blocks {
                ctx.setFillColor(color.cgColor)
                ctx.fill(b)
                if rng.next(0, 1) < 0.35 {
                    ctx.fill(CGRect(x: b.midX - 1, y: b.minY - unit * 0.08, width: 2, height: unit * 0.08))
                    ctx.setFillColor(Palette.orange.withAlphaComponent(0.9).cgColor)
                    ctx.fillEllipse(in: CGRect(x: b.midX - 2, y: b.minY - unit * 0.08 - 2, width: 4, height: 4))
                }
                let cell = max(4, unit * 0.028)
                var wy = b.minY + cell
                while wy < b.maxY - cell {
                    var wx = b.minX + cell * 0.8
                    while wx < b.maxX - cell {
                        if rng.next(0, 1) < windows {
                            let lit = rng.next(0, 1) < 0.7 ? Palette.lime : Palette.orange
                            ctx.setFillColor(lit.withAlphaComponent(rng.next(0.25, 0.7)).cgColor)
                            ctx.fill(CGRect(x: wx, y: wy, width: cell * 0.55, height: cell * 0.65))
                        }
                        wx += cell
                    }
                    wy += cell * 1.2
                }
            }
        }
    }

    static func floorTexture(size: CGSize) -> SKTexture {
        Art.texture(size: CGSize(width: 8, height: max(8, size.height)), scale: 1) { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor(hex: 0x111410).cgColor, UIColor(hex: 0x050506).cgColor,
            ] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }
}

/// Deterministic generator so the skyline looks the same every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return lo + (hi - lo) * CGFloat(state % 1_000_000) / 1_000_000
    }
}
