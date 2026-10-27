import AVFoundation
import Foundation
import PopupBookCore

public struct AudioAsset {
    public let id: SoundID
    public let url: URL
    public let volume: Float
    public let loops: Bool
    public let autostart: Bool
    public init(id: SoundID, url: URL, volume: Float, loops: Bool = false, autostart: Bool = true) {
        self.id = id
        self.url = url
        self.volume = volume
        self.loops = loops
        self.autostart = autostart
    }
}
@MainActor public final class BundleAudio: AudioOutput {
    private var players: [SoundID: [AVAudioPlayer]] = [:]
    private var volumes: [SoundID: Float] = [:]
    private var autostart: Set<SoundID> = []
    private var variants: [SoundID: Int] = [:]
    private var stops: [SoundID: Timer] = [:]
    private var enabled = false
    public private(set) var lastError: String?
    public init(assets: [AudioAsset]) throws {
        for asset in assets {
            let player = try AVAudioPlayer(contentsOf: asset.url)
            player.volume = asset.volume
            player.numberOfLoops = asset.loops ? -1 : 0
            players[asset.id, default: []].append(player)
            volumes[asset.id] = asset.volume
            if asset.loops && asset.autostart { autostart.insert(asset.id) }
        }
    }
    public func setActive(_ active: Bool) {
        enabled = active
        if active {
            for id in autostart { startLoop(id) }
        } else {
            for timer in stops.values { timer.invalidate() }
            stops.removeAll()
            for group in players.values {
                for player in group {
                    player.stop()
                    player.currentTime = 0
                }
            }
        }
    }
    public func play(_ sound: SoundID) {
        guard enabled else { return }
        guard let group = players[sound], !group.isEmpty else {
            missing(sound)
            return
        }
        // Rotate distinct recordings deterministically; no immediate same sample repeats.
        let index = variants[sound, default: 0] % group.count
        variants[sound] = index + 1
        for player in group { player.stop() }
        let player = group[index]
        player.currentTime = 0
        player.volume = volumes[sound] ?? 0.1
        if player.play() { lastError = nil } else { lastError = L10n.text("声音暂时无法播放：%@", sound.rawValue) }
    }
    public func startLoop(_ sound: SoundID) {
        guard enabled else { return }
        stops.removeValue(forKey: sound)?.invalidate()
        guard let player = players[sound]?.first, player.numberOfLoops == -1 else {
            missing(sound)
            return
        }
        if !player.isPlaying {
            player.volume = 0
            if !player.play() {
                lastError = L10n.text("循环声音暂时无法播放：%@", sound.rawValue)
                return
            }
        }
        player.setVolume(volumes[sound] ?? 0.1, fadeDuration: 0.15)
    }
    public func stopLoop(_ sound: SoundID, fade: Double) {
        stops.removeValue(forKey: sound)?.invalidate()
        guard let player = players[sound]?.first else {
            missing(sound)
            return
        }
        let duration = fade.isFinite ? clamp(fade, 0, 2) : 0
        guard player.isPlaying else { return }
        player.setVolume(0, fadeDuration: duration)
        if duration == 0 {
            player.stop()
            player.currentTime = 0
            return
        }
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.players[sound]?.first?.stop()
                self.players[sound]?.first?.currentTime = 0
                self.stops.removeValue(forKey: sound)
            }
        }
        stops[sound] = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func missing(_ sound: SoundID) { lastError = L10n.text("没有找到声音资源：%@", sound.rawValue) }
    deinit { for timer in stops.values { timer.invalidate() } }
}
