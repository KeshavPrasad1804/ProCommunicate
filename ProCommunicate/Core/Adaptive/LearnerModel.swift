import Foundation

/// Which track to put first.
enum LearningFocus: String, Codable, CaseIterable, Sendable, Identifiable {
    case meetings, interviews, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meetings: "Client meetings first"
        case .interviews: "Job interviews first"
        case .both: "Both, mixed"
        }
    }

    var shortTitle: String {
        switch self {
        case .meetings: "client meetings"
        case .interviews: "job interviews"
        case .both: "meetings & interviews"
        }
    }

    /// Quick guess from the "preparing for" text when the AI hasn't classified it yet.
    static func guess(from target: String) -> LearningFocus {
        let text = target.lowercased()
        let interview = ["interview", "job", "switch", "hr round", "offer", "hike", "new role", "placement", "naukri"].contains { text.contains($0) }
        let meeting = ["client", "meeting", "call", "stand-up", "standup", "stakeholder", "onsite", "present", "demo", "scrum"].contains { text.contains($0) }
        switch (interview, meeting) {
        case (true, false): return .interviews
        case (false, true): return .meetings
        case (true, true): return .both
        default: return .meetings
        }
    }
}

/// How well you know one unit, 0…1, and where that comes from.
struct UnitMastery: Equatable, Sendable {
    let unitId: String
    /// Best first-try lesson score (0 if not done).
    var lesson: Double = 0
    /// How well you currently remember the unit's review cards (0 if none).
    var memory: Double = 0
    /// How few mistakes you make in this unit's calls (nil if no call yet).
    var calls: Double?
    var lastPracticed: Date?

    var started: Bool { lastPracticed != nil }

    /// Weighted: lesson 40%, memory 30%, calls 30% (or lesson 55% / memory 45% before any call).
    var score: Double {
        if let calls { return 0.4 * lesson + 0.3 * memory + 0.3 * calls }
        return 0.55 * lesson + 0.45 * memory
    }
}

/// Everything the planner needs about you, built from what's saved on the phone.
struct LearnerSnapshot: Sendable {
    var mastery: [String: UnitMastery]
    var focus: LearningFocus
    /// Rule-pattern mistakes in the last 14 days: rule id → times.
    var recentPatterns: [String: Int]
    /// From the speaking check: 0 = beginner … 2 = confident.
    var level: Int
    /// Completed calls by kind, with their average mistakes per answer.
    var callStats: [CallScenario.Kind: (count: Int, mistakesPerAnswer: Double)]
    var upcoming: UpcomingEventInfo?
    /// Finished calls per scenario id.
    var scenarioCounts: [String: Int] = [:]

    func mastery(of unitId: String) -> UnitMastery { mastery[unitId] ?? UnitMastery(unitId: unitId) }
}

/// A real meeting or interview coming up (from "I have a meeting tomorrow").
struct UpcomingEventInfo: Sendable, Equatable {
    let title: String
    let who: String
    let date: Date
    let phrases: [String]
}

enum LearnerModel {
    /// Days for a skill to fade halfway if you don't practise it.
    static let halfLifeDays = 21.0

    /// Builds the learner snapshot. Pure function of the saved data, so it's quick and testable.
    @MainActor
    static func snapshot(course: Course, lessons: [Lesson], progress: [LessonProgressRecord], cards: [ReviewCard],
                         calls: [CallRecord], mistakes: [MistakeRecord], focus: LearningFocus, level: Int,
                         upcoming: UpcomingEventInfo?, scenarios: [CallScenario], now: Date = .now) -> LearnerSnapshot {
        var mastery: [String: UnitMastery] = [:]
        let lessonByUnit = Dictionary(lessons.map { ($0.unitId, $0) }, uniquingKeysWith: { a, _ in a })
        let scheduler = FSRS()

        for unit in course.tracks.flatMap(\.units) {
            var m = UnitMastery(unitId: unit.id)
            if let lesson = lessonByUnit[unit.id] {
                if let record = progress.first(where: { $0.lessonId == lesson.id }) {
                    m.lesson = record.bestScore
                    m.lastPracticed = record.lastCompletedAt
                }
                let unitCards = cards.filter { $0.lessonId == lesson.id }
                if !unitCards.isEmpty {
                    let recall = unitCards.map { card -> Double in
                        guard let last = card.lastReview, card.stability > 0 else { return card.isNew ? 0.5 : 0 }
                        return scheduler.retrievability(elapsedDays: now.timeIntervalSince(last) / 86_400, stability: card.stability)
                    }
                    m.memory = recall.reduce(0, +) / Double(recall.count)
                    if let latest = unitCards.compactMap(\.lastReview).max() {
                        m.lastPracticed = max(m.lastPracticed ?? latest, latest)
                    }
                }
            }
            let unitScenarioIds = Set(scenarios.filter { $0.unitId == unit.id }.map(\.id) + ["unit-\(unit.id)"])
            let unitCalls = calls.filter { unitScenarioIds.contains($0.scenarioId) && !$0.reportPending }
            if !unitCalls.isEmpty {
                let perAnswer = unitCalls.map { call -> Double in
                    let answers = max(1, call.turns.filter { $0.speaker == .learner }.count)
                    return Double(call.mistakeCount) / Double(answers)
                }
                let average = perAnswer.reduce(0, +) / Double(perAnswer.count)
                m.calls = max(0, 1 - average / 2)     // 0 mistakes/answer = 1.0, 2+ = 0
                if let latest = unitCalls.map(\.startedAt).max() { m.lastPracticed = max(m.lastPracticed ?? latest, latest) }
            }
            // Fade with time since you last practised.
            if let last = m.lastPracticed {
                let days = now.timeIntervalSince(last) / 86_400
                let fade = pow(0.5, max(0, days - 3) / halfLifeDays)
                m.lesson *= fade
                if let c = m.calls { m.calls = c * fade }
            }
            mastery[unit.id] = m
        }

        var patterns: [String: Int] = [:]
        for mistake in mistakes where now.timeIntervalSince(mistake.lastSeen) < 14 * 86_400 && MistakeRules.rule(mistake.pattern) != nil {
            patterns[mistake.pattern, default: 0] += mistake.count
        }

        var callStats: [CallScenario.Kind: (count: Int, mistakesPerAnswer: Double)] = [:]
        for kind in [CallScenario.Kind.quick, .meeting, .interview] {
            let done = calls.filter { $0.kind == kind.rawValue && !$0.reportPending }
            guard !done.isEmpty else { continue }
            let rate = done.map { Double($0.mistakeCount) / Double(max(1, $0.turns.filter { $0.speaker == .learner }.count)) }
            callStats[kind] = (done.count, rate.reduce(0, +) / Double(rate.count))
        }

        var counts: [String: Int] = [:]
        for call in calls { counts[call.scenarioId, default: 0] += 1 }

        return LearnerSnapshot(mastery: mastery, focus: focus, recentPatterns: patterns, level: level,
                               callStats: callStats, upcoming: upcoming, scenarioCounts: counts)
    }

    /// 0 = beginner, 1 = intermediate, 2 = confident, from the speaking check.
    static func level(speakingCheckWPM: Double, speakingCheckMistakes: Int) -> Int {
        guard speakingCheckMistakes >= 0 else { return 1 }
        if speakingCheckMistakes >= 3 || speakingCheckWPM < 80 { return 0 }
        if speakingCheckMistakes >= 1 { return 1 }
        return 2
    }
}

extension MistakeRules {
    /// The unit that teaches the fix for each pattern.
    static let teachingUnit: [String: String] = [
        "myself-intro": "interviews-01-about-you",
        "am-having": "interviews-01-about-you",
        "since-continuous": "interviews-02-current-role",
        "revert-back": "meetings-06-get-back",
        "revert-to-me": "meetings-06-get-back",
        "itself": "meetings-09-negotiate",
        "do-the-needful": "meetings-05-clarify",
        "discuss-about": "meetings-12-closing",
        "doubt-question": "meetings-05-clarify",
        "prepone": "meetings-09-negotiate",
        "good-name": "meetings-02-opening",
        "cousin-brother": "meetings-02-opening",
        "passed-out": "interviews-01-about-you",
        "updation": "meetings-03-status",
        "the-same": "meetings-12-closing",
        "out-of-station": "meetings-02-opening",
        "my-native": "interviews-01-about-you",
        "do-one-thing": "meetings-05-clarify",
        "only-emphasis": "meetings-03-status",
        "did-past": "meetings-01-standup",
        "more-better": "interviews-06-strengths",
    ]
}
