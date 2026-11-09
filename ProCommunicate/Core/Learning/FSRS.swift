import Foundation

/// How well you remembered a review card.
enum ReviewGrade: Int, CaseIterable, Sendable, Codable {
    case again = 1, hard = 2, good = 3, easy = 4

    var title: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

/// Memory state of one card.
struct MemoryState: Equatable, Sendable {
    /// Days until recall probability falls to 90%.
    var stability: Double
    /// 1 (easy) … 10 (hard).
    var difficulty: Double
}

/// The FSRS-4.5 spaced-repetition scheduler (Free Spaced Repetition Scheduler), with its published
/// default parameters. It predicts when you're about to forget a card and schedules it just before.
struct FSRS: Sendable {
    static let defaultWeights: [Double] = [
        0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474,
        0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755,
    ]
    static let decay = -0.5
    static let factor = 19.0 / 81.0

    var weights: [Double] = defaultWeights
    /// Target chance of remembering a card when it comes back.
    var desiredRetention: Double = 0.9
    var maximumIntervalDays: Double = 365

    private func w(_ index: Int) -> Double { weights[index] }

    /// Chance of remembering after `elapsedDays` with the given stability.
    func retrievability(elapsedDays: Double, stability: Double) -> Double {
        pow(1 + Self.factor * max(0, elapsedDays) / stability, Self.decay)
    }

    /// Days until the next review, for the target retention.
    func intervalDays(stability: Double) -> Double {
        let raw = stability / Self.factor * (pow(desiredRetention, 1 / Self.decay) - 1)
        return min(maximumIntervalDays, max(1, raw.rounded()))
    }

    func initialState(grade: ReviewGrade) -> MemoryState {
        MemoryState(stability: max(0.1, w(grade.rawValue - 1)),
                    difficulty: clampDifficulty(initialDifficulty(grade)))
    }

    /// The state after reviewing a card that was last seen `elapsedDays` ago.
    func next(_ state: MemoryState, grade: ReviewGrade, elapsedDays: Double) -> MemoryState {
        let r = retrievability(elapsedDays: elapsedDays, stability: state.stability)
        let difficulty = nextDifficulty(state.difficulty, grade: grade)
        let stability = grade == .again
            ? forgetStability(state, retrievability: r)
            : recallStability(state, grade: grade, retrievability: r)
        return MemoryState(stability: max(0.1, stability), difficulty: difficulty)
    }

    private func initialDifficulty(_ grade: ReviewGrade) -> Double {
        w(4) - Double(grade.rawValue - 3) * w(5)
    }

    private func nextDifficulty(_ d: Double, grade: ReviewGrade) -> Double {
        let changed = d - w(6) * Double(grade.rawValue - 3)
        let meanReverted = w(7) * initialDifficulty(.good) + (1 - w(7)) * changed
        return clampDifficulty(meanReverted)
    }

    private func clampDifficulty(_ d: Double) -> Double { min(10, max(1, d)) }

    private func recallStability(_ s: MemoryState, grade: ReviewGrade, retrievability r: Double) -> Double {
        let hardPenalty = grade == .hard ? w(15) : 1
        let easyBonus = grade == .easy ? w(16) : 1
        return s.stability * (exp(w(8)) * (11 - s.difficulty) * pow(s.stability, -w(9))
            * (exp(w(10) * (1 - r)) - 1) * hardPenalty * easyBonus + 1)
    }

    private func forgetStability(_ s: MemoryState, retrievability r: Double) -> Double {
        w(11) * pow(s.difficulty, -w(12)) * (pow(s.stability + 1, w(13)) - 1) * exp(w(14) * (1 - r))
    }
}
