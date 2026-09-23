# Little Giant Hop

A one-tap iOS arcade game starring the VGANG **Little Giant** mascot. Tap to hop through neon towers over a synthwave city at night.

Everything is made in this repo: the art is drawn in code from the approved brand vectors, and every sound and the music loop are synthesised by a Python script. There are no downloaded assets.

## What's in it

- **Mascot**: the exact brand paths from `landing-v2` (`mascotArtwork.ts`), rendered to textures at runtime. It adds shading, a glow, random blinking, squash-and-stretch on each hop, the orange rays flaring on every tap, eyes that look toward where it's heading, and X eyes when it dies.
- **World**: a parallax night city (sky, a retro sun, twinkling stars, two skyline layers, and a perspective neon floor grid that slides with the camera).
- **Obstacles**: neon towers with hazard-stripe caps. The gap shrinks and the speed rises as the score goes up. From score 12, some towers drift up and down.
- **Ray sparks**: optional orange pickups between towers worth +1.
- **Milestones**: every 10 points you get a banner, confetti, a fanfare, and a new colour theme (lime, orange, mint, violet).
- **Game feel**: hit-stop, a white flash, camera shake, slow motion, and music that goes muffled (low-pass filter) when you crash. There are haptics on hop, score, and hit.
- **Game over card**: the score counts up with ticks, and you earn a medal (Bronze 10, Silver 20, Gold 30, Giant 50) with a mini mascot inside. Beating your best shows a "NEW BEST!" badge with confetti.
- **Audio**: a 16-bar synthwave loop in A minor at 112 BPM (sidechain-pumped bass, a ping-pong-delayed arpeggio, and a lead melody) plus 9 sound effects. The score chime rises in pitch with your combo.
- **Any screen**: all tuning is relative to screen height, so folded and unfolded iPhone Duo, standard iPhones, and Pro Max play the same. Folding or unfolding rebuilds the layout.

## Build & run

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open LittleGiantHop.xcodeproj   # run on any iPhone simulator or device
```

To run from the command line on a simulator:

```sh
xcodebuild -project LittleGiantHop.xcodeproj -scheme LittleGiantHop \
  -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath build/dd build
xcrun simctl install booted "build/dd/Build/Products/Debug-iphonesimulator/Little Giant Hop.app"
xcrun simctl launch booted studio.vgang.littlegianthop
```

### Demo / autopilot mode

For recording demos, a bot can play the game:

```sh
xcrun simctl launch booted studio.vgang.littlegianthop -autopilot      # plays forever
xcrun simctl launch booted studio.vgang.littlegianthop -autopilot 14   # lets go at 14 to show the crash
```

## Regenerating assets

```sh
./tools/build_sounds.sh          # synthesise all sounds -> LittleGiantHop/Resources/Sounds/*.caf
./tools/build_sounds.sh music    # just one
python3 tools/make_icon.py LittleGiantHop/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

`tools/synth.py` only uses the Python standard library. `make_icon.py` needs Pillow.

## Layout

```
LittleGiantHop/
  App/LittleGiantHopApp.swift   SwiftUI entry, hosts the SKView
  Game/GameScene.swift          state machine, physics, scoring, juice, game-over card
  Game/Mascot.swift             Little Giant built from brand vectors
  Game/Backdrop.swift           sky, sun, skyline parallax, neon floor, themes
  Game/Obstacles.swift          towers, caps, ray sparks
  Game/HUD.swift                poster labels, motion helpers, particle factory
  Game/Art.swift                palette, SVG path parser, texture helpers
  Audio/SoundBoard.swift        AVAudioEngine voice pool, music + low-pass, haptics
tools/
  synth.py, build_sounds.sh     sound and music synthesis
  make_icon.py                  app icon
```
