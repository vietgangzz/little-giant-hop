import SpriteKit

enum Fonts {
    static let display = "AvenirNextCondensed-Heavy"
    static let bold = "AvenirNextCondensed-Bold"
    static let mono = "Menlo-Bold"
}

/// A label with a hard drop shadow, the brand's poster look.
final class PosterLabel: SKNode {
    private let face: SKLabelNode
    private let shadow: SKLabelNode

    init(_ text: String, size: CGFloat, color: UIColor, font: String = Fonts.display,
         shadowColor: UIColor = Palette.ink, depth: CGFloat? = nil) {
        face = SKLabelNode(fontNamed: font)
        shadow = SKLabelNode(fontNamed: font)
        super.init()
        for l in [shadow, face] {
            l.text = text
            l.fontSize = size
            l.verticalAlignmentMode = .center
            l.horizontalAlignmentMode = .center
            addChild(l)
        }
        face.fontColor = color
        shadow.fontColor = shadowColor
        let d = depth ?? max(2, size * 0.06)
        shadow.position = CGPoint(x: d, y: -d)
    }

    required init?(coder: NSCoder) { fatalError() }

    var text: String {
        get { face.text ?? "" }
        set { face.text = newValue; shadow.text = newValue }
    }

    var color: UIColor {
        get { face.fontColor ?? .white }
        set { face.fontColor = newValue }
    }

    var width: CGFloat { face.frame.width }
}

enum Motion {
    static func pop(_ node: SKNode, to scale: CGFloat = 1, from start: CGFloat = 1.35, duration: TimeInterval = 0.3) {
        node.removeAction(forKey: "pop")
        node.setScale(start)
        let settle = SKAction.scale(to: scale, duration: duration)
        settle.timingFunction = { t in Mascot.springEase(t) }
        node.run(settle, withKey: "pop")
    }

    static func pulse(_ node: SKNode, amount: CGFloat = 1.08, period: TimeInterval = 0.9) {
        let up = SKAction.scale(to: amount, duration: period / 2)
        let down = SKAction.scale(to: 1, duration: period / 2)
        up.timingMode = .easeInEaseOut
        down.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([up, down])), withKey: "pulse")
    }
}

/// Builds particle emitters in code (no .sks files).
enum FX {
    static func emitter(texture: SKTexture = Art.softDot, birthRate: CGFloat, count: Int = 0,
                        lifetime: CGFloat, lifetimeRange: CGFloat = 0, speed: CGFloat, speedRange: CGFloat = 0,
                        angle: CGFloat = 0, angleRange: CGFloat = .pi * 2, scale: CGFloat, scaleRange: CGFloat = 0,
                        scaleSpeed: CGFloat = 0, alpha: CGFloat = 1, alphaSpeed: CGFloat, color: UIColor,
                        colors: [UIColor]? = nil, accel: CGVector = .zero, spin: CGFloat = 0,
                        blend: SKBlendMode = .add) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.particleBirthRate = birthRate
        e.numParticlesToEmit = count
        e.particleLifetime = lifetime
        e.particleLifetimeRange = lifetimeRange
        e.particleSpeed = speed
        e.particleSpeedRange = speedRange
        e.emissionAngle = angle
        e.emissionAngleRange = angleRange
        e.particleScale = scale
        e.particleScaleRange = scaleRange
        e.particleScaleSpeed = scaleSpeed
        e.particleAlpha = alpha
        e.particleAlphaSpeed = alphaSpeed
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.xAcceleration = accel.dx
        e.yAcceleration = accel.dy
        e.particleRotationRange = spin > 0 ? .pi * 2 : 0
        e.particleRotationSpeed = spin
        e.particleBlendMode = blend
        if let colors, colors.count > 1 {
            let times = colors.indices.map { NSNumber(value: Double($0) / Double(colors.count - 1)) }
            e.particleColorSequence = SKKeyframeSequence(keyframeValues: colors, times: times)
        }
        return e
    }

    /// One-shot burst that removes itself.
    static func burst(in parent: SKNode, at p: CGPoint, _ make: () -> SKEmitterNode, life: TimeInterval = 1.5) {
        let e = make()
        e.position = p
        e.zPosition = 30
        e.targetNode = parent
        parent.addChild(e)
        e.run(.sequence([.wait(forDuration: life), .removeFromParent()]))
    }
}
