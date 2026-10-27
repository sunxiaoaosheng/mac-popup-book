/// Pure page-local behavior; no host, rendering, hardware or persistence dependencies.
public struct Selection {
    public private(set) var value = 0.2
    public init() {}
    public mutating func select(_ x: Double) { if x.isFinite { value = min(1, max(0, x)) } }
}
