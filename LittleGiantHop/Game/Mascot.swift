import SpriteKit

/// The VGANG Little Giant, built from the approved brand vectors
/// (landing-v2 `mascotArtwork.ts`). Everything lives in SVG units with the
/// y axis flipped; the root node is scaled to the requested on-screen height.
final class Mascot: SKNode {
    static let body = "M706 313.5L705 268L711 268.5Q717 269 729.5 272.5Q742 276 757 284Q772 292 784.5 304Q797 316 804.5 329Q812 342 816.5 360.5Q821 379 821 410Q821 441 823.5 455.5Q826 470 831.5 483Q837 496 848 512Q859 528 862.5 535.5Q866 543 867.5 549Q869 555 869 568Q869 581 865.5 591Q862 601 855 611Q848 621 841.5 627Q835 633 827.5 638Q820 643 800.5 651Q781 659 754 665.5Q727 672 691 676.5Q655 681 620 681.5Q585 682 562.5 679.5Q540 677 527 674Q514 671 506.5 668Q499 665 494 663.5Q489 662 478.5 656.5Q468 651 461.5 646.5Q455 642 446.5 634Q438 626 430 614.5Q422 603 416 587.5Q410 572 408 560Q406 548 406 531.5Q406 515 407 507.5Q408 500 413.5 480Q419 460 426.5 443.5Q434 427 443 412.5Q452 398 461.5 386Q471 374 482 362.5Q493 351 506.5 339.5Q520 328 534.5 318Q549 308 565.5 299Q582 290 594 285Q606 280 621.5 275.5Q637 271 639 271.5Q641 272 653 287.5Q665 303 682 328.5Q699 354 701.5 356.5Q704 359 705.5 359L707 359L706 313.5Z"
    static let eyes = [
        "M557.5 419.5L559 415.5L562 416Q565 416.5 614 448L663 479.5L662 486Q661 492.5 656.5 501Q652 509.5 649 512Q646 514.5 643.5 517.5Q641 520.5 635.5 523.5Q630 526.5 623 527.5Q616 528.5 606.5 525.5Q597 522.5 588.5 515Q580 507.5 573 496Q566 484.5 562.5 474.5Q559 464.5 557.5 456.5Q556 448.5 556 436Q556 423.5 557.5 419.5Z",
        "M755.5 455.5L783 433L785 434L787 435L787.5 437Q788 439 789 453.5Q790 468 788.5 476Q787 484 784.5 490.5Q782 497 776.5 504Q771 511 767 513Q763 515 757 515Q751 515 747.5 513.5Q744 512 743 510.5Q742 509 739 506.5Q736 504 733.5 499.5Q731 495 729.5 490.5Q728 486 728 482L728 478L755.5 455.5Z",
    ]
    static let rays = [
        "M872 211Q875 209 879.5 210Q884 211 896.5 219.5Q909 228 911.5 230.5Q914 233 914 236.5Q914 240 888.5 267.5Q863 295 859.5 299Q856 303 853 303.5Q850 304 843 299Q836 294 834.5 291L833 288L851 250.5Q869 213 872 211Z",
        "M922 290Q941 280 944.5 281Q948 282 949.5 284Q951 286 957 302Q963 318 962.5 321.5L962 325L957.5 327.5Q953 330 920 338Q887 346 882 347L877 348L874.5 346Q872 344 869.5 337Q867 330 867.5 326L868 322L885.5 311Q903 300 922 290Z",
        "M877.5 374L880 372L912 377.5L944 383L945 387Q946 391 942.5 403.5Q939 416 937.5 417.5Q936 419 931 419Q926 419 900 408Q874 397 872.5 393.5Q871 390 873 383Q875 376 877.5 374Z",
    ]

    /// Centre of the body in SVG space; becomes the node origin.
    static let origin = CGPoint(x: 637, y: 476)
    static let bodyHeight: CGFloat = 414

    private static let cache = TextureCache()

    let squash = SKNode()
    private let glow: SKSpriteNode
    private let bodySprite: SKSpriteNode
    private let eyeNodes: [SKSpriteNode]
    private let deadEyes = SKNode()
    private var rayNodes: [SKNode] = []
    private(set) var isDead = false

    init(height: CGFloat, glowing: Bool = true) {
        let tex = Mascot.cache.textures
        glow = SKSpriteNode(texture: tex.glow.texture)
        glow.size = tex.glow.size
        glow.position = tex.glow.center
        glow.alpha = glowing ? 0.55 : 0
        glow.blendMode = .add

        bodySprite = SKSpriteNode(texture: tex.body.texture)
        bodySprite.size = tex.body.size
        bodySprite.position = tex.body.center

        eyeNodes = tex.eyes.map { e in
            let s = SKSpriteNode(texture: e.texture)
            s.size = e.size
            s.position = e.center
            return s
        }
        super.init()

        addChild(squash)
        squash.addChild(glow)
        for (i, ray) in tex.rays.enumerated() {
            let pivot = SKNode()
            pivot.position = tex.rayPivots[i]
            let s = SKSpriteNode(texture: ray.texture)
            s.size = ray.size
            s.position = CGPoint(x: ray.center.x - pivot.position.x, y: ray.center.y - pivot.position.y)
            pivot.addChild(s)
            squash.addChild(pivot)
            rayNodes.append(pivot)
        }
        squash.addChild(bodySprite)
        eyeNodes.forEach(squash.addChild)

        for e in tex.eyes {
            let x = SKShapeNode(path: Mascot.crossPath(size: 64))
            x.strokeColor = Palette.ink
            x.lineWidth = 17
            x.lineCap = .round
            x.position = e.center
            deadEyes.addChild(x)
        }
        deadEyes.isHidden = true
        squash.addChild(deadEyes)

        setScale(height / Mascot.bodyHeight)
        startBlinking()
        startRayIdle()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Squash-and-stretch hop with the brand rays flaring outward.
    func hop() {
        squash.removeAction(forKey: "squash")
        let stretch = SKAction.group([.scaleX(to: 0.8, duration: 0.05), .scaleY(to: 1.22, duration: 0.05)])
        let settle = SKAction.group([.scaleX(to: 1, duration: 0.28), .scaleY(to: 1, duration: 0.28)])
        settle.timingFunction = { t in Mascot.springEase(t) }
        squash.run(.sequence([stretch, settle]), withKey: "squash")

        for (i, ray) in rayNodes.enumerated() {
            ray.removeAction(forKey: "flare")
            let out = SKAction.group([.scale(to: 1.45, duration: 0.06),
                                      .rotate(toAngle: -0.12 * CGFloat(i - 1), duration: 0.06)])
            let back = SKAction.group([.scale(to: 1, duration: 0.3), .rotate(toAngle: 0, duration: 0.3)])
            back.timingMode = .easeOut
            ray.run(.sequence([.wait(forDuration: Double(i) * 0.02), out, back]), withKey: "flare")
        }
        glow.removeAction(forKey: "pulse")
        glow.run(.sequence([.fadeAlpha(to: 1, duration: 0.05), .fadeAlpha(to: 0.55, duration: 0.35)]),
                 withKey: "pulse")
    }

    /// Landing / impact squash.
    func thud() {
        squash.removeAction(forKey: "squash")
        let flat = SKAction.group([.scaleX(to: 1.3, duration: 0.05), .scaleY(to: 0.72, duration: 0.05)])
        let settle = SKAction.group([.scaleX(to: 1, duration: 0.35), .scaleY(to: 1, duration: 0.35)])
        settle.timingFunction = { t in Mascot.springEase(t) }
        squash.run(.sequence([flat, settle]), withKey: "squash")
    }

    func die() {
        isDead = true
        eyeNodes.forEach { $0.isHidden = true }
        deadEyes.isHidden = false
        deadEyes.setScale(0.2)
        deadEyes.run(.scale(to: 1, duration: 0.18))
        for (i, ray) in rayNodes.enumerated() {
            ray.removeAllActions()
            ray.run(.group([.scale(to: 0.3, duration: 0.25),
                            .rotate(toAngle: -0.9 + CGFloat(i) * 0.2, duration: 0.25),
                            .fadeAlpha(to: 0, duration: 0.3)]))
        }
        glow.run(.fadeAlpha(to: 0, duration: 0.3))
    }

    func revive() {
        isDead = false
        eyeNodes.forEach { $0.isHidden = false }
        deadEyes.isHidden = true
        rayNodes.forEach { $0.removeAllActions(); $0.setScale(1); $0.zRotation = 0; $0.alpha = 1 }
        glow.alpha = 0.55
        squash.setScale(1)
        startRayIdle()
    }

    /// The eyes slide slightly toward where it's heading.
    func look(dy: CGFloat) {
        let off = dy.clamped(-1, 1) * 10
        for (e, piece) in zip(eyeNodes, Mascot.cache.textures.eyes) { e.position.y = piece.center.y + off }
    }

    private func startBlinking() {
        let blink = SKAction.sequence([
            .wait(forDuration: 2.2, withRange: 2.4),
            .scaleY(to: 0.1, duration: 0.05),
            .scaleY(to: 1, duration: 0.09),
        ])
        for e in eyeNodes { e.run(.repeatForever(blink), withKey: "blink") }
        // Keep both eyes in sync: drive the second from the first.
        eyeNodes.last?.removeAction(forKey: "blink")
        if let first = eyeNodes.first, let last = eyeNodes.last {
            last.run(.repeatForever(.customAction(withDuration: 1) { _, _ in last.yScale = first.yScale }))
        }
    }

    private func startRayIdle() {
        for (i, ray) in rayNodes.enumerated() {
            let pulse = SKAction.sequence([
                .wait(forDuration: Double(i) * 0.12),
                .scale(to: 1.12, duration: 0.18),
                .scale(to: 1, duration: 0.3),
                .wait(forDuration: 1.1),
            ])
            ray.run(.repeatForever(pulse), withKey: "idle")
        }
    }

    static func springEase(_ t: Float) -> Float {
        // Damped overshoot: 0 -> 1 with a single soft bounce.
        let tt = Double(t)
        return Float(1 - exp(-6 * tt) * cos(10 * tt))
    }

    private static func crossPath(size: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let h = size / 2
        p.move(to: CGPoint(x: -h, y: -h)); p.addLine(to: CGPoint(x: h, y: h))
        p.move(to: CGPoint(x: -h, y: h)); p.addLine(to: CGPoint(x: h, y: -h))
        return p
    }
}

// MARK: - Texture generation

private struct Piece {
    let texture: SKTexture
    let size: CGSize
    /// Centre in node space (SVG units, y up, relative to Mascot.origin).
    let center: CGPoint
}

private struct MascotTextures {
    let body: Piece
    let glow: Piece
    let eyes: [Piece]
    let rays: [Piece]
    let rayPivots: [CGPoint]
}

private final class TextureCache {
    lazy var textures: MascotTextures = build()

    private func nodeSpace(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - Mascot.origin.x, y: -(p.y - Mascot.origin.y))
    }

    private func piece(_ path: CGPath, pad: CGFloat, scale: CGFloat = 1.3,
                       draw: (CGContext, CGPath) -> Void) -> Piece {
        let box = path.boundingBoxOfPath.insetBy(dx: -pad, dy: -pad).integral
        let tex = Art.texture(size: box.size, scale: scale) { ctx in
            ctx.translateBy(x: -box.minX, y: -box.minY)
            draw(ctx, path)
        }
        return Piece(texture: tex, size: box.size, center: nodeSpace(CGPoint(x: box.midX, y: box.midY)))
    }

    private func build() -> MascotTextures {
        let bodyPath = SVGPath(Mascot.body).cgPath

        let body = piece(bodyPath, pad: 4) { ctx, path in
            ctx.addPath(path)
            ctx.setFillColor(Palette.lime.cgColor)
            ctx.fillPath()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let box = path.boundingBoxOfPath
            let space = CGColorSpaceCreateDeviceRGB()
            // Top light, belly shade.
            let shade = CGGradient(colorsSpace: space, colors: [
                UIColor.white.withAlphaComponent(0.22).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor,
                Palette.limeDeep.withAlphaComponent(0).cgColor,
                Palette.limeDeep.withAlphaComponent(0.55).cgColor,
            ] as CFArray, locations: [0, 0.35, 0.62, 1])!
            ctx.drawLinearGradient(shade, start: CGPoint(x: box.midX, y: box.minY),
                                   end: CGPoint(x: box.midX, y: box.maxY), options: [])
            // Inner rim for a soft, squishy edge.
            ctx.addPath(path)
            ctx.setStrokeColor(Palette.limeDeep.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(22)
            ctx.strokePath()
            // Specular blob.
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.4).cgColor)
            ctx.translateBy(x: 500, y: 405)
            ctx.rotate(by: -0.75)
            ctx.fillEllipse(in: CGRect(x: -34, y: -15, width: 68, height: 30))
            ctx.restoreGState()
        }

        let glow = piece(bodyPath, pad: 70, scale: 0.5) { ctx, path in
            ctx.setShadow(offset: .zero, blur: 50, color: Palette.lime.withAlphaComponent(0.9).cgColor)
            ctx.addPath(path)
            ctx.setFillColor(Palette.lime.withAlphaComponent(0.5).cgColor)
            ctx.fillPath()
        }

        let eyes = Mascot.eyes.map { d in
            piece(SVGPath(d).cgPath, pad: 2) { ctx, path in
                ctx.addPath(path)
                ctx.setFillColor(Palette.ink.cgColor)
                ctx.fillPath()
            }
        }

        let rayShapes = Mascot.rays.map(SVGPath.init)
        let rays = rayShapes.map { shape in
            piece(shape.cgPath, pad: 3) { ctx, path in
                ctx.addPath(path)
                ctx.setFillColor(Palette.orange.cgColor)
                ctx.fillPath()
                ctx.addPath(path)
                ctx.clip()
                ctx.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
                let b = path.boundingBoxOfPath
                ctx.fill(CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height * 0.3))
            }
        }
        // Each ray pivots on the end nearest the body, so flares burst outward.
        let pivots = rayShapes.map { shape -> CGPoint in
            let near = shape.points.min { a, b in
                hypot(a.x - Mascot.origin.x, a.y - Mascot.origin.y) < hypot(b.x - Mascot.origin.x, b.y - Mascot.origin.y)
            }!
            return nodeSpace(near)
        }
        return MascotTextures(body: body, glow: glow, eyes: eyes, rays: rays, rayPivots: pivots)
    }
}
