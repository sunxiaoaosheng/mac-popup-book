import Foundation

public func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, x)) }
public func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}
public struct CharacterID: Hashable, Sendable {
    public let rawValue: String
    public init(_ value: String) { rawValue = value }
}
public struct AnchorID: Hashable, Sendable {
    public let rawValue: String
    public init(_ value: String) { rawValue = value }
    public static let entry = Self("entry")
    public static let resting = Self("resting")
    public static let peek = Self("peek")
}
public struct SoundID: Hashable, Sendable {
    public let rawValue: String
    public init(_ value: String) { rawValue = value }
}
public struct AngleSample: Sendable {
    public let angle: Double?
    public let timestamp: TimeInterval
    public init(angle: Double?, timestamp: TimeInterval) {
        self.angle = angle
        self.timestamp = timestamp
    }
}
public struct WorldContext: Sendable {
    public var progress: Double
    public var clock: Double
    public var deltaTime: Double
    public var stableDuration: Double
    public init(progress: Double, clock: Double, deltaTime: Double, stableDuration: Double) {
        self.progress = progress
        self.clock = clock
        self.deltaTime = deltaTime
        self.stableDuration = stableDuration
    }
}
public enum CharacterInteraction: Sendable { case greet }
public enum CharacterEvent: Equatable, Sendable { case restingInside, appearing, outside, returningInside }
public struct CharacterOutput<Pose> {
    public let pose: Pose
    public let caption: String
    public let events: [CharacterEvent]
    public let sounds: [SoundID]
    public init(pose: Pose, caption: String, events: [CharacterEvent], sounds: [SoundID] = []) {
        self.pose = pose
        self.caption = caption
        self.events = events
        self.sounds = sounds
    }
}
public enum BookConfigurationError: Error, LocalizedError {
    case missingAnchors(Set<AnchorID>)
    public var errorDescription: String? {
        switch self {
        case .missingAnchors(let anchors):
            return "场景缺少角色需要的位置：" + anchors.map(\.rawValue).sorted().joined(separator: "、")
        }
    }
}

public struct SceneGuidance {
    public let closedCaption: String
    public let initialCaption: String
    public let following: String
    public let manual: String
    public init(initialCaption: String, following: String, manual: String, closedCaption: String) {
        self.closedCaption = closedCaption
        self.initialCaption = initialCaption
        self.following = following
        self.manual = manual
    }
}
