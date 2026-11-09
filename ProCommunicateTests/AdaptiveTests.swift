import Foundation
import SwiftData
import Testing
@testable import ProCommunicate

private func snapshot(_ mastery: [UnitMastery] = [], focus: LearningFocus = .meetings, patterns: [String: Int] = [:],
                      level: Int = 1, callStats: [CallScenario.Kind: (count: Int, mistakesPerAnswer: Double)] = [:],
                      upcoming: UpcomingEventInfo? = nil, counts: [String: Int] = [:]) -> LearnerSnapshot {
    LearnerSnapshot(mastery: Dictionary(mastery.map { ($0.unitId, $0) }, uniquingKeysWith: { a, _ in a }), focus: focus,
                    recentPatterns: patterns, level: level, callStats: callStats, upcoming: upcoming, scenarioCounts: counts)
}

private func unit(_ id: String, lesson: Double, memory: Double = 0.9, calls: Double? = nil, daysAgo: Double) -> UnitMastery {
    UnitMastery(unitId: id, lesson: lesson, memory: memory, calls: calls, lastPracticed: Date.now.addingTimeInterval(-daysAgo * 86_400))
}

@Suite("Learner model")
@MainActor
struct LearnerModelTests {
    let course = try! ContentLoader.loadCourse()
    var lessons: [Lesson] { TodayView.loadLessons(for: course) }

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func aFinishedLessonCountsAndFadesWithTime() throws {
        let lessons = self.lessons
        let lesson = try #require(lessons.first { $0.unitId == "meetings-03-status" })
        let fresh = LessonProgressRecord(lessonId: lesson.id, unitId: lesson.unitId, score: 0.9)
        let old = LessonProgressRecord(lessonId: lesson.id, unitId: lesson.unitId, score: 0.9, date: .now.addingTimeInterval(-60 * 86_400))
        let ctx = try context()
        ctx.insert(fresh)

        let now = LearnerModel.snapshot(course: course, lessons: lessons, progress: [fresh], cards: [], calls: [], mistakes: [],
                                        focus: .meetings, level: 1, upcoming: nil, scenarios: [])
        let later = LearnerModel.snapshot(course: course, lessons: lessons, progress: [old], cards: [], calls: [], mistakes: [],
                                          focus: .meetings, level: 1, upcoming: nil, scenarios: [])
        #expect(now.mastery(of: lesson.unitId).started)
        #expect(abs(now.mastery(of: lesson.unitId).lesson - 0.9) < 0.001)
        #expect(later.mastery(of: lesson.unitId).lesson < 0.45)
        #expect(!now.mastery(of: "meetings-04-delay").started)
    }

    @Test func callsAndRepeatedRuleMistakesAreCounted() throws {
        let ctx = try context()
        let turns = [CallTurn(speaker: .ai, text: "Any update?"),
                     CallTurn(speaker: .learner, text: "I will revert back by today itself.",
                              ruleHits: MistakeRules.check("I will revert back by today itself.").map { .init(ruleId: $0.ruleId, wrong: $0.wrong) })]
        let call = CallRecord(scenarioId: "unit-meetings-06-get-back", title: "Get back", kind: "quick", startedAt: .now, seconds: 60, turns: turns)
        let mistake = MistakeRecord(pattern: "revert-back", wrong: "revert back", right: "get back to you", why: "", whyTamil: nil)
        mistake.count = 3
        ctx.insert(call)
        ctx.insert(mistake)
        let snap = LearnerModel.snapshot(course: course, lessons: lessons, progress: [], cards: [], calls: [call], mistakes: [mistake],
                                         focus: .meetings, level: 1, upcoming: nil, scenarios: [])
        #expect(snap.recentPatterns["revert-back"] == 3)
        #expect(snap.mastery(of: "meetings-06-get-back").calls != nil)
        #expect(snap.callStats[.quick]?.count == 1)
        #expect(snap.scenarioCounts["unit-meetings-06-get-back"] == 1)
    }

    @Test func everyMistakeRuleHasARealTeachingUnit() {
        let unitIds = Set(course.tracks.flatMap(\.units).map(\.id))
        for rule in MistakeRules.all {
            let unit = MistakeRules.teachingUnit[rule.id]
            #expect(unit != nil, "\(rule.id) has no teaching unit")
            if let unit { #expect(unitIds.contains(unit), "\(rule.id) → \(unit)") }
        }
    }

    @Test func focusIsGuessedFromTheGoal() {
        #expect(LearningFocus.guess(from: "Clearing interviews at product companies") == .interviews)
        #expect(LearningFocus.guess(from: "Daily calls with my UK client") == .meetings)
        #expect(LearningFocus.guess(from: "Client meetings now, job switch next year") == .both)
        #expect(LearningFocus.guess(from: "") == .meetings)
    }

    @Test func speakingCheckSetsTheLevel() {
        #expect(LearnerModel.level(speakingCheckWPM: 60, speakingCheckMistakes: 0) == 0)
        #expect(LearnerModel.level(speakingCheckWPM: 120, speakingCheckMistakes: 1) == 1)
        #expect(LearnerModel.level(speakingCheckWPM: 130, speakingCheckMistakes: 0) == 2)
        #expect(LearnerModel.level(speakingCheckWPM: 0, speakingCheckMistakes: -1) == 1)
    }
}

@Suite("Adaptive planner")
@MainActor
struct AdaptivePlannerTests {
    let course = try! ContentLoader.loadCourse()
    var all: Set<String> { Set(course.tracks.flatMap(\.units).map(\.id)) }

    @Test func aNewLearnerStartsWithTheirFocus() throws {
        let meetings = try #require(AdaptivePlanner.pickLesson(snapshot: snapshot(focus: .meetings),
                                                               order: AdaptivePlanner.unitOrder(course, focus: .meetings), available: all))
        #expect(meetings.unitId == "meetings-01-standup")
        #expect(meetings.kind == .new)
        let interviews = try #require(AdaptivePlanner.pickLesson(snapshot: snapshot(focus: .interviews),
                                                                 order: AdaptivePlanner.unitOrder(course, focus: .interviews), available: all))
        #expect(interviews.unitId == "interviews-01-about-you")
    }

    @Test func bothInterleavesTheTracks() {
        let order = AdaptivePlanner.unitOrder(course, focus: .both).map(\.id)
        #expect(order.prefix(2) == ["meetings-01-standup", "interviews-01-about-you"])
        #expect(order.count == all.count)
    }

    @Test func aRepeatedMistakePullsInTheUnitThatFixesIt() throws {
        let snap = snapshot([unit("meetings-01-standup", lesson: 0.9, daysAgo: 1)], patterns: ["revert-back": 3])
        let pick = try #require(AdaptivePlanner.pickLesson(snapshot: snap, order: AdaptivePlanner.unitOrder(course, focus: .meetings), available: all))
        #expect(pick.unitId == "meetings-06-get-back")
        #expect(pick.kind == .fix)
        #expect(pick.reason.contains("3×"))
    }

    @Test func aFixLessonGetsThreeDaysToWork() throws {
        let snap = snapshot([unit("meetings-06-get-back", lesson: 0.6, daysAgo: 1)], patterns: ["revert-back": 3])
        let pick = try #require(AdaptivePlanner.pickLesson(snapshot: snap, order: AdaptivePlanner.unitOrder(course, focus: .meetings), available: all))
        #expect(pick.unitId != "meetings-06-get-back")
    }

    @Test func aFadedUnitIsRefreshed() throws {
        let snap = snapshot([unit("meetings-01-standup", lesson: 0.3, memory: 0.2, daysAgo: 10)])
        let pick = try #require(AdaptivePlanner.pickLesson(snapshot: snap, order: AdaptivePlanner.unitOrder(course, focus: .meetings), available: all))
        #expect(pick.unitId == "meetings-01-standup")
        #expect(pick.kind == .refresh)
    }

    @Test func masteredUnitsAreSkipped() throws {
        let snap = snapshot([unit("meetings-01-standup", lesson: 1, memory: 1, calls: 1, daysAgo: 1),
                             unit("meetings-02-opening", lesson: 1, memory: 1, daysAgo: 1)])
        let pick = try #require(AdaptivePlanner.pickLesson(snapshot: snap, order: AdaptivePlanner.unitOrder(course, focus: .meetings), available: all))
        #expect(pick.unitId == "meetings-03-status")
    }

    @Test func aRealMeetingTomorrowBecomesTodaysCall() throws {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let event = UpcomingEventInfo(title: "Sprint demo to the UK client", who: "Product owner", date: tomorrow, phrases: ["Let me walk you through it."])
        let unit = try #require(course.tracks.flatMap(\.units).first)
        let call = try #require(AdaptivePlanner.pickCall(lessonUnit: unit, lessonKind: .new, upcoming: event, scenarios: ScenarioLoader.loadAll()))
        #expect(call.scenario.id.hasPrefix("rehearsal"))
        #expect(call.reason.contains("tomorrow"))
        #expect(call.extra?.contains("walk you through") == true)

        let later = UpcomingEventInfo(title: "Demo", who: "", date: Calendar.current.date(byAdding: .day, value: 5, to: .now)!, phrases: [])
        let normal = try #require(AdaptivePlanner.pickCall(lessonUnit: unit, lessonKind: .new, upcoming: later, scenarios: ScenarioLoader.loadAll()))
        #expect(!normal.scenario.id.hasPrefix("rehearsal"))
    }

    @Test func weeklyKindFollowsFocusAndBalancesBoth() {
        #expect(AdaptivePlanner.weeklyKind(snapshot: snapshot(focus: .interviews), week: 2) == .interview)
        #expect(AdaptivePlanner.weeklyKind(snapshot: snapshot(focus: .meetings), week: 3) == .meeting)
        let moreMeetings = snapshot(focus: .both, callStats: [.meeting: (3, 0.5), .interview: (1, 0.5)])
        #expect(AdaptivePlanner.weeklyKind(snapshot: moreMeetings, week: 2) == .interview)
    }

    @Test func difficultyRisesAsMistakesFall() {
        #expect(AdaptivePlanner.difficulty(for: .meeting, snapshot: snapshot(level: 0)) == .gentle)
        #expect(AdaptivePlanner.difficulty(for: .meeting, snapshot: snapshot(level: 2)) == .standard)
        #expect(AdaptivePlanner.difficulty(for: .meeting, snapshot: snapshot(callStats: [.meeting: (3, 0.3)])) == .challenging)
        #expect(AdaptivePlanner.difficulty(for: .meeting, snapshot: snapshot(callStats: [.meeting: (2, 0.9)])) == .standard)
        #expect(AdaptivePlanner.difficulty(for: .meeting, snapshot: snapshot(callStats: [.meeting: (2, 2.0)])) == .gentle)
    }

    @Test func weeklyScenarioPrefersOnesYouHaveDoneLeast() throws {
        let scenarios = ScenarioLoader.loadAll()
        let interviews = scenarios.filter { $0.kind == .interview }
        var counts: [String: Int] = [:]
        for s in interviews.dropLast() { counts[s.id] = 2 }
        let pick = try #require(AdaptivePlanner.weeklyScenario(kind: .interview, scenarios: scenarios, snapshot: snapshot(counts: counts), week: 7))
        #expect(pick.id == interviews.last?.id)
    }

    @Test func difficultyIsWrittenIntoTheRole() throws {
        let base = try #require(ScenarioLoader.loadAll().first { $0.kind == .meeting })
        #expect(base.adapted(difficulty: .challenging).situation.contains("push back"))
        #expect(base.adapted(difficulty: .standard).situation == base.situation)
        #expect(base.adapted(difficulty: .gentle).id == base.id)
    }

    @Test func eventLabels() {
        let now = Date.now
        let cal = Calendar.current
        #expect(AdaptivePlanner.eventDayLabel(now, now: now) == "today")
        #expect(AdaptivePlanner.eventDayLabel(cal.date(byAdding: .day, value: 1, to: now)!, now: now) == "tomorrow")
        #expect(AdaptivePlanner.eventDayLabel(cal.date(byAdding: .day, value: 4, to: now)!, now: now) == "in 4 days")
        #expect(AdaptivePlanner.eventDayLabel(cal.date(byAdding: .day, value: -1, to: now)!, now: now) == nil)
    }
}

@Suite("Adaptive AI content")
@MainActor
struct AdaptiveContentTests {
    private func tempStore() -> AdaptiveStore {
        AdaptiveStore(fileURL: URL.temporaryDirectory.appending(path: "adaptive-\(UUID().uuidString)/content.json"))
    }

    @Test func storeSavesToDiskAndReloads() {
        let store = tempStore()
        store.update { $0.aiFocus = .init(target: "Interviews", focus: .interviews) }
        store.addEvent(.init(title: "Demo", who: "Client", date: Calendar.current.startOfDay(for: .now)))
        let reloaded = AdaptiveStore(fileURL: store.fileURL)
        #expect(reloaded.content == store.content)
        #expect(reloaded.nextEvent()?.title == "Demo")
    }

    @Test func focusChoiceBeatsTheAIWhichBeatsTheGuess() {
        let store = tempStore()
        #expect(store.focus(target: "my UK client calls", choice: "auto") == .meetings)
        store.update { $0.aiFocus = .init(target: "my UK client calls", focus: .both) }
        #expect(store.focus(target: "my UK client calls", choice: "auto") == .both)
        #expect(store.focus(target: "my UK client calls", choice: "interviews") == .interviews)
        // A changed goal falls back to the guess until the AI reads it again.
        #expect(store.focus(target: "HR interview at Zoho", choice: "auto") == .interviews)
    }

    @Test func pastEventsArePruned() {
        let store = tempStore()
        store.addEvent(.init(title: "Old", who: "", date: .now.addingTimeInterval(-3 * 86_400)))
        store.pruneEvents()
        #expect(store.content.events.isEmpty)
    }

    @Test func focusOutputGivesADatedEvent() throws {
        let out = try AdaptivePrompts.parseFocus(#"{"focus": "interviews", "event": "Zoho HR round", "days": 2}"#)
        #expect(out.focus == .interviews)
        let event = try #require(out.event(now: .now))
        #expect(AdaptivePlanner.eventDayLabel(event.date) == "in 2 days")
        #expect(try AdaptivePrompts.parseFocus(#"{"focus":"both","event":"","days":-1}"#).event(now: .now) == nil)
    }

    @Test func datesAreReadFromEnglishAndTanglish() {
        // Monday 9 November 2026.
        let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 10))!
        #expect(EventDate.days(in: "naalaikku manager kooda appraisal meeting irukku", now: monday) == 1)
        #expect(EventDate.days(in: "Zoho interview next Friday", now: monday) == 4)
        #expect(EventDate.days(in: "client demo on Monday", now: monday) == 7)
        #expect(EventDate.days(in: "adutha vaaram TCS interview", now: monday) == 7)
        #expect(EventDate.days(in: "release review in 3 days", now: monday) == 3)
        #expect(EventDate.days(in: "Interview today!", now: monday) == 0)
        #expect(EventDate.days(in: "Switching to a product company in 3 months", now: monday) == nil)
        #expect(EventDate.days(in: "Daily calls with my UK client", now: monday) == nil)
    }

    @Test func aPhraseWithATaughtMistakeIsRejected() {
        let good = #"{"english": "I'll get back to you on the payment API by Friday.", "tamil": "வெள்ளிக்கிழமைக்குள் பதில் சொல்கிறேன்.", "when": "When the client asks for an update"}"#
        let bad = #"{"english": "I will revert back to you on the payment API.", "tamil": "பதில் சொல்கிறேன்.", "when": "x"}"#
        let noTamil = #"{"english": "I'll get back to you on the payment API by Friday.", "tamil": "I will reply", "when": "x"}"#
        #expect((try? AdaptivePrompts.parsePhrase(good, day: "d", unitId: "u")) != nil)
        #expect((try? AdaptivePrompts.parsePhrase(bad, day: "d", unitId: "u")) == nil)
        #expect((try? AdaptivePrompts.parsePhrase(noTamil, day: "d", unitId: "u")) == nil)
    }

    @Test func weeklyChallengeMustBeForTheRightPerson() throws {
        let base = try #require(ScenarioLoader.loadAll().first { $0.kind == .meeting })
        let good = #"{"title": "Payment API go-live review", "subtitle": "Explain the go-live plan.", "situation": "You are \#(base.aiName), reviewing the payment API go-live with the learner. Ask about risks and dates.", "goals": ["Give a clear status", "Explain one risk", "Agree next steps"]}"#
        let wrong = #"{"title": "Review", "subtitle": "x", "situation": "You are Bob, a client asking many questions about the project plan.", "goals": ["a", "b", "c"]}"#
        let weekly = try AdaptivePrompts.parseWeekly(good, week: "2026-W46", base: base)
        #expect(weekly.goals.count == 3)
        #expect((try? AdaptivePrompts.parseWeekly(wrong, week: "w", base: base)) == nil)
    }

    @Test func jobsAreOnlyDueWhenTheCacheIsStale() throws {
        let store = tempStore()
        let jobs = AdaptiveJobs()
        jobs.store = store
        let base = try #require(ScenarioLoader.loadAll().first { $0.kind == .meeting })
        let inputs = AdaptiveJobInputs(profile: LearnerProfile(name: "", role: "", company: "", years: "", project: "", target: "Interviews"),
                                       day: "2026-11-09", week: "2026-W46",
                                       phraseUnit: .init(id: "meetings-01-standup", title: "Stand-up", goal: "", examples: []),
                                       weeklyBase: base, weakSpots: [])
        #expect(jobs.pendingJobs(inputs).count == 3)
        store.update {
            $0.aiFocus = .init(target: "Interviews", focus: .interviews)
            $0.phrase = .init(day: "2026-11-09", unitId: "meetings-01-standup", english: "x", tamil: "x", when: "x")
            $0.weekly = .init(week: "2026-W46", baseScenarioId: base.id, title: "t", subtitle: "s", situation: "s", goals: [])
        }
        #expect(jobs.pendingJobs(inputs).isEmpty)
    }
}

@Suite("Recording cleanup")
@MainActor
struct RecordingCleanupTests {
    @Test func oldAudioGoesButStarredAndMistakeClipsStay() throws {
        let dir = URL.temporaryDirectory.appending(path: "rec-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = Date.now.addingTimeInterval(-90 * 86_400)
        for name in ["old.m4a", "starred.m4a", "mistake.m4a", "new.m4a"] {
            let url = dir.appending(path: name)
            try Data(repeating: 1, count: 1000).write(to: url)
            if name != "new.m4a" { try FileManager.default.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: url.path) }
        }
        let ctx = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let starred = Recording(kind: "drill", title: "Kept", fileName: "starred.m4a", duration: 3)
        starred.starred = true
        ctx.insert(starred)
        let gone = Recording(kind: "drill", title: "Gone", fileName: "old.m4a", duration: 3)
        ctx.insert(gone)
        let mistake = MistakeRecord(pattern: "grammar", wrong: "a", right: "b", why: "", whyTamil: nil)
        mistake.lastClipFile = "mistake.m4a"
        ctx.insert(mistake)

        let result = RecordingCleanup.run(in: ctx, keepDays: 60, directory: dir)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        #expect(result.files == 1)
        #expect(left == ["starred.m4a", "mistake.m4a", "new.m4a"])
        #expect(try ctx.fetch(FetchDescriptor<Recording>()).map(\.title) == ["Kept"])
        #expect(RecordingCleanup.run(in: ctx, keepDays: 0, directory: dir).files == 0)
    }
}
