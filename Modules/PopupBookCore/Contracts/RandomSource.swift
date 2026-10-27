import Foundation

public protocol RandomSource {
    mutating func nextUnit() -> Double
}

/// Reproducible choice without a global random generator in business logic.
public struct SeededRandom: RandomSource {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }
}
