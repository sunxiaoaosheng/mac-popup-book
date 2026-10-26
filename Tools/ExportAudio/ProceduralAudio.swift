import Foundation
import PopupBookCore

enum ProceduralAudio {
    static func wave(seconds: Double, kind: Int) -> Data {
        let rate = 22050
        let count = Int(seconds * Double(rate))
        var samples = Data(capacity: count * 2)
        var seed: UInt32 = 5489
        var low = 0.0
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let u = t / seconds
            seed = 1_664_525 &* seed &+ 1_013_904_223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            low += (noise - low) * 0.045
            let value: Double
            if kind == 0 {
                value = (noise * 0.3 + low * 0.8) * pow(sin(.pi * u), 2) * 0.45
            } else if kind == 1 {
                let frequency = 530 + 250 * sin(.pi * u) - 190 * u
                phase += 2 * .pi * frequency / Double(rate)
                value =
                    (sin(phase) + 0.28 * sin(phase * 2) + 0.12 * sin(phase * 3)) * pow(sin(.pi * u), 1.8)
                    * 0.3
            } else {
                // Loop endpoints fade to silence; one gentle bird-like overtone per cycle.
                let envelope = pow(sin(.pi * u), 2)
                let bird =
                    t > 3.2 && t < 3.65
                    ? sin(2 * .pi * (1600 * t + 140 * t * t)) * pow(sin(.pi * (t - 3.2) / 0.45), 2) * 0.08 : 0
                value = low * envelope * 0.7 + bird
            }
            var s = Int16(clamp(value, -1, 1) * 32760).littleEndian
            withUnsafeBytes(of: &s) { samples.append(contentsOf: $0) }
        }
        var data = Data()
        func ascii(_ s: String) { data.append(s.data(using: .ascii)!) }
        func u32(_ x: UInt32) {
            var x = x.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        func u16(_ x: UInt16) {
            var x = x.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        ascii("RIFF")
        u32(UInt32(samples.count + 36))
        ascii("WAVEfmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(rate))
        u32(UInt32(rate * 2))
        u16(2)
        u16(16)
        ascii("data")
        u32(UInt32(samples.count))
        data.append(samples)
        return data
    }
}
