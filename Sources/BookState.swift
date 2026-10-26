import Foundation

func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, x)) }
func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t)
}
enum CatMood: String {
    case sleeping, waking, stretching, walking, resting, greeting, returning
    var label: String {
        switch self {
        case .sleeping: return "睡觉"
        case .waking: return "醒来"
        case .stretching: return "伸懒腰"
        case .walking: return "出门"
        case .resting: return "晒太阳"
        case .greeting: return "打招呼"
        case .returning: return "回屋"
        }
    }
}

/// Hardware-independent simulation. Advance with a monotonic clock; pause does not advance story time.
struct BookState {
    var progress = 1.0
    var target = 1.0
    var openAngle = 105.0
    var angle: Double?
    var sensorAvailable = false
    var sensorMissingSince: Double?
    var mood: CatMood = .sleeping
    var outside = 0.0
    var moodTime = 0.0
    var stableTime = 0.0
    var clock = 0.0
    var lastProgress = 1.0
    var blink = 0.0
    var didMeow = false
    var didRustle = false
    private var lastRustle = -10.0

    static func openness(angle: Double, full: Double = 105) -> Double? {
        guard angle.isFinite, full.isFinite, full >= 80, full <= 120,
              angle >= 0, angle <= 180 else { return nil }
        return clamp((angle - 35) / (full - 35))
    }
    mutating func calibrate(_ angle: Double) -> Bool {
        guard angle.isFinite, (80...120).contains(angle) else { return false }
        openAngle = angle; return true
    }
    mutating func receive(_ value: Double?, at time: Double) {
        if let value, let p = Self.openness(angle: value, full: openAngle) {
            angle = value; target = p; sensorAvailable = true; sensorMissingSince = nil
        } else {
            if sensorMissingSince == nil { sensorMissingSince = time }
            if time - (sensorMissingSince ?? time) >= 1 { sensorAvailable = false; angle = nil }
        }
    }
    mutating func greet() -> Bool {
        guard mood == .resting, progress >= 0.85, outside > 0.95 else { return false }
        mood = .greeting; moodTime = 0; return true
    }
    mutating func step(_ elapsed: Double) {
        let dt = clamp(elapsed, 0, 0.05)
        clock += dt; didMeow = false; didRustle = false
        lastProgress = progress
        progress += (target - progress) * (1 - exp(-dt / 0.060))
        if abs(target - progress) < 0.0001 { progress = target }
        let speed = dt > 0 ? abs(progress - lastProgress) / dt : 0
        if speed > 0.08, clock - lastRustle > 0.65 { didRustle = true; lastRustle = clock }
        if progress >= 0.85 && speed < 0.06 { stableTime += dt } else { stableTime = 0 }
        moodTime += dt
        // Close has priority over every character action; fast folds compress the return.
        if progress < 0.75 && mood != .sleeping && mood != .waking && mood != .returning {
            mood = .returning; moodTime = 0
        }
        switch mood {
        case .sleeping:
            outside = 0
            if progress > 0.45 { mood = .waking; moodTime = 0 }
        case .waking:
            if progress < 0.35 { mood = .sleeping; moodTime = 0 }
            else if stableTime >= 0.5 { mood = .stretching; moodTime = 0 }
        case .stretching:
            if moodTime >= 1.1 { mood = .walking; moodTime = 0 }
        case .walking:
            outside = min(1, outside + dt / 1.8)
            if outside >= 1 { mood = .resting; moodTime = 0 }
        case .resting: break
        case .greeting:
            if moodTime - dt < 0.18 && moodTime >= 0.18 { didMeow = true }
            if moodTime >= 1.15 { mood = .resting; moodTime = 0 }
        case .returning:
            // Reverse smoothly from the current position, never reset to an endpoint.
            if progress > 0.85 && stableTime >= 0.5 { mood = .walking; moodTime = 0 }
            else {
                let duration = max(0.16, 1.25 * smoothstep(0.3, 0.75, progress))
                outside = max(0, outside - dt / duration)
                if outside <= 0 { mood = progress > 0.4 ? .waking : .sleeping; moodTime = 0 }
            }
        }
        blink = pow(max(0, sin(clock * 0.67)), 48)
    }
    var caption: String {
        if progress < 0.12 { return "把森林，轻轻收进口袋。" }
        switch mood {
        case .sleeping, .waking: return "嘘，窗边的小猫还在做梦。"
        case .stretching: return "伸个懒腰，今天也是好天气。"
        case .walking: return "门开了。有个小家伙想见你。"
        case .resting: return "阳光正好。点点小猫，和它打个招呼。"
        case .greeting: return "喵。很高兴你来了。"
        case .returning: return "再见之前，留一盏小灯。"
        }
    }
}
