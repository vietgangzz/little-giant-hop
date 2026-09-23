import AVFoundation
import UIKit

/// Low-latency SFX + looping music on one AVAudioEngine.
/// SFX run through a small voice pool with varispeed so repeated sounds can
/// shift pitch (the score chime climbs with the combo). Music runs through a
/// low-pass EQ that closes down when the mascot gets hit.
final class SoundBoard {
    static let shared = SoundBoard()

    enum Sound: String, CaseIterable {
        case hop, score, spark, hit, fall, milestone, gameover, swoosh, tap
    }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var voices: [(player: AVAudioPlayerNode, pitch: AVAudioUnitVarispeed)] = []
    private var nextVoice = 0
    private let music = AVAudioPlayerNode()
    private let musicFilter = AVAudioUnitEQ(numberOfBands: 1)
    private var musicBuffer: AVAudioPCMBuffer?
    private var muffle: Float = 0
    private var muffleTarget: Float = 0
    private var musicVolume: Float = 0
    private var musicVolumeTarget: Float = 0.55

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        for sound in Sound.allCases { buffers[sound] = load(sound.rawValue) }
        musicBuffer = load("music")

        for _ in 0..<10 {
            let p = AVAudioPlayerNode(), v = AVAudioUnitVarispeed()
            engine.attach(p); engine.attach(v)
            engine.connect(p, to: v, format: format)
            engine.connect(v, to: engine.mainMixerNode, format: format)
            voices.append((p, v))
        }

        let band = musicFilter.bands[0]
        band.filterType = .lowPass
        band.frequency = 20_000
        band.bandwidth = 0.5
        band.bypass = false
        engine.attach(music); engine.attach(musicFilter)
        engine.connect(music, to: musicFilter, format: format)
        engine.connect(musicFilter, to: engine.mainMixerNode, format: format)
        music.volume = 0

        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in self?.restart() }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                               queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.restart() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.restart() }
        restart()
    }

    private func load(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        guard file.processingFormat.channelCount == 2 else { return nil }
        try? file.read(into: buf)
        return buf
    }

    private func restart() {
        guard !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        do { try engine.start() } catch { return }
        if let buf = musicBuffer {
            music.stop()
            music.scheduleBuffer(buf, at: nil, options: .loops)
            music.play()
        }
    }

    func play(_ sound: Sound, volume: Float = 1, pitch: Float = 1) {
        guard let buf = buffers[sound] else { return }
        if !engine.isRunning { restart() }
        guard engine.isRunning else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.player.stop()
        voice.pitch.rate = pitch
        voice.player.volume = volume
        voice.player.scheduleBuffer(buf, at: nil, options: .interrupts)
        voice.player.play()
    }

    /// 0 = open, 1 = underwater. Eased every frame from `tick`.
    func setMuffle(_ amount: Float) { muffleTarget = amount }
    func setMusicLevel(_ level: Float) { musicVolumeTarget = level }

    func tick(_ dt: Double) {
        let k = Float(min(1, dt * 5))
        muffle += (muffleTarget - muffle) * k
        musicVolume += (musicVolumeTarget - musicVolume) * Float(min(1, dt * 2.5))
        musicFilter.bands[0].frequency = 20_000 * powf(0.025, muffle)
        music.volume = musicVolume
    }
}

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()

    static func hop() { light.impactOccurred(intensity: 0.7) }
    static func score() { rigid.impactOccurred(intensity: 0.5) }
    static func hit() { heavy.impactOccurred(intensity: 1) }
    static func success() { notify.notificationOccurred(.success) }
    static func fail() { notify.notificationOccurred(.error) }
}
