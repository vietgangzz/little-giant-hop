import SpriteKit
import SwiftUI

@main
struct LittleGiantHopApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// Hosts a plain SKView: touches go straight to the scene and the frame rate
/// can follow ProMotion.
struct GameView: UIViewRepresentable {
    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.preferredFramesPerSecond = 120
        view.backgroundColor = Palette.ink
        view.isMultipleTouchEnabled = false
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {}
}
