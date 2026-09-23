import SpriteKit
import UIKit

/// Plain UIKit lifecycle: the game needs direct control over rotation,
/// scene geometry and hinge updates, which SwiftUI's hosting layers hide.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Game", sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    /// Fallback for systems without the per-scene hook (iOS < 27).
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Layout.orientations(for: window?.windowScene)
    }
}

enum Layout {
    /// Folded (phone-sized) screens stay portrait. An unfolded iPhone Duo is
    /// tablet-sized and also allows landscape, so the game fills both halves.
    static func isLargeScreen(_ scene: UIWindowScene?) -> Bool {
        guard let b = scene?.screen.bounds else { return false }
        return min(b.width, b.height) >= 600
    }

    static func orientations(for scene: UIWindowScene?) -> UIInterfaceOrientationMask {
        isLargeScreen(scene) ? .allButUpsideDown : .portrait
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var wasLarge: Bool?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.backgroundColor = Palette.ink
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
        wasLarge = Layout.isLargeScreen(scene)
    }

    @objc(supportedInterfaceOrientationsForWindowScene:)
    func supportedInterfaceOrientations(for windowScene: UIWindowScene) -> UIInterfaceOrientationMask {
        Layout.orientations(for: windowScene)
    }

    @available(iOS 26.0, *)
    func windowScene(_ windowScene: UIWindowScene, didUpdateEffectiveGeometry previous: UIWindowScene.Geometry) {
        let large = Layout.isLargeScreen(windowScene)
        // `previous` arrives as nil on the very first callback (scene creation)
        // despite the non-optional signature, so it is never touched.
        FoldLog.log("geometry -> \(windowScene.effectiveGeometry.coordinateSpace.bounds.size) large=\(large)")
        if large != wasLarge {
            wasLarge = large
            // Folding or unfolding changes which orientations make sense.
            window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

final class GameViewController: UIViewController {
    private let skView = SKView()
    private let scene = GameScene(size: CGSize(width: 390, height: 844))

    /// QA: `-foldDemo` narrows and widens the game view every few seconds,
    /// with fake hinge updates, to exercise the unfold path on any simulator.
    private let foldDemo = ProcessInfo.processInfo.arguments.contains("-foldDemo")
    private var demoFolded = false

    override func loadView() {
        skView.preferredFramesPerSecond = 120
        skView.backgroundColor = Palette.ink
        skView.isMultipleTouchEnabled = false
        if foldDemo {
            view = UIView()
            view.backgroundColor = .black
            view.addSubview(skView)
        } else {
            view = skView
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
        if foldDemo { scheduleFoldDemo() }

        if #available(iOS 27.1, *) {
            let hinge = UIHingeInteraction { [weak self] _, update in
                guard let hinge = update.hinge else {
                    self?.scene.hingeChanged(.unavailable, angle: 0)
                    return
                }
                let state: GameScene.Hinge
                switch hinge.status {
                case .closed: state = .closed
                case .partiallyOpen: state = .moving
                case .fullyOpen: state = .open
                default: state = .unavailable
                }
                FoldLog.log("hinge \(state) angle=\(String(format: "%.2f", hinge.angle))")
                self?.scene.hingeChanged(state, angle: hinge.angle)
            }
            view.addInteraction(hinge)
        }
    }

    private func scheduleFoldDemo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            self.scene.hingeChanged(.moving, angle: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.demoFolded.toggle()
                self.scene.captureSnapshot(from: self.skView)
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
                self.scene.hingeChanged(self.demoFolded ? .closed : .open, angle: self.demoFolded ? 0 : .pi)
                self.scheduleFoldDemo()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if foldDemo {
            let b = view.bounds
            let w = demoFolded ? (b.width * 0.49).rounded() : b.width
            skView.frame = CGRect(x: b.width - w, y: 0, width: w, height: b.height)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        FoldLog.log("transition \(view.bounds.size) -> \(size)")
        // The system's rotation animation spins a snapshot of the game, which
        // is what looked broken mid-unfold. Snap the window instead and let
        // the scene run its own unfold animation on live content.
        scene.captureSnapshot(from: skView)
        UIView.setAnimationsEnabled(false)
        coordinator.animate(alongsideTransition: nil) { _ in UIView.setAnimationsEnabled(true) }
        super.viewWillTransition(to: size, with: coordinator)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
}

enum FoldLog {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("[LGH] %@", message())
        #endif
    }
}
