import SpriteKit

final class GameScene: SKScene {
    private enum State { case ready, playing, dying, over }

    // Tuning, all relative to scene height so every screen (folded, unfolded,
    // Pro Max) plays the same.
    private enum Tune {
        static let gravity: CGFloat = 2.75
        static let hop: CGFloat = 0.84
        static let maxFall: CGFloat = 1.3
        static let mascotHeight: CGFloat = 0.085
        static let radius: CGFloat = 0.031
        static func speed(_ score: Int) -> CGFloat { 0.36 + CGFloat(min(score, 45)) * 0.0042 }
        static func gap(_ score: Int) -> CGFloat { 0.29 - CGFloat(min(score, 45)) * 0.0021 }
        static func spacing(_ score: Int) -> CGFloat { 0.6 - CGFloat(min(score, 45)) * 0.0022 }
    }

    private static let milestoneLines = ["NICE.", "BIG ENERGY.", "LITTLE GIANT!", "FULL ATTENTION.", "UNSTOPPABLE.", "LEGEND."]
    private static let deathLines = ["OUCH.", "BONK!", "SPLAT.", "OOF.", "WELP."]

    private var state: State = .ready
    private var layoutSize: CGSize = .zero

    private let world = SKNode()
    private let cam = SKCameraNode()
    private let hud = SKNode()
    private var backdrop: Backdrop!
    private var mascot: Mascot!
    private var shadowBlob: SKSpriteNode!
    private var trail: SKEmitterNode!
    private var art: PillarArt!
    private var pillars: [PillarPair] = []
    private var sparks: [Spark] = []

    private var scoreLabel: PosterLabel!
    private var readyLayer = SKNode()
    private var overLayer = SKNode()
    private var flash: SKSpriteNode!

    private var mx: CGFloat = 0, my: CGFloat = 0, vy: CGFloat = 0
    private var distance: CGFloat = 0
    private var speedNow: CGFloat = 0
    private var clock: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var timeScale: CGFloat = 1
    private var hitStop: TimeInterval = 0
    private var score = 0
    private var combo = 0
    private var canRestart = false
    private var lastGapCenter: CGFloat = 0

    /// Demo/QA bot: launch with `-autopilot` (plays forever) or
    /// `-autopilot N` (lets go after scoring N, to show the death sequence).
    private let autopilot: (on: Bool, until: Int) = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-autopilot") else { return (false, 0) }
        let limit = args.count > i + 1 ? Int(args[i + 1]) ?? .max : .max
        return (true, limit)
    }()
    private var autoRestartAt: TimeInterval = 0

    // Foldable support (iPhone Duo).
    enum Hinge { case closed, moving, open, unavailable }
    private var hingeHold = false
    private var holdLabel: PosterLabel?
    private var snapshot: SKTexture?
    private var leaf: SKNode?
    private var hudCenterX: CGFloat = 0

    private var best: Int {
        get { UserDefaults.standard.integer(forKey: "best") }
        set { UserDefaults.standard.set(newValue, forKey: "best") }
    }

    private var W: CGFloat { size.width }
    private var H: CGFloat { size.height }
    private var groundY: CGFloat { backdrop.groundY }
    private var radius: CGFloat { H * Tune.radius }
    private var homeX: CGFloat { min(W * 0.32, H * 0.3) }
    private var safeTop: CGFloat { max(view?.safeAreaInsets.top ?? 0, H * 0.03) }

    /// Everything is centred, folded or unfolded.
    private var uiX: CGFloat { W / 2 }
    private var restX: CGFloat { W / 2 }
    private var paneWidth: CGFloat { W }

    // MARK: lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.ink
        anchorPoint = .zero
        scaleMode = .resizeFill
        view.isMultipleTouchEnabled = false
        if cam.parent == nil { addChild(cam); camera = cam }
        if world.parent == nil { addChild(world) }
        _ = SoundBoard.shared
        rebuild()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard view != nil, backdrop != nil, size.width > 10, size.height > 10 else { return }
        let old = layoutSize
        guard abs(size.width - old.width) > 1 || abs(size.height - old.height) > 1 else { return }
        FoldLog.log("scene \(old) -> \(size) state=\(state)")
        if abs(size.height - old.height) <= old.height * 0.03 {
            // Fold / unfold keeps the height and changes the width, and all
            // gameplay is sized by height: keep the run going.
            relayoutWidth(from: old)
        } else {
            rebuild()
            crossfadeFromSnapshot()
        }
        snapshot = nil
    }

    private func relayoutWidth(from old: CGSize) {
        layoutSize = size
        let theme = backdrop.themeIndex
        backdrop.removeFromParent()
        backdrop = Backdrop(size: size, theme: theme)
        world.addChild(backdrop)
        backdrop.update(distance: distance, time: clock)
        layoutHUD()
        unfold(from: old)
    }

    /// Positions everything that depends on width or panes. Safe to call any time.
    private func layoutHUD() {
        cam.position = CGPoint(x: W / 2, y: H / 2)
        hud.position = CGPoint(x: -W / 2, y: -H / 2)
        scoreLabel.position = CGPoint(x: uiX, y: H - safeTop - H * 0.07)
        hud.childNode(withName: "mark")?.position = CGPoint(x: uiX, y: groundY * 0.3)
        flash.size = size
        let readyAlpha = readyLayer.alpha
        readyLayer.removeFromParent()
        buildReadyLayer()
        readyLayer.alpha = state == .ready ? readyAlpha : 0
        updateBestText()
        overLayer.position.x += uiX - hudCenterX
        if let dim = overLayer.childNode(withName: "dim") as? SKSpriteNode {
            dim.size = size
            dim.position.x = -overLayer.position.x
        }
        holdLabel?.position = CGPoint(x: uiX, y: H * 0.5)
        hudCenterX = uiX
    }

    /// The panel that stays put while unfolding is the right-hand one, so the
    /// world starts where the player was looking and glides into its new
    /// framing, with a light seam sweeping across the opening.
    private func unfold(from old: CGSize) {
        let dx = W - old.width
        world.removeAction(forKey: "unfold")
        world.position.x = dx
        let glide = SKAction.moveTo(x: 0, duration: 0.85)
        glide.timingFunction = { t in let u = 1 - t; return 1 - u * u * u }
        world.run(glide, withKey: "unfold")

        leaf?.removeFromParent()
        let leaf = SKNode()
        leaf.zPosition = 40
        let shade = SKSpriteNode(color: Palette.ink, size: CGSize(width: 1, height: H))
        shade.name = "shade"
        shade.anchorPoint = .zero
        leaf.addChild(shade)
        let seam = SKSpriteNode(texture: Art.softDot)
        seam.name = "seam"
        seam.size = CGSize(width: H * 0.06, height: H * 1.2)
        seam.color = Palette.lime
        seam.colorBlendFactor = 1
        seam.blendMode = .add
        leaf.addChild(seam)
        hud.addChild(leaf)
        self.leaf = leaf
        updateLeaf()
        leaf.run(.sequence([.wait(forDuration: 0.8), .fadeOut(withDuration: 0.25), .removeFromParent()]))

        cam.removeAction(forKey: "zoom")
        cam.setScale(0.95)
        let settle = SKAction.scale(to: 1, duration: 0.7)
        settle.timingMode = .easeOut
        cam.run(settle, withKey: "zoom")
        SoundBoard.shared.play(.swoosh, volume: 0.8, pitch: dx > 0 ? 0.8 : 1.2)
        Haptics.score()
    }

    /// Covers the strip the gliding world has not reached yet.
    private func updateLeaf() {
        guard let leaf, leaf.parent != nil,
              let shade = leaf.childNode(withName: "shade") as? SKSpriteNode,
              let seam = leaf.childNode(withName: "seam") else { return }
        let x = world.position.x
        shade.size = CGSize(width: abs(x), height: H)
        shade.position = CGPoint(x: x > 0 ? 0 : W + x, y: 0)
        seam.position = CGPoint(x: x > 0 ? x : W + x, y: H / 2)
    }

    private func crossfadeFromSnapshot() {
        guard let snapshot else { return }
        let sprite = SKSpriteNode(texture: snapshot)
        let s = snapshot.size()
        let k = max(W / s.width, H / s.height)
        sprite.size = CGSize(width: s.width * k, height: s.height * k)
        sprite.position = CGPoint(x: W / 2, y: H / 2)
        sprite.zPosition = 60
        hud.addChild(sprite)
        sprite.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
    }

    // MARK: foldable hooks (called by GameViewController)

    func captureSnapshot(from view: SKView) {
        snapshot = view.texture(from: self)
    }

    /// Freezes a run while the hinge is moving so an unfold can't kill you,
    /// then counts back in once it settles.
    func hingeChanged(_ hinge: Hinge, angle: CGFloat) {
        switch hinge {
        case .moving:
            if state == .playing { holdForHinge() }
        case .closed, .open, .unavailable:
            if hingeHold { releaseHinge() }
        }
    }

    private func holdForHinge() {
        removeAction(forKey: "hinge")
        hingeHold = true
        trail.particleBirthRate = 0
        SoundBoard.shared.setMuffle(0.6)
        if holdLabel == nil {
            let label = PosterLabel("HOLD ON…", size: H * 0.05, color: Palette.lime)
            label.zPosition = 45
            hud.addChild(label)
            holdLabel = label
        }
        holdLabel?.text = "HOLD ON…"
        holdLabel?.color = Palette.lime
        holdLabel?.position = CGPoint(x: uiX, y: H * 0.5)
        if let holdLabel { Motion.pop(holdLabel, from: 0.3) }
    }

    private func releaseHinge() {
        run(.sequence([
            .wait(forDuration: 0.6),
            .run { [weak self] in
                guard let self, let label = self.holdLabel else { return }
                label.text = "GO!"
                label.color = Palette.orange
                Motion.pop(label, from: 1.8)
                SoundBoard.shared.play(.tap, volume: 0.6, pitch: 1.3)
            },
            .wait(forDuration: 0.35),
            .run { [weak self] in
                guard let self else { return }
                self.holdLabel?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
                self.holdLabel = nil
                self.hingeHold = false
                SoundBoard.shared.setMuffle(0)
                if self.state == .playing {
                    self.trail.particleBirthRate = 55
                    self.hop()
                }
            },
        ]), withKey: "hinge")
    }

    private func rebuild() {
        layoutSize = size
        world.removeAllChildren()
        hud.removeAllChildren()
        hud.removeFromParent()
        pillars.removeAll()
        sparks.removeAll()
        overLayer = SKNode()
        leaf = nil
        holdLabel = nil
        hingeHold = false
        world.position = .zero

        cam.position = CGPoint(x: W / 2, y: H / 2)
        hud.position = CGPoint(x: -W / 2, y: -H / 2)
        hud.zPosition = 100
        cam.addChild(hud)

        backdrop = Backdrop(size: size)
        world.addChild(backdrop)
        art = PillarArt(sceneHeight: H)

        shadowBlob = SKSpriteNode(texture: Art.softDot)
        shadowBlob.color = .black
        shadowBlob.colorBlendFactor = 1
        shadowBlob.zPosition = -40
        world.addChild(shadowBlob)

        trail = FX.emitter(birthRate: 0, lifetime: 0.45, lifetimeRange: 0.1, speed: 0, angleRange: 0.2,
                           scale: H / 2600, scaleRange: H / 8000, scaleSpeed: -H / 2000, alpha: 0.8,
                           alphaSpeed: -1.8, color: Palette.lime)
        trail.zPosition = 15
        trail.targetNode = world
        world.addChild(trail)

        mascot = Mascot(height: H * Tune.mascotHeight)
        mascot.zPosition = 20
        world.addChild(mascot)

        scoreLabel = PosterLabel("0", size: H * 0.1, color: Palette.paper)
        scoreLabel.position = CGPoint(x: uiX, y: H - safeTop - H * 0.07)
        scoreLabel.alpha = 0
        hud.addChild(scoreLabel)

        let mark = SKLabelNode(fontNamed: Fonts.mono)
        mark.text = "vgang.studio"
        mark.name = "mark"
        mark.fontSize = max(10, H * 0.014)
        mark.fontColor = Palette.paper.withAlphaComponent(0.35)
        mark.position = CGPoint(x: uiX, y: groundY * 0.3)
        hud.addChild(mark)

        flash = SKSpriteNode(color: .white, size: size)
        flash.anchorPoint = .zero
        flash.alpha = 0
        flash.zPosition = 50
        hud.addChild(flash)

        hudCenterX = uiX
        buildReadyLayer()
        enterReady(animated: false)
    }

    // MARK: states

    private func buildReadyLayer() {
        readyLayer = SKNode()
        readyLayer.zPosition = 10
        hud.addChild(readyLayer)

        let titleSize = min(H * 0.075, paneWidth * 0.14)
        let title = PosterLabel("LITTLE GIANT", size: titleSize, color: Palette.lime)
        title.position = CGPoint(x: uiX, y: H * 0.8 - safeTop * 0.3)
        readyLayer.addChild(title)

        let hop = PosterLabel("HOP!", size: titleSize * 1.6, color: Palette.orange, depth: titleSize * 0.09)
        hop.position = CGPoint(x: uiX, y: title.position.y - titleSize * 1.25)
        hop.zRotation = 0.07
        readyLayer.addChild(hop)
        Motion.pulse(hop, amount: 1.06, period: 1.1)

        let hint = PosterLabel("TAP TO HOP", size: H * 0.03, color: Palette.paper, font: Fonts.bold)
        hint.position = CGPoint(x: uiX, y: groundY + H * 0.14)
        readyLayer.addChild(hint)
        hint.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)])))

        let ring = SKShapeNode(circleOfRadius: H * 0.03)
        ring.strokeColor = Palette.lime
        ring.lineWidth = 2
        ring.position = CGPoint(x: uiX, y: groundY + H * 0.085)
        readyLayer.addChild(ring)
        let tapDot = SKShapeNode(circleOfRadius: H * 0.011)
        tapDot.fillColor = Palette.lime
        tapDot.strokeColor = .clear
        tapDot.position = ring.position
        readyLayer.addChild(tapDot)
        ring.run(.repeatForever(.sequence([
            .group([.scale(to: 1.6, duration: 0.8), .fadeAlpha(to: 0, duration: 0.8)]),
            .group([.scale(to: 0.6, duration: 0), .fadeAlpha(to: 1, duration: 0)]),
        ])))

        let bestLabel = SKLabelNode(fontNamed: Fonts.mono)
        bestLabel.name = "best"
        bestLabel.fontSize = max(11, H * 0.017)
        bestLabel.fontColor = Palette.mute
        bestLabel.position = CGPoint(x: uiX, y: groundY + H * 0.03)
        readyLayer.addChild(bestLabel)
    }

    private func enterReady(animated: Bool) {
        state = .ready
        score = 0
        combo = 0
        timeScale = 1
        hitStop = 0
        canRestart = false
        for p in pillars { p.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()])) }
        for s in sparks { s.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()])) }
        pillars.removeAll()
        sparks.removeAll()

        mascot.revive()
        mascot.zRotation = 0
        mx = animated ? -H * 0.1 : restX
        my = H * 0.52
        vy = 0
        lastGapCenter = H * 0.5
        backdrop.setTheme(0)
        trail.particleBirthRate = 0

        updateBestText()
        readyLayer.removeAllActions()
        readyLayer.alpha = 0
        readyLayer.run(.fadeIn(withDuration: animated ? 0.35 : 0.6))
        scoreLabel.run(.fadeOut(withDuration: 0.2))
        SoundBoard.shared.setMuffle(0)
        SoundBoard.shared.setMusicLevel(0.45)
    }

    private func updateBestText() {
        (readyLayer.childNode(withName: "best") as? SKLabelNode)?.text = best > 0 ? "BEST \(best)" : "vgang presents"
    }

    private func start() {
        state = .playing
        readyLayer.removeAllActions()
        readyLayer.run(.group([.fadeOut(withDuration: 0.25), .moveBy(x: 0, y: H * 0.04, duration: 0.25)])) { [weak self] in
            self?.readyLayer.position = .zero
        }
        scoreLabel.text = "0"
        scoreLabel.run(.fadeIn(withDuration: 0.2))
        Motion.pop(scoreLabel)
        trail.particleBirthRate = 55
        SoundBoard.shared.setMusicLevel(0.6)
        hop()
    }

    private func hop() {
        vy = H * Tune.hop
        mascot.hop()
        SoundBoard.shared.play(.hop, volume: 0.75, pitch: .random(in: 0.94...1.08))
        Haptics.hop()
        FX.burst(in: world, at: CGPoint(x: mx - radius * 0.3, y: my - radius * 0.9)) {
            FX.emitter(birthRate: 400, count: 8, lifetime: 0.35, speed: H * 0.18, speedRange: H * 0.08,
                       angle: -.pi * 0.62, angleRange: 0.9, scale: H / 3000, scaleSpeed: -H / 2500,
                       alpha: 0.9, alphaSpeed: -2.6, color: Palette.lime)
        }
    }

    // MARK: input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch state {
        case .ready: start()
        case .playing: if !hingeHold { hop() }
        case .dying: break
        case .over: if canRestart { restart() }
        }
    }

    private func restart() {
        canRestart = false
        SoundBoard.shared.play(.swoosh, volume: 0.7)
        let layer = overLayer
        layer.run(.sequence([.group([.moveBy(x: 0, y: -H, duration: 0.35), .fadeOut(withDuration: 0.3)]),
                             .removeFromParent()]))
        enterReady(animated: true)
    }

    // MARK: loop

    override func update(_ currentTime: TimeInterval) {
        let raw = lastUpdate == 0 ? 1.0 / 60 : min(1.0 / 30, currentTime - lastUpdate)
        lastUpdate = currentTime
        SoundBoard.shared.tick(raw)
        guard backdrop != nil else { return }
        if hitStop > 0 { hitStop -= raw; return }
        timeScale += (1 - timeScale) * CGFloat(min(1, raw * 1.6))
        let dt = hingeHold && state == .playing ? 0 : CGFloat(raw) * timeScale
        clock += Double(dt)

        switch state {
        case .ready:
            if autopilot.on, clock > autoRestartAt { start() }
            speedNow = H * Tune.speed(0) * 0.55
            mx += (restX - mx) * min(1, dt * 4)
            my = H * 0.52 + sin(CGFloat(clock) * 2.6) * H * 0.018
            mascot.zRotation = sin(CGFloat(clock) * 2.6 + 1) * 0.06
            mascot.look(dy: cos(CGFloat(clock) * 2.6))
        case .playing:
            speedNow = H * Tune.speed(score)
            mx += (homeX - mx) * min(1, dt * 5)
            stepPlaying(dt)
        case .dying:
            speedNow *= max(0, 1 - dt * 2.5)
            stepDying(dt)
        case .over:
            speedNow *= max(0, 1 - dt * 3)
        }

        distance += speedNow * dt
        for p in pillars {
            p.position.x -= speedNow * dt
            p.update(time: clock, lo: pillarRange(gap: p.gap).lo, hi: pillarRange(gap: p.gap).hi)
        }
        for s in sparks { s.position.x -= speedNow * dt }
        pillars.removeAll { p in
            if p.position.x < -art.bodySize.width { p.removeFromParent(); return true }
            return false
        }
        sparks.removeAll { s in
            if s.collected { return true }
            if s.position.x < -H * 0.1 { s.removeFromParent(); return true }
            return false
        }

        backdrop.update(distance: distance, time: clock)
        updateLeaf()
        mascot.position = CGPoint(x: mx, y: my)
        let lift = ((my - groundY) / (H * 0.8)).clamped(0, 1)
        shadowBlob.position = CGPoint(x: mx, y: groundY + 1)
        shadowBlob.size = CGSize(width: H * 0.09 * (1 - lift * 0.6), height: H * 0.02 * (1 - lift * 0.6))
        shadowBlob.alpha = 0.7 * (1 - lift * 0.8)
        trail.position = CGPoint(x: mx - radius * 0.8, y: my - radius * 0.1)
        trail.particleSpeed = speedNow
        trail.emissionAngle = .pi
    }

    private func pillarRange(gap: CGFloat) -> (lo: CGFloat, hi: CGFloat) {
        (groundY + gap / 2 + H * 0.07, H - safeTop - gap / 2 - H * 0.08)
    }

    private func stepPlaying(_ dt: CGFloat) {
        vy = max(vy - H * Tune.gravity * dt, -H * Tune.maxFall)
        my += vy * dt
        if my > H * 1.04 { my = H * 1.04; vy = min(vy, 0) }
        let tilt = (vy / (H * Tune.hop)).clamped(-1.6, 1)
        let target = tilt > 0 ? tilt * 0.35 : tilt * 0.7
        mascot.zRotation += (target - mascot.zRotation) * min(1, dt * 10)
        mascot.look(dy: vy / (H * Tune.hop))

        spawnIfNeeded()
        if autopilot.on, score < autopilot.until { pilot() }

        let c = CGPoint(x: mx, y: my)
        for p in pillars where !p.passed && p.position.x + art.width / 2 < mx - radius {
            p.passed = true
            p.celebrate()
            addScore(1, bonus: false)
        }
        for s in sparks where !s.collected && hypot(s.position.x - mx, s.position.y - my) < radius + s.radius {
            collect(s)
        }
        if pillars.contains(where: { $0.hits(center: c, radius: radius) }) {
            die(hitGround: false)
        } else if my - radius * 0.9 < groundY {
            my = groundY + radius * 0.9
            die(hitGround: true)
        }
    }

    private func pilot() {
        let next = pillars.first { $0.position.x + art.width / 2 > mx - radius }
        var target = next.map { $0.gapCenter - $0.gap * 0.12 } ?? H * 0.5
        if let s = sparks.first(where: { !$0.collected && $0.position.x > mx }),
           next == nil || s.position.x < next!.position.x {
            target = s.position.y - radius
        }
        if my < target, vy < H * 0.05 { hop() }
    }

    private func spawnIfNeeded() {
        let spacing = H * Tune.spacing(score)
        let edge = W + art.bodySize.width
        guard let last = pillars.last else {
            spawnPillar(at: edge + H * 0.25)
            return
        }
        if last.position.x + spacing < edge + spacing * 0.5 {
            spawnPillar(at: last.position.x + spacing)
        }
    }

    private func spawnPillar(at x: CGFloat) {
        let gap = H * Tune.gap(score)
        let range = pillarRange(gap: gap)
        let swing = H * 0.26
        let center = (lastGapCenter + .random(-swing, swing)).clamped(range.lo, range.hi)
        let pair = PillarPair(art: art, gap: gap, center: center)
        pair.position = CGPoint(x: x, y: 0)
        pair.zPosition = 5
        if score >= 12, CGFloat.random(0, 1) < min(0.55, 0.2 + CGFloat(score) * 0.008) {
            pair.drift = (H * 0.055, .random(1.1, 1.8), .random(0, .pi * 2))
        }
        world.addChild(pair)
        if x < W {
            pair.alpha = 0
            pair.run(.fadeIn(withDuration: 0.35))
        }

        if let prev = pillars.last, score >= 1 || CGFloat.random(0, 1) < 0.5, CGFloat.random(0, 1) < 0.5 {
            let spark = Spark(size: H * 0.05)
            let y = (prev.gapCenter + center) / 2 + .random(-H * 0.04, H * 0.04)
            spark.position = CGPoint(x: (prev.position.x + x) / 2, y: y)
            spark.zPosition = 6
            world.addChild(spark)
            sparks.append(spark)
        }
        pillars.append(pair)
        lastGapCenter = center
    }

    private func addScore(_ n: Int, bonus: Bool) {
        let before = score
        score += n
        combo += 1
        scoreLabel.text = "\(score)"
        Motion.pop(scoreLabel, from: bonus ? 1.5 : 1.3)
        if !bonus {
            SoundBoard.shared.play(.score, volume: 0.6, pitch: 1 + Float(min(combo, 16)) * 0.022)
            Haptics.score()
        }
        if score / 10 > before / 10 { milestone(score / 10) }
    }

    private func collect(_ s: Spark) {
        s.collected = true
        SoundBoard.shared.play(.spark, volume: 0.8)
        Haptics.score()
        let p = s.position
        s.removeAllActions()
        s.run(.sequence([.group([.scale(to: 2, duration: 0.15), .fadeOut(withDuration: 0.15)]), .removeFromParent()]))
        FX.burst(in: world, at: p) {
            FX.emitter(texture: Art.spark, birthRate: 800, count: 14, lifetime: 0.6, lifetimeRange: 0.2,
                       speed: H * 0.35, speedRange: H * 0.15, scale: H / 2600, scaleSpeed: -H / 2400,
                       alphaSpeed: -1.6, color: Palette.orange, spin: 5)
        }
        let plus = PosterLabel("+1", size: H * 0.045, color: Palette.orange)
        plus.position = CGPoint(x: p.x, y: p.y + H * 0.03)
        plus.zPosition = 40
        world.addChild(plus)
        Motion.pop(plus, from: 0.4)
        plus.run(.sequence([.group([.moveBy(x: -H * 0.08, y: H * 0.08, duration: 0.7), .fadeOut(withDuration: 0.7)]),
                            .removeFromParent()]))
        addScore(1, bonus: true)
    }

    private func milestone(_ n: Int) {
        SoundBoard.shared.play(.milestone, volume: 0.75)
        Haptics.success()
        backdrop.setTheme(n)
        flash.color = Palette.lime
        flash.removeAllActions()
        flash.run(.sequence([.fadeAlpha(to: 0.18, duration: 0.05), .fadeOut(withDuration: 0.5)]))

        let line = GameScene.milestoneLines[(n - 1) % GameScene.milestoneLines.count]
        let banner = PosterLabel(line, size: min(H * 0.065, paneWidth * 0.12), color: Palette.lime,
                                 depth: H * 0.006)
        banner.position = CGPoint(x: uiX, y: H * 0.66)
        banner.zRotation = -0.05
        banner.zPosition = 20
        hud.addChild(banner)
        Motion.pop(banner, from: 0.2, duration: 0.45)
        banner.run(.sequence([.wait(forDuration: 1.1),
                              .group([.fadeOut(withDuration: 0.35), .moveBy(x: 0, y: H * 0.05, duration: 0.35)]),
                              .removeFromParent()]))
        confetti(from: CGPoint(x: uiX, y: H + 10), spread: .pi * 0.45)
    }

    private func confetti(from p: CGPoint, spread: CGFloat) {
        for color in [Palette.lime, Palette.orange, Palette.paper] {
            FX.burst(in: hud, at: p, {
                FX.emitter(texture: Art.confettiBit, birthRate: 300, count: 26, lifetime: 2.2, lifetimeRange: 0.6,
                           speed: H * 0.55, speedRange: H * 0.3, angle: -.pi / 2, angleRange: spread,
                           scale: H / 1400, scaleRange: H / 3000, alphaSpeed: -0.35, color: color,
                           accel: CGVector(dx: 0, dy: -H * 0.5), spin: 7, blend: .alpha)
            }, life: 3)
        }
    }

    // MARK: death

    private func die(hitGround: Bool) {
        state = .dying
        hitStop = 0.09
        timeScale = 0.3
        combo = 0
        mascot.die()
        trail.particleBirthRate = 0
        SoundBoard.shared.play(.hit, volume: 1)
        SoundBoard.shared.setMuffle(1)
        SoundBoard.shared.setMusicLevel(0.3)
        Haptics.hit()

        flash.color = .white
        flash.removeAllActions()
        flash.alpha = 0.85
        flash.run(.fadeOut(withDuration: 0.3))
        shake(amount: H * 0.022, duration: 0.45)

        let p = CGPoint(x: mx, y: my)
        for color in [Palette.lime, Palette.orange] {
            FX.burst(in: world, at: p) {
                FX.emitter(texture: Art.hardDot, birthRate: 2000, count: 18, lifetime: 0.9, lifetimeRange: 0.3,
                           speed: H * 0.5, speedRange: H * 0.25, scale: H / 1600, scaleRange: H / 3200,
                           scaleSpeed: -H / 2200, alphaSpeed: -0.9, color: color,
                           accel: CGVector(dx: 0, dy: -H * 1.2), blend: .alpha)
            }
        }
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.strokeColor = Palette.paper
        ring.lineWidth = 3
        ring.position = p
        ring.zPosition = 25
        world.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 5, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))

        if hitGround {
            vy = H * 0.35
        } else {
            vy = H * 0.5
            run(.sequence([.wait(forDuration: 0.18), .run { SoundBoard.shared.play(.fall, volume: 0.55) }]))
        }
    }

    private func stepDying(_ dt: CGFloat) {
        vy = max(vy - H * Tune.gravity * dt, -H * Tune.maxFall)
        my += vy * dt
        mx -= speedNow * dt * 0.2
        mascot.zRotation += (-.pi * 0.55 - mascot.zRotation) * min(1, dt * 6)
        if my - radius * 0.85 <= groundY && vy < 0 {
            my = groundY + radius * 0.85
            vy = 0
            land()
        }
    }

    private func land() {
        state = .over
        mascot.thud()
        Haptics.fail()
        SoundBoard.shared.play(.tap, volume: 0.5, pitch: 0.5)
        FX.burst(in: world, at: CGPoint(x: mx, y: groundY + 2)) {
            FX.emitter(birthRate: 600, count: 16, lifetime: 0.6, speed: H * 0.15, speedRange: H * 0.08,
                       angle: .pi / 2, angleRange: .pi * 0.9, scale: H / 1800, scaleSpeed: -H / 3000,
                       alpha: 0.5, alphaSpeed: -0.8, color: Palette.paper, blend: .alpha)
        }
        run(.sequence([.wait(forDuration: 0.35), .run { [weak self] in self?.showGameOver() }]))
    }

    private func shake(amount: CGFloat, duration: TimeInterval) {
        cam.removeAction(forKey: "shake")
        let steps = 12
        var actions: [SKAction] = []
        for i in 0..<steps {
            let k = amount * (1 - CGFloat(i) / CGFloat(steps))
            let to = CGPoint(x: W / 2 + .random(-k, k), y: H / 2 + .random(-k, k))
            actions.append(.move(to: to, duration: duration / Double(steps)))
        }
        actions.append(.move(to: CGPoint(x: W / 2, y: H / 2), duration: 0.05))
        cam.run(.sequence(actions), withKey: "shake")
        cam.run(.sequence([.rotate(toAngle: 0.02, duration: 0.05), .rotate(toAngle: -0.015, duration: 0.08),
                           .rotate(toAngle: 0, duration: 0.15)]))
    }

    // MARK: game over

    private func showGameOver() {
        let isNewBest = score > best && score > 0
        if isNewBest { best = score }
        SoundBoard.shared.play(.gameover, volume: 0.7)
        scoreLabel.run(.fadeOut(withDuration: 0.2))

        overLayer = SKNode()
        overLayer.zPosition = 30
        hud.addChild(overLayer)

        let cardW = min(paneWidth * 0.84, H * 0.5)
        let cardH = cardW * 0.6
        let center = CGPoint(x: uiX, y: H * 0.52)

        let dim = SKSpriteNode(color: .black, size: size)
        dim.name = "dim"
        dim.anchorPoint = .zero
        dim.alpha = 0
        dim.zPosition = -1
        overLayer.addChild(dim)
        dim.run(.fadeAlpha(to: 0.35, duration: 0.3))

        let card = SKNode()
        card.position = CGPoint(x: center.x, y: center.y - H * 0.6)
        overLayer.addChild(card)

        let rect = CGRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH)
        let offset = cardW * 0.025
        let back = SKShapeNode(rect: rect.offsetBy(dx: offset, dy: -offset), cornerRadius: cardW * 0.05)
        back.fillColor = Palette.lime
        back.strokeColor = .clear
        card.addChild(back)
        let face = SKShapeNode(rect: rect, cornerRadius: cardW * 0.05)
        face.fillColor = UIColor(hex: 0x121418)
        face.strokeColor = Palette.lime
        face.lineWidth = 2
        card.addChild(face)

        // Medal with a mini mascot.
        let medalR = cardH * 0.3
        let medal = SKNode()
        medal.position = CGPoint(x: -cardW * 0.24, y: 0)
        card.addChild(medal)
        let (medalColor, medalName) = GameScene.medal(for: score)
        let disc = SKShapeNode(circleOfRadius: medalR)
        disc.fillColor = medalColor.withAlphaComponent(medalName == nil ? 0.15 : 1)
        disc.strokeColor = medalName == nil ? Palette.mute.withAlphaComponent(0.4) : .white.withAlphaComponent(0.7)
        disc.lineWidth = 3
        medal.addChild(disc)
        let mini = Mascot(height: medalR * 1.05, glowing: false)
        mini.position = CGPoint(x: -medalR * 0.08, y: 0)
        medal.addChild(mini)
        if medalName == nil { mini.alpha = 0.5 }
        let medalLabel = SKLabelNode(fontNamed: Fonts.mono)
        medalLabel.text = medalName ?? "NO MEDAL"
        medalLabel.fontSize = max(9, cardH * 0.075)
        medalLabel.fontColor = medalName == nil ? Palette.mute : medalColor
        medalLabel.position = CGPoint(x: 0, y: -medalR - cardH * 0.14)
        medal.addChild(medalLabel)
        if medalName != nil {
            medal.setScale(0)
            medal.run(.sequence([.wait(forDuration: 0.75), .run { Motion.pop(medal, from: 0.01, duration: 0.5) }]))
            let shine = SKSpriteNode(texture: Art.spark)
            shine.size = CGSize(width: medalR * 0.6, height: medalR * 0.6)
            shine.position = CGPoint(x: medalR * 0.6, y: medalR * 0.6)
            shine.blendMode = .add
            medal.addChild(shine)
            shine.run(.repeatForever(.sequence([.scale(to: 0, duration: 0), .wait(forDuration: 1.2),
                                                .scale(to: 1, duration: 0.15), .scale(to: 0, duration: 0.25)])))
        }

        let colX = cardW * 0.2
        let caption = { (text: String, y: CGFloat) -> SKLabelNode in
            let l = SKLabelNode(fontNamed: Fonts.mono)
            l.text = text
            l.fontSize = max(10, cardH * 0.075)
            l.fontColor = Palette.mute
            l.position = CGPoint(x: colX, y: y)
            card.addChild(l)
            return l
        }
        _ = caption("SCORE", cardH * 0.3)
        let scoreValue = PosterLabel("0", size: cardH * 0.26, color: Palette.paper)
        scoreValue.position = CGPoint(x: colX, y: cardH * 0.12)
        card.addChild(scoreValue)
        _ = caption("BEST", -cardH * 0.14)
        let bestValue = PosterLabel("\(best)", size: cardH * 0.17, color: Palette.lime)
        bestValue.position = CGPoint(x: colX, y: -cardH * 0.3)
        card.addChild(bestValue)

        let title = PosterLabel(GameScene.deathLines.randomElement()!, size: min(paneWidth * 0.17, H * 0.09),
                                color: Palette.orange, depth: H * 0.007)
        title.position = CGPoint(x: center.x, y: center.y + cardH / 2 + H * 0.075)
        title.zRotation = -0.05
        title.setScale(0)
        overLayer.addChild(title)
        title.run(.sequence([.wait(forDuration: 0.12), .run { Motion.pop(title, from: 0.01, duration: 0.5) }]))

        let rise = SKAction.move(to: center, duration: 0.55)
        rise.timingFunction = { t in Mascot.springEase(t) }
        card.run(.sequence([.wait(forDuration: 0.05), rise]))

        // Count the score up, ticking.
        let total = score
        if total > 0 {
            var shown = 0
            let steps = min(total, 30)
            scoreValue.run(.sequence([
                .wait(forDuration: 0.45),
                .customAction(withDuration: 0.6) { _, t in
                    let v = Int((CGFloat(total) * t / 0.6).rounded())
                    guard v != shown else { return }
                    let stepBefore = shown * steps / max(total, 1)
                    shown = v
                    scoreValue.text = "\(v)"
                    if v * steps / total != stepBefore {
                        SoundBoard.shared.play(.tap, volume: 0.25, pitch: 0.8 + Float(v) / Float(total) * 0.6)
                    }
                },
                .run { scoreValue.text = "\(total)"; Motion.pop(scoreValue) },
            ]))
        }

        if isNewBest {
            let badge = SKNode()
            let tagW = cardW * 0.3, tagH = cardH * 0.13
            let tag = SKShapeNode(rect: CGRect(x: -tagW / 2, y: -tagH / 2, width: tagW, height: tagH),
                                  cornerRadius: tagH * 0.3)
            tag.fillColor = Palette.orange
            tag.strokeColor = Palette.ink
            tag.lineWidth = 2
            badge.addChild(tag)
            let t = SKLabelNode(fontNamed: Fonts.display)
            t.text = "NEW BEST!"
            t.fontSize = tagH * 0.7
            t.fontColor = Palette.ink
            t.verticalAlignmentMode = .center
            badge.addChild(t)
            badge.position = CGPoint(x: cardW * 0.36, y: cardH * 0.46)
            badge.zRotation = -0.18
            badge.setScale(0)
            card.addChild(badge)
            badge.run(.sequence([.wait(forDuration: 1.1), .run { [weak self] in
                Motion.pop(badge, from: 0.01, duration: 0.5)
                Motion.pulse(badge, amount: 1.08, period: 0.8)
                SoundBoard.shared.play(.milestone, volume: 0.7)
                Haptics.success()
                guard let self else { return }
                self.confetti(from: CGPoint(x: self.uiX, y: self.H + 10), spread: .pi * 0.5)
            }]))
        }

        let retry = PosterLabel("TAP TO RETRY", size: H * 0.032, color: Palette.paper, font: Fonts.bold)
        retry.position = CGPoint(x: center.x, y: center.y - cardH / 2 - H * 0.08)
        retry.alpha = 0
        overLayer.addChild(retry)
        retry.run(.sequence([.wait(forDuration: 0.9), .fadeIn(withDuration: 0.2), .run { [weak self] in
            self?.canRestart = true
            if let self, self.autopilot.on {
                self.run(.sequence([.wait(forDuration: 3), .run { [weak self] in
                    self?.restart()
                    self?.autoRestartAt = (self?.clock ?? 0) + 1.5
                }]))
            }
            retry.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)])))
        }]))
    }

    private static func medal(for score: Int) -> (UIColor, String?) {
        switch score {
        case 50...: return (Palette.lime, "GIANT")
        case 30..<50: return (UIColor(hex: 0xFFC940), "GOLD")
        case 20..<30: return (UIColor(hex: 0xC9D2DC), "SILVER")
        case 10..<20: return (UIColor(hex: 0xD08A4E), "BRONZE")
        default: return (Palette.mute, nil)
        }
    }
}
