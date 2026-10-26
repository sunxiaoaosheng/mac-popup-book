import Foundation

public struct FoldState {
    public private(set) var progress = 1.0
    public var target = 1.0
    public private(set) var openAngle = 105.0
    public private(set) var angle: Double?
    public private(set) var sensorAvailable = false
    public private(set) var stableDuration = 0.0
    public private(set) var clock = 0.0
    private var missingSince: Double?
    private var lastSampleTime: Double?
    public init() {}
    public static func openness(angle: Double, full: Double = 105) -> Double? {
        guard angle.isFinite, full.isFinite, (80...120).contains(full), (0...180).contains(angle) else {
            return nil
        }
        return clamp((angle - 35) / (full - 35))
    }
    @discardableResult public mutating func calibrate(_ angle: Double) -> Bool {
        guard angle.isFinite, (80...120).contains(angle) else { return false }
        openAngle = angle
        if let raw = self.angle { target = Self.openness(angle: raw, full: angle) ?? target }
        return true
    }
    public mutating func receive(_ sample: AngleSample) {
        guard sample.timestamp.isFinite, sample.timestamp >= (lastSampleTime ?? -.infinity) else { return }
        lastSampleTime = sample.timestamp
        if let angle = sample.angle, let p = Self.openness(angle: angle, full: openAngle) {
            self.angle = angle
            target = p
            sensorAvailable = true
            missingSince = nil
        } else {
            if missingSince == nil { missingSince = sample.timestamp }
            if sample.timestamp - (missingSince ?? sample.timestamp) >= 1 {
                sensorAvailable = false
                angle = nil
            }
        }
    }
    public mutating func advance(_ elapsed: Double) -> WorldContext {
        let dt = elapsed.isFinite ? clamp(elapsed, 0, 0.05) : 0
        clock += dt
        let previous = progress
        progress += (target - progress) * (1 - exp(-dt / 0.060))
        if abs(target - progress) < 0.0001 { progress = target }
        let speed = dt > 0 ? abs(progress - previous) / dt : 0
        if speed < 0.06 { stableDuration += dt } else { stableDuration = 0 }
        return WorldContext(progress: progress, clock: clock, deltaTime: dt, stableDuration: stableDuration)
    }
}
