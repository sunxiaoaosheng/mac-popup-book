import Foundation
import AVFoundation

/// Procedural original sounds: no recordings, downloads, microphone, or network.
final class BookAudio {
    private var paper: AVAudioPlayer?
    private var cat: AVAudioPlayer?
    private var forest: AVAudioPlayer?
    init() {
        paper = try? AVAudioPlayer(data: Self.wave(seconds: 0.24, kind: 0))
        cat = try? AVAudioPlayer(data: Self.wave(seconds: 0.48, kind: 1))
        forest = try? AVAudioPlayer(data: Self.wave(seconds: 8, kind: 2))
        paper?.volume = 0.12; cat?.volume = 0.15; forest?.volume = 0.045; forest?.numberOfLoops = -1
    }
    func setActive(_ active: Bool) {
        if active { if forest?.isPlaying != true { forest?.play() } }
        else { forest?.pause(); paper?.stop(); cat?.stop() }
    }
    func rustle() { paper?.currentTime = 0; paper?.play() }
    func meow() { cat?.currentTime = 0; cat?.play() }
    static func wave(seconds: Double, kind: Int) -> Data {
        let rate = 22050, count = Int(seconds * Double(rate))
        var samples = Data(capacity: count * 2), seed: UInt32 = 5489, low = 0.0, phase = 0.0
        for i in 0..<count {
            let t = Double(i)/Double(rate), u = t/seconds
            seed = 1664525 &* seed &+ 1013904223
            let noise = Double(seed)/Double(UInt32.max)*2-1
            low += (noise-low)*0.045
            let value: Double
            if kind == 0 { value = (noise*0.3+low*0.8)*pow(sin(.pi*u),2)*0.45 }
            else if kind == 1 {
                let frequency = 530 + 250*sin(.pi*u) - 190*u
                phase += 2 * .pi * frequency/Double(rate)
                value = (sin(phase)+0.28*sin(phase*2)+0.12*sin(phase*3))*pow(sin(.pi*u),1.8)*0.3
            } else {
                // Loop endpoints fade to silence; one gentle bird-like overtone per cycle.
                let envelope = pow(sin(.pi*u),2)
                let bird = t > 3.2 && t < 3.65 ? sin(2 * .pi*(1600*t+140*t*t))*pow(sin(.pi*(t-3.2)/0.45),2)*0.08 : 0
                value = low*envelope*0.7+bird
            }
            var s = Int16(clamp(value,-1,1)*32760).littleEndian
            withUnsafeBytes(of:&s) { samples.append(contentsOf:$0) }
        }
        var data = Data()
        func ascii(_ s: String) { data.append(s.data(using:.ascii)!) }
        func u32(_ x: UInt32) { var x=x.littleEndian; withUnsafeBytes(of:&x) { data.append(contentsOf:$0) } }
        func u16(_ x: UInt16) { var x=x.littleEndian; withUnsafeBytes(of:&x) { data.append(contentsOf:$0) } }
        ascii("RIFF");u32(UInt32(samples.count+36));ascii("WAVEfmt ");u32(16);u16(1);u16(1)
        u32(UInt32(rate));u32(UInt32(rate*2));u16(2);u16(16);ascii("data");u32(UInt32(samples.count));data.append(samples)
        return data
    }
}
