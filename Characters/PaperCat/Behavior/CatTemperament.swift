import Foundation
import PopupBookCore

/// Short-lived feelings, kept separate from durable relationship memory.
public struct CatTemperament {
    public private(set) var attention = 0.0
    public private(set) var relaxation = 0.2
    public private(set) var willingness = 0.55
    public private(set) var solitude = 0.0
    public init() {}
    mutating func advance(_ dt: Double, touched: Bool) {
        attention = clamp(attention - dt * 0.12)
        relaxation = clamp(relaxation + dt * (touched ? 0.12 : -0.012), 0.2, 1)
        solitude = clamp(solitude + dt * (touched ? 0.09 : -0.125))
        willingness = clamp(0.65 - solitude * 0.35 + relaxation * 0.15)
    }
    mutating func notice() { attention = 1 }
}
