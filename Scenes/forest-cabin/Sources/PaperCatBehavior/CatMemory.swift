import Foundation
import PopupBookCore

/// Only meaningful summaries are durable; no raw pointer trace or offline punishment.
public struct CatMemory: Codable, Equatable {
    public private(set) var version = 1
    public private(set) var meetings = 0
    public private(set) var lastMeeting: Date?
    public private(set) var effectiveTouches = 0
    public private(set) var quietMoments = 0
    private var touchWindow: Date?
    private var touchWindowCredits = 0
    private var lastQuietMoment: Date?
    public var prefersQuiet: Bool { quietMoments > effectiveTouches }
    public var familiarity: Double { min(1, Double(meetings) * 0.08 + Double(effectiveTouches) * 0.025) }
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case version, meetings, lastMeeting, effectiveTouches, quietMoments
        case touchWindow, touchWindowCredits, lastQuietMoment
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version == 1 else { throw StateRestoreError.unsupportedVersion(version) }
        meetings = try values.decode(Int.self, forKey: .meetings)
        lastMeeting = try values.decodeIfPresent(Date.self, forKey: .lastMeeting)
        effectiveTouches = try values.decode(Int.self, forKey: .effectiveTouches)
        quietMoments = try values.decode(Int.self, forKey: .quietMoments)
        touchWindow = try values.decodeIfPresent(Date.self, forKey: .touchWindow) ?? lastMeeting
        touchWindowCredits =
            try values.decodeIfPresent(Int.self, forKey: .touchWindowCredits) ?? min(3, effectiveTouches)
        lastQuietMoment = try values.decodeIfPresent(Date.self, forKey: .lastQuietMoment)
    }
    mutating func recordMeeting(at date: Date) -> Bool {
        guard date.timeIntervalSince1970.isFinite else { return false }
        if let lastMeeting, date.timeIntervalSince(lastMeeting) < 1800 { return false }
        meetings = min(meetings + 1, 10000)
        lastMeeting = date
        return true
    }
    mutating func recordTouch(at date: Date) -> Bool {
        if touchWindow == nil || date.timeIntervalSince(touchWindow ?? date) >= 1800 {
            touchWindow = date
            touchWindowCredits = 0
        }
        guard touchWindowCredits < 3 else { return false }
        effectiveTouches = min(effectiveTouches + 1, 30000)
        touchWindowCredits += 1
        return true
    }
    mutating func recordQuiet(at date: Date) {
        if let lastQuietMoment, date.timeIntervalSince(lastQuietMoment) < 1800 { return }
        quietMoments = min(quietMoments + 1, 10000)
        lastQuietMoment = date
    }
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }
    static func decoded(_ data: Data) throws -> Self {
        struct Version: Decodable { let version: Int }
        let decoder = JSONDecoder()
        let version = try decoder.decode(Version.self, from: data).version
        guard version == 1 else { throw StateRestoreError.unsupportedVersion(version) }
        let memory = try decoder.decode(Self.self, from: data)
        guard memory.meetings >= 0, memory.meetings <= 10000,
            memory.effectiveTouches >= 0, memory.effectiveTouches <= 30000,
            memory.quietMoments >= 0, memory.quietMoments <= 10000,
            (0...3).contains(memory.touchWindowCredits),
            memory.touchWindow?.timeIntervalSince1970.isFinite ?? true,
            memory.lastQuietMoment?.timeIntervalSince1970.isFinite ?? true,
            memory.lastMeeting?.timeIntervalSince1970.isFinite ?? true
        else {
            throw StateRestoreError.invalidState
        }
        return memory
    }
}
