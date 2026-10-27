import Foundation

/// Renderer-independent interpretation in logical points, not display pixels.
public struct ContactGesture {
    private var origin: (Double, Double)?
    private var last: (Double, Double)?
    private var began = 0.0, lastTime = 0.0, distance = 0.0
    public var isActive: Bool { origin != nil }
    public init() {}
    public mutating func begin(x: Double, y: Double, time: Double, point: ContactPoint)
        -> [CharacterInteraction]
    {
        guard x.isFinite, y.isFinite, time.isFinite else { return [] }
        origin = (x, y)
        last = (x, y)
        began = time
        lastTime = time
        distance = 0
        return [.contactBegan(point)]
    }
    public mutating func move(x: Double, y: Double, time: Double, point: ContactPoint)
        -> [CharacterInteraction]
    {
        guard let last, let origin, x.isFinite, y.isFinite, time.isFinite, time >= lastTime else { return [] }
        distance = max(distance, hypot(x - origin.0, y - origin.1))
        let interval = time - lastTime
        let speed = interval > 0 ? hypot(x - last.0, y - last.1) / interval : 0
        self.last = (x, y)
        lastTime = time
        let intensity = speed >= 10 && speed <= 220 ? min(1, speed / 100) : 0
        return [.contactMoved(point, intensity: intensity)]
    }
    public mutating func end(time: Double) -> [CharacterInteraction] {
        guard origin != nil else { return [] }
        let click = time.isFinite && time >= began && time - began <= 0.3 && distance <= 6
        reset()
        return click ? [.contactEnded, .greet] : [.contactEnded]
    }
    public mutating func cancel() -> [CharacterInteraction] {
        guard origin != nil else { return [] }
        reset()
        return [.contactEnded]
    }
    private mutating func reset() {
        origin = nil
        last = nil
    }
}
