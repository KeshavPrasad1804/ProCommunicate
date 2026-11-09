import Foundation
import SwiftData

/// One spoken turn in a call.
struct CallTurn: Codable, Sendable, Identifiable, Equatable {
    enum Speaker: String, Codable, Sendable { case ai, learner }

    var id = UUID()
    let speaker: Speaker
    var text: String
    /// Your recorded answer (Recordings folder), for learner turns.
    var clipFile: String?
    var seconds: Double = 0
    var longPauses = 0
    /// Instant pattern matches (no AI needed).
    var ruleHits: [StoredHit] = []
    /// The AI's check of this answer, once done.
    var check: AnswerCheck?
    var checkFailed = false

    struct StoredHit: Codable, Sendable, Equatable {
        let ruleId: String
        let wrong: String
    }

    var words: Int { FluencyMetrics.wordCount(text) }
}

/// A finished practice call and its numbers, saved on the phone.
@Model
final class CallRecord {
    @Attribute(.unique) var id: UUID
    var scenarioId: String
    var title: String
    var kind: String
    var startedAt: Date
    var seconds: Double
    var turnsData: Data
    var learnerWords: Int
    var learnerSeconds: Double
    var fillers: Int
    var longPauses: Int
    var mistakeCount: Int
    /// True while the AI is still checking answers in the background (the report fills in as it goes).
    var reportPending: Bool = false

    init(id: UUID = UUID(), scenarioId: String, title: String, kind: String, startedAt: Date, seconds: Double, turns: [CallTurn]) {
        self.id = id
        self.scenarioId = scenarioId
        self.title = title
        self.kind = kind
        self.startedAt = startedAt
        self.seconds = seconds
        self.turnsData = (try? JSONEncoder().encode(turns)) ?? Data()
        let learner = turns.filter { $0.speaker == .learner }
        self.learnerWords = learner.reduce(0) { $0 + $1.words }
        self.learnerSeconds = learner.reduce(0) { $0 + $1.seconds }
        self.fillers = learner.reduce(0) { $0 + FluencyMetrics.fillerCount($1.text) }
        self.longPauses = learner.reduce(0) { $0 + $1.longPauses }
        self.mistakeCount = learner.reduce(0) { $0 + $1.ruleHits.count + ($1.check?.mistakes.count ?? 0) }
    }

    /// Learner answers the AI hasn't checked yet.
    var uncheckedCount: Int { turns.filter { $0.speaker == .learner && $0.check == nil && !$0.checkFailed }.count }

    /// Saves updated turns (after background checks) and recounts mistakes.
    func update(turns newTurns: [CallTurn]) {
        turns = newTurns
        mistakeCount = newTurns.filter { $0.speaker == .learner }.reduce(0) { $0 + $1.ruleHits.count + ($1.check?.mistakes.count ?? 0) }
    }

    var turns: [CallTurn] {
        get { (try? JSONDecoder().decode([CallTurn].self, from: turnsData)) ?? [] }
        set { turnsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var wordsPerMinute: Double { FluencyMetrics.wordsPerMinute(words: learnerWords, seconds: learnerSeconds) }
    var fillersPerMinute: Double { learnerSeconds > 10 ? Double(fillers) / learnerSeconds * 60 : 0 }
}

/// A mistake you made, grouped by pattern, until you stop making it.
@Model
final class MistakeRecord {
    /// pattern + normalized wrong words, so repeats of the same mistake add up.
    @Attribute(.unique) var key: String
    /// A rule id from MistakeRules, or "grammar" / "style" for the AI's finds.
    var pattern: String
    var wrong: String
    var right: String
    var why: String
    /// Explanation in the learner's language when it was saved. (Stored under its original name so
    /// existing data keeps working.)
    var whyTamil: String?
    var count: Int
    var firstSeen: Date
    var lastSeen: Date
    /// Where you said it last (for playback), if recorded.
    var lastClipFile: String?
    var lastContext: String?

    init(pattern: String, wrong: String, right: String, why: String, whyNative: String?, date: Date = .now) {
        self.key = Self.key(pattern: pattern, wrong: wrong)
        self.pattern = pattern
        self.wrong = wrong
        self.right = right
        self.why = why
        self.whyTamil = whyNative
        self.count = 1
        self.firstSeen = date
        self.lastSeen = date
    }

    static func key(pattern: String, wrong: String) -> String {
        // Rule mistakes group by the rule; AI finds group by the exact words.
        MistakeRules.rule(pattern) != nil ? pattern : pattern + ":" + AnswerChecker.normalize(wrong)
    }

    var title: String { MistakeRules.rule(pattern)?.title ?? wrong }

    /// The explanation in the learner's current language: the rule's note for pattern mistakes,
    /// otherwise the one saved with the mistake.
    var whyNative: String? {
        get { MistakeRules.rule(pattern).flatMap { RuleNotes.text(for: $0.id) } ?? whyTamil }
        set { whyTamil = newValue }
    }
}
