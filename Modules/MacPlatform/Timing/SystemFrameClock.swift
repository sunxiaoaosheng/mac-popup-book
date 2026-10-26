import AppKit
import PopupBookCore

@MainActor public final class SystemFrameClock: FrameClock {
    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var timer: Timer?
    public init() {}
    public func start(_ onFrame: @escaping @MainActor (TimeInterval) -> Void) {
        stop()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { onFrame(ProcessInfo.processInfo.systemUptime) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    deinit { timer?.invalidate() }
}
