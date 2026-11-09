import Foundation
import SwiftData
import Testing
@testable import ProCommunicate

@Suite("FSRS scheduler")
struct FSRSTests {
    let fsrs = FSRS()

    @Test func betterGradesGiveLongerFirstIntervals() {
        let intervals = ReviewGrade.allCases.map { fsrs.intervalDays(stability: fsrs.initialState(grade: $0).stability) }
        #expect(intervals == intervals.sorted())
        #expect(intervals.last! > intervals.first!)
    }

    @Test func intervalEqualsStabilityAtNinetyPercentRetention() {
        #expect(fsrs.intervalDays(stability: 10) == 10)
        #expect(fsrs.intervalDays(stability: 0.2) == 1)       // never less than a day
        #expect(fsrs.intervalDays(stability: 5000) == 365)    // capped at a year
    }

    @Test func retrievabilityIsNinetyPercentAfterStabilityDays() {
        let r = fsrs.retrievability(elapsedDays: 7, stability: 7)
        #expect(abs(r - 0.9) < 0.0001)
        #expect(fsrs.retrievability(elapsedDays: 0, stability: 7) == 1)
    }

    @Test func rememberingGrowsStabilityAndForgettingShrinksIt() {
        let start = fsrs.initialState(grade: .good)
        let remembered = fsrs.next(start, grade: .good, elapsedDays: start.stability)
        let forgotten = fsrs.next(start, grade: .again, elapsedDays: start.stability)
        #expect(remembered.stability > start.stability)
        #expect(forgotten.stability < start.stability)
        #expect(forgotten.difficulty > start.difficulty)
    }

    @Test func difficultyStaysInRange() {
        var state = fsrs.initialState(grade: .again)
        for _ in 0..<20 { state = fsrs.next(state, grade: .again, elapsedDays: 1) }
        #expect(state.difficulty <= 10)
        for _ in 0..<40 { state = fsrs.next(state, grade: .easy, elapsedDays: 1) }
        #expect(state.difficulty >= 1)
    }
}

@MainActor
@Suite("Review cards and streaks")
struct ReviewStoreTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(AppSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func lessonAddsPhraseAndMistakeCardsOnceDueTomorrow() throws {
        let context = try makeContext()
        let lesson = try #require(try ContentLoader.loadLesson(unitId: "meetings-03-status"))
        let now = Date()
        LearningStore.addCards(from: lesson, now: now, in: context)
        LearningStore.addCards(from: lesson, now: now, in: context)   // repeat lesson: no duplicates
        let cards = try context.fetch(FetchDescriptor<ReviewCard>())
        #expect(cards.count == 5 + 2)                                  // 5 phrases + 2 fix steps
        #expect(cards.filter { $0.kind == .mistake }.count == 2)
        #expect(LearningStore.dueCards(now: now, in: context).isEmpty)
        let tomorrow = now.addingTimeInterval(36 * 3600)
        #expect(LearningStore.dueCards(now: tomorrow, in: context).count == 7)
    }

    @Test func gradingSchedulesTheNextReview() throws {
        let context = try makeContext()
        let card = ReviewCard(id: "c", kind: .phrase, front: "f", back: "b", hint: nil, lessonId: nil, due: .now)
        context.insert(card)
        let now = Date()
        LearningStore.grade(card, .good, now: now)
        #expect(card.reps == 1)
        #expect(card.due > now.addingTimeInterval(86_400 * 0.9))
        LearningStore.grade(card, .again, now: now.addingTimeInterval(86_400 * 3))
        #expect(card.lapses == 1)
        #expect(card.due.timeIntervalSince(now.addingTimeInterval(86_400 * 3)) == 600)
    }

    @Test func practiceTimeAddsUpPerDay() throws {
        let context = try makeContext()
        let now = Date()
        LearningStore.log(.lesson, seconds: 300, now: now, in: context)
        LearningStore.log(.review, seconds: 120, now: now, in: context)
        let days = try context.fetch(FetchDescriptor<PracticeDay>())
        #expect(days.count == 1)
        #expect(days.first?.minutes == 7)
        #expect(days.first?.lessons == 1)
        #expect(days.first?.reviews == 1)
    }

    @Test func streakCountsConsecutiveDays() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 15))!
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
        #expect(LearningStore.streak(practiceDays: [], today: today, calendar: cal) == 0)
        #expect(LearningStore.streak(practiceDays: [day(0)], today: today, calendar: cal) == 1)
        #expect(LearningStore.streak(practiceDays: [day(0), day(-1), day(-2)], today: today, calendar: cal) == 3)
        // Today not done yet: the streak from yesterday still counts.
        #expect(LearningStore.streak(practiceDays: [day(-1), day(-2)], today: today, calendar: cal) == 2)
        // A gap breaks it.
        #expect(LearningStore.streak(practiceDays: [day(0), day(-2)], today: today, calendar: cal) == 1)
        #expect(LearningStore.streak(practiceDays: [day(-2), day(-3)], today: today, calendar: cal) == 0)
    }
}
