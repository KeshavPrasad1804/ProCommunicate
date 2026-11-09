import Foundation

/// How hard the AI makes a call.
enum CallDifficulty: String, Codable, Sendable, CaseIterable {
    case gentle, standard, challenging

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .standard: "Standard"
        case .challenging: "Challenging"
        }
    }

    /// Added to the AI's role instructions.
    var instruction: String? {
        switch self {
        case .gentle:
            "Difficulty: gentle. Speak slowly and simply, use common words, be patient and warm, and give the learner time. Ask one clear question at a time."
        case .standard:
            nil
        case .challenging:
            "Difficulty: challenging. Be realistic and demanding: ask at least one tough follow-up, push back politely once on what they say, and once ask them to be more specific or give a number."
        }
    }
}

/// Today's lesson choice and why.
struct LessonPick: Equatable, Sendable {
    enum Kind: String, Sendable { case fix, refresh, new, strengthen, keepFresh }
    let unitId: String
    let kind: Kind
    let reason: String
}

/// Chooses what to practise from the learner model. Pure and quick: no AI, no disk, so it runs on
/// every screen refresh and is easy to test. The AI only writes content for these choices (see AdaptiveJobs).
enum AdaptivePlanner {
    /// At or above this, a unit counts as mastered and is skipped.
    static let masteredScore = 0.85
    /// Below this, a unit you've done needs a refresh.
    static let weakScore = 0.45

    // MARK: - Unit order

    /// The course's units in the order your focus asks for.
    static func unitOrder(_ course: Course, focus: LearningFocus) -> [CourseUnit] {
        let meetings = course.tracks.first { $0.id == "meetings" }?.units ?? []
        let interviews = course.tracks.first { $0.id == "interviews" }?.units ?? []
        let others = course.tracksByPriority.filter { $0.id != "meetings" && $0.id != "interviews" }.flatMap(\.units)
        switch focus {
        case .meetings: return meetings + interviews + others
        case .interviews: return interviews + meetings + others
        case .both:
            var mixed: [CourseUnit] = []
            for i in 0..<max(meetings.count, interviews.count) {
                if i < meetings.count { mixed.append(meetings[i]) }
                if i < interviews.count { mixed.append(interviews[i]) }
            }
            return mixed + others
        }
    }

    // MARK: - Today's lesson

    /// 1. A mistake you keep making → the unit that fixes it.
    /// 2. A unit you did that has faded → refresh it.
    /// 3. The next new unit in your focus order (mastered ones are skipped).
    /// 4. Your weakest unit that isn't mastered yet.
    /// 5. Everything mastered → the unit that has faded most.
    static func pickLesson(snapshot: LearnerSnapshot, order: [CourseUnit], available: Set<String>,
                           now: Date = .now) -> LessonPick? {
        let units = order.filter { available.contains($0.id) }
        guard !units.isEmpty else { return nil }
        let titles = Dictionary(units.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        func daysSince(_ unitId: String) -> Double {
            guard let last = snapshot.mastery(of: unitId).lastPracticed else { return .infinity }
            return now.timeIntervalSince(last) / 86_400
        }

        // 1. Recurring mistakes, most frequent first. Give a fix lesson 3 days to work before repeating it.
        let recurring = snapshot.recentPatterns.filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        for (pattern, count) in recurring {
            guard let unitId = MistakeRules.teachingUnit[pattern], titles[unitId] != nil, daysSince(unitId) >= 3 else { continue }
            let mastery = snapshot.mastery(of: unitId)
            guard mastery.score < masteredScore || count >= 3 else { continue }
            let name = MistakeRules.rule(pattern)?.title ?? pattern
            return LessonPick(unitId: unitId, kind: .fix,
                              reason: "Fixes a mistake you keep making: \(name) (\(count)× in 2 weeks).")
        }

        // 2. A started unit that has faded (not touched in the last 2 days).
        let faded = units.filter { snapshot.mastery(of: $0.id).started && snapshot.mastery(of: $0.id).score < weakScore && daysSince($0.id) >= 2 }
            .min { snapshot.mastery(of: $0.id).score < snapshot.mastery(of: $1.id).score }
        if let faded {
            let percent = Int((snapshot.mastery(of: faded.id).score * 100).rounded())
            return LessonPick(unitId: faded.id, kind: .refresh, reason: "Refresh: this one has slipped to \(percent)%.")
        }

        // 3. Next new unit in focus order.
        if let new = units.first(where: { !snapshot.mastery(of: $0.id).started }) {
            let track = new.id.hasPrefix("interviews") ? "interviews" : "meetings"
            let reason = switch snapshot.focus {
            case .both: "Next new skill. You're working on meetings and interviews together."
            default: "Next new skill for \(track), your focus."
            }
            return LessonPick(unitId: new.id, kind: .new, reason: reason)
        }

        // 4. Weakest unit that isn't mastered.
        let notMastered = units.filter { snapshot.mastery(of: $0.id).score < masteredScore && daysSince($0.id) >= 1 }
        if let weakest = notMastered.min(by: { snapshot.mastery(of: $0.id).score < snapshot.mastery(of: $1.id).score }) {
            let percent = Int((snapshot.mastery(of: weakest.id).score * 100).rounded())
            return LessonPick(unitId: weakest.id, kind: .strengthen, reason: "Your weakest skill right now (\(percent)%).")
        }

        // 5. All mastered: keep the most faded one fresh.
        let oldest = units.max { daysSince($0.id) < daysSince($1.id) } ?? units[0]
        return LessonPick(unitId: oldest.id, kind: .keepFresh, reason: "Everything's strong. Keeping this one fresh.")
    }

    // MARK: - Today's call

    /// Rehearse a real meeting that's today or tomorrow; otherwise use today's lesson in a role-play.
    static func pickCall(lessonUnit: CourseUnit?, lessonKind: LessonPick.Kind?, upcoming: UpcomingEventInfo?,
                         scenarios: [CallScenario], now: Date = .now) -> (scenario: CallScenario, reason: String, extra: String?)? {
        if let upcoming, let when = eventDayLabel(upcoming.date, now: now), when == "today" || when == "tomorrow" {
            let scenario = ScenarioLoader.rehearsal(description: upcoming.title, who: upcoming.who)
            let extra = upcoming.phrases.isEmpty ? nil : "Phrases the learner wants to practise: " + upcoming.phrases.joined(separator: " | ")
            return (scenario, "Rehearse your real meeting \(when): \(upcoming.title)", extra)
        }
        if let lessonUnit {
            let reason = lessonKind == .fix ? "Use the fix in a real conversation." : "Use today's lesson in a real conversation."
            return (ScenarioLoader.forUnit(lessonUnit, all: scenarios), reason, nil)
        }
        return scenarios.first { $0.id == "quick-status" }.map { ($0, "A quick status update.", nil) }
    }

    /// "today", "tomorrow", "in 3 days", or nil if it's past or more than two weeks away.
    static func eventDayLabel(_ date: Date, now: Date = .now) -> String? {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? -1
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...14: return "in \(days) days"
        default: return nil
        }
    }

    // MARK: - Weekly challenge

    /// Interviews if that's your focus, meetings if that's yours; with both, whichever you've done
    /// less (or do worse at).
    static func weeklyKind(snapshot: LearnerSnapshot, week: Int) -> CallScenario.Kind {
        switch snapshot.focus {
        case .meetings: return .meeting
        case .interviews: return .interview
        case .both:
            let m = snapshot.callStats[.meeting], i = snapshot.callStats[.interview]
            let mCount = m?.count ?? 0, iCount = i?.count ?? 0
            if mCount != iCount { return mCount < iCount ? .meeting : .interview }
            if let m, let i, abs(m.mistakesPerAnswer - i.mistakesPerAnswer) > 0.2 {
                return m.mistakesPerAnswer > i.mistakesPerAnswer ? .meeting : .interview
            }
            return week.isMultiple(of: 2) ? .meeting : .interview
        }
    }

    /// Harder as you improve: from your mistakes per answer in calls of this kind.
    static func difficulty(for kind: CallScenario.Kind, snapshot: LearnerSnapshot) -> CallDifficulty {
        guard let stats = snapshot.callStats[kind] ?? snapshot.callStats[.quick] else {
            return snapshot.level == 0 ? .gentle : .standard
        }
        if stats.count >= 2 && stats.mistakesPerAnswer < 0.5 { return .challenging }
        if stats.mistakesPerAnswer < 1.2 { return .standard }
        return .gentle
    }

    /// The scenario of that kind you've done least, rotating by week among equals.
    static func weeklyScenario(kind: CallScenario.Kind, scenarios: [CallScenario], snapshot: LearnerSnapshot, week: Int) -> CallScenario? {
        let options = scenarios.filter { $0.kind == kind }
        guard !options.isEmpty else { return nil }
        let indexed = options.enumerated().map { (offset: $0.offset, scenario: $0.element) }
        return indexed.min { a, b in
            let ca = snapshot.scenarioCounts[a.scenario.id] ?? 0, cb = snapshot.scenarioCounts[b.scenario.id] ?? 0
            if ca != cb { return ca < cb }
            return (a.offset - week).mod(options.count) < (b.offset - week).mod(options.count)
        }?.scenario
    }

    // MARK: - Phrase of the day

    /// The unit to take the phrase of the day from: your weakest started unit, or today's lesson.
    static func phraseUnit(snapshot: LearnerSnapshot, order: [CourseUnit], lessonUnitId: String?) -> String? {
        let started = order.filter { snapshot.mastery(of: $0.id).started && snapshot.mastery(of: $0.id).score < masteredScore }
        if let weakest = started.min(by: { snapshot.mastery(of: $0.id).score < snapshot.mastery(of: $1.id).score }) {
            return weakest.id
        }
        return lessonUnitId ?? order.first?.id
    }

    // MARK: - Keys

    static func dayKey(_ date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func weekKey(_ date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }
}

extension CallScenario {
    /// A copy with a different difficulty (and, optionally, AI-written details).
    func adapted(difficulty: CallDifficulty, title: String? = nil, subtitle: String? = nil, situation: String? = nil,
                 goals: [String]? = nil, opening: String? = nil, idSuffix: String = "") -> CallScenario {
        var text = situation ?? self.situation
        if let instruction = difficulty.instruction { text += " " + instruction }
        return CallScenario(id: id + idSuffix, kind: kind, unitId: unitId, title: title ?? self.title,
                            subtitle: subtitle ?? self.subtitle, aiName: aiName, aiRole: aiRole, voice: voice,
                            maxTurns: maxTurns, goals: goals ?? self.goals, situation: text, opening: opening ?? self.opening)
    }
}

private extension Int {
    func mod(_ n: Int) -> Int { ((self % n) + n) % n }
}
