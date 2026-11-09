import Foundation
import Observation
import UIKit

/// What the AI needs to personalise today's content. Built by Today from the planner's choices.
struct AdaptiveJobInputs: Equatable, Sendable {
    struct UnitBrief: Equatable, Sendable {
        let id: String
        let title: String
        let goal: String
        let examples: [String]
    }

    var profile: LearnerProfile
    var day: String
    var week: String
    var phraseUnit: UnitBrief?
    var weeklyBase: CallScenario?
    /// Titles of your most repeated mistakes.
    var weakSpots: [String]
}

/// Uses the on-device AI, when the phone is free, to write content for you and cache it:
/// - reads your goal ("preparing for") once to choose meetings, interviews or both, and spots a dated event;
/// - writes a phrase of the day for your real job, once a day;
/// - writes this week's challenge call around your project and weak spots, once a week.
///
/// Rules: only while the app is open (iPhones don't allow GPU work in the background), never during a
/// call or while a report is being checked, one short job at a time, and the AI's memory is freed afterwards.
@MainActor @Observable
final class AdaptiveJobs {
    static let shared = AdaptiveJobs()

    /// What the AI is writing right now (shown quietly on Today), or nil.
    private(set) var working: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var failures: [String: Int] = [:]
    @ObservationIgnored var store: AdaptiveStore = .shared

    enum Job: Equatable {
        case focus(target: String)
        case phrase(AdaptiveJobInputs.UnitBrief)
        case weekly(CallScenario)

        var label: String {
            switch self {
            case .focus: "Reading your goal…"
            case .phrase: "Writing your phrase of the day…"
            case .weekly: "Writing this week's challenge for your job…"
            }
        }
    }

    /// The jobs whose cached result is missing or out of date.
    func pendingJobs(_ inputs: AdaptiveJobInputs) -> [Job] {
        let content = store.content
        var jobs: [Job] = []
        let target = inputs.profile.target.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.isEmpty && content.aiFocus?.target != target { jobs.append(.focus(target: target)) }
        if let unit = inputs.phraseUnit, content.phrase?.day != inputs.day { jobs.append(.phrase(unit)) }
        if let base = inputs.weeklyBase, content.weekly?.week != inputs.week || content.weekly?.baseScenarioId != base.id {
            jobs.append(.weekly(base))
        }
        return jobs.filter { (failures[key($0, inputs)] ?? 0) < 2 }
    }

    /// Starts the jobs that are due, a few seconds from now, if the AI is on and the phone is free.
    func schedule(_ inputs: AdaptiveJobInputs) {
        guard task == nil, UserDefaults.standard.bool(forKey: SettingsKey.aiTutorEnabled), TutorService.isAvailable else { return }
        let jobs = pendingJobs(inputs)
        guard !jobs.isEmpty else { return }
        task = Task { [weak self] in
            await self?.run(jobs, inputs: inputs)
            self?.task = nil
        }
    }

    private var isFree: Bool {
        UIApplication.shared.applicationState == .active
            && !ReportProcessor.shared.callInProgress && !ReportProcessor.shared.isWorking
    }

    private func run(_ jobs: [Job], inputs: AdaptiveJobInputs) async {
        // Let the screen settle first, so this never competes with what you just opened.
        try? await Task.sleep(for: .seconds(4))
        guard isFree else { return }
        let wasLoaded = await LlamaEngine.shared.isLoaded()
        defer { working = nil }
        for job in jobs {
            guard isFree else { break }
            working = job.label
            do {
                try await perform(job, inputs: inputs)
            } catch LlamaError.cancelled {
                break   // a call started or you left the app: try again next time
            } catch {
                failures[key(job, inputs), default: 0] += 1
            }
        }
        working = nil
        if !wasLoaded && isFree { await LlamaEngine.shared.unload() }
    }

    private func key(_ job: Job, _ inputs: AdaptiveJobInputs) -> String {
        switch job {
        case .focus(let target): "focus:\(target)"
        case .phrase: "phrase:\(inputs.day)"
        case .weekly(let base): "weekly:\(inputs.week):\(base.id)"
        }
    }

    // MARK: - Running one job

    private func perform(_ job: Job, inputs: AdaptiveJobInputs) async throws {
        switch job {
        case .focus(let target):
            let raw = try await generate(system: AdaptivePrompts.focusSystem, user: AdaptivePrompts.focusUser(target: target),
                                         grammar: AdaptivePrompts.focusGrammar, maxTokens: 120)
            var result = try AdaptivePrompts.parseFocus(raw)
            // The small model is unreliable at counting days; plain date words are read by rules first.
            if let days = EventDate.days(in: target) { result = .init(focus: result.focus, event: result.event, days: days) }
            // If the goal clearly names both, keep both even if the AI picked one.
            let focus = LearningFocus.guess(from: target) == .both ? .both : result.focus
            store.update { $0.aiFocus = .init(target: target, focus: focus) }
            if let event = result.event(now: .now) { store.addEvent(event) }

        case .phrase(let unit):
            let raw = try await generate(system: AdaptivePrompts.writerSystem,
                                         user: AdaptivePrompts.phraseUser(profile: inputs.profile, unit: unit, weakSpots: inputs.weakSpots),
                                         grammar: AdaptivePrompts.phraseGrammar, maxTokens: 260)
            let phrase = try AdaptivePrompts.parsePhrase(raw, day: inputs.day, unitId: unit.id)
            store.update { $0.phrase = phrase }

        case .weekly(let base):
            let raw = try await generate(system: AdaptivePrompts.writerSystem,
                                         user: AdaptivePrompts.weeklyUser(profile: inputs.profile, base: base, weakSpots: inputs.weakSpots),
                                         grammar: AdaptivePrompts.weeklyGrammar, maxTokens: 450)
            let weekly = try AdaptivePrompts.parseWeekly(raw, week: inputs.week, base: base)
            store.update { $0.weekly = weekly }
        }
    }

    /// One grammar-constrained generation that stops if the phone gets busy, or after 90 seconds.
    private func generate(system: String, user: String, grammar: String, maxTokens: Int) async throws -> String {
        let watcher = Task { [weak self] in
            let started = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                if !self.isFree || Date.now.timeIntervalSince(started) > 90 {
                    LlamaEngine.shared.cancelCurrent()
                    return
                }
            }
        }
        defer { watcher.cancel() }
        return try await TutorService.json(system: system, user: user, grammar: grammar, maxTokens: maxTokens)
    }
}

// MARK: - Prompts

enum AdaptivePromptError: Error { case badOutput }

enum AdaptivePrompts {
    private static let string = #"""
    string ::= "\"" char{1,300} "\""
    char ::= [^"\\\x7F\x00-\x1F] | "\\" ( ["\\/bfnrt] | "u" [0-9a-fA-F]{4} )
    ws ::= [ \t\n]{0,10}
    """#

    static let banned = "Never use Indian-English phrases like revert back, do the needful, prepone, today itself, discuss about or \"I have one doubt\"."

    // Focus

    static let focusSystem = "You read a learner's goal and classify it. Reply only with the JSON."

    static func focusUser(target: String, now: Date = .now) -> String {
        """
        The learner's goal (English, Tamil or Tanglish): "\(target)"
        Today is \(now.formatted(.dateTime.weekday(.wide).day().month(.wide).year())).
        "focus": "interviews" if it is only about job interviews or changing jobs, "meetings" if it is only about meetings, calls or work at their current job, "both" if it mentions both.
        "event": if the goal mentions ONE specific upcoming meeting, presentation or interview, a short title for it in English (at most 8 words), otherwise "".
        "days": how many days from today until that event, or -1 if not known. Tamil time words: naalaikku or naalai = tomorrow (1), inniki or indru = today (0), naalanniki = day after tomorrow (2), adutha vaaram = next week (7).
        """
    }

    static let focusGrammar = #"""
    root ::= "{" ws "\"focus\":" ws focus ws "," ws "\"event\":" ws optstring ws "," ws "\"days\":" ws days ws "}"
    focus ::= "\"meetings\"" | "\"interviews\"" | "\"both\""
    optstring ::= "\"" char{0,80} "\""
    days ::= "-1" | [0-9] | [1-5] [0-9] | "60"
    char ::= [^"\\\x7F\x00-\x1F] | "\\" ( ["\\/bfnrt] | "u" [0-9a-fA-F]{4} )
    ws ::= [ \t\n]{0,10}
    """#

    struct FocusOutput: Codable, Equatable {
        let focus: LearningFocus
        let event: String
        let days: Int

        func event(now: Date) -> AdaptiveContent.UpcomingEvent? {
            let title = event.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, (0...30).contains(days),
                  let date = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: now)) else { return nil }
            return AdaptiveContent.UpcomingEvent(title: title, who: "", date: date)
        }
    }

    static func parseFocus(_ raw: String) throws -> FocusOutput {
        try JSONDecoder().decode(FocusOutput.self, from: Data(raw.utf8))
    }

    // Writing

    static let writerSystem = """
    You write English speaking practice for a Tamil-speaking IT professional (about CEFR B1–B2) who wants to sound natural and professional at work. \
    Use simple, natural, polite international business English. \(banned) Reply only with the JSON.
    """

    static func phraseUser(profile: LearnerProfile, unit: AdaptiveJobInputs.UnitBrief, weakSpots: [String]) -> String {
        """
        About the learner: \(profile.summary)
        Skill to practise: \(unit.title). \(unit.goal)
        Example phrases for this skill: \(unit.examples.prefix(3).map { "\"\($0)\"" }.joined(separator: ", "))
        Write ONE new sentence (8 to 20 words) the learner could really say at work this week, about their own job or project if you know it, using this skill.
        "english": the sentence. "tamil": its meaning in simple spoken Tamil, in Tamil script. "when": when to say it, in at most 12 simple English words.
        """
    }

    static let phraseGrammar = #"""
    root ::= "{" ws "\"english\":" ws string ws "," ws "\"tamil\":" ws string ws "," ws "\"when\":" ws string ws "}"
    """# + "\n" + string

    private struct PhraseOutput: Codable { let english: String; let tamil: String; let when: String }

    static func parsePhrase(_ raw: String, day: String, unitId: String) throws -> AdaptiveContent.DailyPhrase {
        let out = try JSONDecoder().decode(PhraseOutput.self, from: Data(raw.utf8))
        let english = out.english.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = FluencyMetrics.wordCount(english)
        // Reject sentences that are too short or long, or that contain a mistake we teach against.
        guard (5...30).contains(words), MistakeRules.check(english).isEmpty,
              out.tamil.unicodeScalars.contains(where: { (0x0B80...0x0BFF).contains($0.value) }) else { throw AdaptivePromptError.badOutput }
        return AdaptiveContent.DailyPhrase(day: day, unitId: unitId, english: english,
                                           tamil: out.tamil.trimmingCharacters(in: .whitespacesAndNewlines),
                                           when: out.when.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func weeklyUser(profile: LearnerProfile, base: CallScenario, weakSpots: [String]) -> String {
        let kind = base.kind == .interview ? "a job interview" : "a client meeting"
        let weak = weakSpots.isEmpty ? "" : "\nThe learner often gets these wrong, so give chances to practise them: \(weakSpots.prefix(3).joined(separator: "; "))."
        return """
        About the learner: \(profile.summary)
        This week's practice call is \(kind) with \(base.aiName), \(base.aiRole).
        The standard version: \(base.title). \(base.subtitle)\(weak)
        Rewrite this call so it fits the learner's real job and project (make up realistic details if needed).
        "title": at most 6 words. "subtitle": one sentence telling the learner what the call is about.
        "situation": 2 to 4 sentences of instructions to \(base.aiName), starting with "You are \(base.aiName)", saying what happens in the call and what to ask.
        "goals": 3 short goals for the learner, at most 10 words each.
        """
    }

    static let weeklyGrammar = #"""
    root ::= "{" ws "\"title\":" ws string ws "," ws "\"subtitle\":" ws string ws "," ws "\"situation\":" ws string ws "," ws "\"goals\":" ws "[" ws string ws "," ws string ws "," ws string ws "]" ws "}"
    """# + "\n" + string

    private struct WeeklyOutput: Codable { let title: String; let subtitle: String; let situation: String; let goals: [String] }

    static func parseWeekly(_ raw: String, week: String, base: CallScenario) throws -> AdaptiveContent.WeeklyChallenge {
        let out = try JSONDecoder().decode(WeeklyOutput.self, from: Data(raw.utf8))
        let title = out.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let situation = out.situation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 60, situation.count >= 40,
              situation.localizedCaseInsensitiveContains(base.aiName) else { throw AdaptivePromptError.badOutput }
        return AdaptiveContent.WeeklyChallenge(week: week, baseScenarioId: base.id, title: title,
                                               subtitle: out.subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                               situation: situation,
                                               goals: out.goals.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
}

/// Reads "tomorrow", "naalaikku", "next Friday", "in 3 days"… from a goal, in English or Tanglish.
enum EventDate {
    static func days(in text: String, now: Date = .now) -> Int? {
        let t = " " + text.lowercased().replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression) + " "
        func has(_ words: [String]) -> Bool { words.contains { t.contains(" \($0) ") } }
        if has(["day after tomorrow", "naalanniki", "nalanniki", "naalanniku", "nalannaiku"]) { return 2 }
        if has(["today", "tonight", "inniki", "innaiku", "indru", "inniku"]) { return 0 }
        if has(["tomorrow", "tmrw", "naalaikku", "nalaikku", "naalai", "nalaiku", "naalaiku", "nalaiki"]) { return 1 }
        if let match = t.firstMatch(of: /in (\d{1,2}) days?/), let n = Int(match.1) { return n }
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let short = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        if let index = weekdays.indices.first(where: { has([weekdays[$0], short[$0]]) }) {
            let today = Calendar.current.component(.weekday, from: now) - 1
            let ahead = (index - today + 7) % 7
            return ahead == 0 ? 7 : ahead
        }
        if has(["next week", "adutha vaaram", "adutha varam", "next wk"]) { return 7 }
        return nil
    }
}
