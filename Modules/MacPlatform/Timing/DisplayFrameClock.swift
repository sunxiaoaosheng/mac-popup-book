import Foundation
import PopupBookCore

/// A single host display drives all pages. No worker owns a business timer.
@MainActor public final class DisplayFrameClock: FrameClock {
    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var callback: ((TimeInterval) -> Void)?
    public init() {}
    public func start(_ onFrame: @escaping @MainActor (TimeInterval) -> Void) { callback = onFrame }
    public func pulse() { callback?(now) }
    public func stop() { callback = nil }
}
