import Foundation
import PopupBookCore

/// Weighted variety with explicit rest periods; choices are deterministic when seeded.
struct CatDailyRhythm {
    var random: any RandomSource
    private var recent: [CatMood] = []
    private(set) var nextAction = 18.0
    private(set) var lastInvitation = -60.0
    init(random: any RandomSource) { self.random = random }
    mutating func choose(at time: Double) -> (CatMood, Double) {
        let pool: [CatMood] = [.observing, .grooming, .stretching, .settling, .strolling, .resting]
        let choices = pool.filter { !recent.contains($0) }
        let mood = choices[min(choices.count - 1, Int(random.nextUnit() * Double(choices.count)))]
        recent.append(mood)
        recent = Array(recent.suffix(2))
        let duration = mood == .resting ? 15 + random.nextUnit() * 20 : 3 + random.nextUnit() * 3
        nextAction = time + duration + 8 + random.nextUnit() * 10
        return (mood, duration)
    }
    mutating func postpone(after time: Double) { nextAction = max(nextAction, time + 8) }
    mutating func invite(at time: Double) { lastInvitation = time }
}
