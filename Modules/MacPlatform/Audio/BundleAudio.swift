import AVFoundation
import Foundation
import PopupBookCore

public struct AudioAsset {
    public let id: SoundID
    public let url: URL
    public let volume: Float
    public let loops: Bool
    public init(id: SoundID, url: URL, volume: Float, loops: Bool = false) {
        self.id = id
        self.url = url
        self.volume = volume
        self.loops = loops
    }
}
@MainActor public final class BundleAudio: AudioOutput {
    private var players: [SoundID: AVAudioPlayer] = [:]
    private var enabled = false
    public private(set) var lastError: String?
    public init(assets: [AudioAsset]) throws {
        for asset in assets {
            let player = try AVAudioPlayer(contentsOf: asset.url)
            player.volume = asset.volume
            player.numberOfLoops = asset.loops ? -1 : 0
            players[asset.id] = player
        }
    }
    public func setActive(_ active: Bool) {
        enabled = active
        for player in players.values {
            if active && player.numberOfLoops == -1 {
                if !player.isPlaying && !player.play() { lastError = "环境声音暂时无法播放。" }
            } else if !active {
                player.pause()
                if player.numberOfLoops != -1 { player.currentTime = 0 }
            }
        }
    }
    public func play(_ sound: SoundID) {
        guard enabled else { return }
        guard let player = players[sound] else {
            lastError = "没有找到声音资源：\(sound.rawValue)"
            return
        }
        player.currentTime = 0
        if !player.play() { lastError = "声音暂时无法播放：\(sound.rawValue)" }
    }
}
