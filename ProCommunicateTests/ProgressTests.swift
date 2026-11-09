import Foundation
import SwiftData
import Testing
@testable import ProCommunicate

@MainActor
@Suite("Lesson progress")
struct ProgressTests {
    let lesson = Lesson(id: "l1", unitId: "u1", title: "T", intro: "", introNative: "", nativeReviewed: true,
                        phrases: [], steps: [])

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: LessonProgressRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func firstCompletionCreatesARecord() throws {
        let context = try makeContext()
        ProgressStore.recordCompletion(of: lesson, score: 0.75, in: context)
        let records = try context.fetch(FetchDescriptor<LessonProgressRecord>())
        #expect(records.count == 1)
        #expect(records.first?.unitId == "u1")
        #expect(records.first?.bestScore == 0.75)
        #expect(records.first?.timesCompleted == 1)
    }

    @Test func repeatsKeepTheBestScoreAndCount() throws {
        let context = try makeContext()
        ProgressStore.recordCompletion(of: lesson, score: 0.75, in: context)
        ProgressStore.recordCompletion(of: lesson, score: 1.0, in: context)
        ProgressStore.recordCompletion(of: lesson, score: 0.5, in: context)
        let records = try context.fetch(FetchDescriptor<LessonProgressRecord>())
        #expect(records.count == 1)
        #expect(records.first?.timesCompleted == 3)
        #expect(records.first?.bestScore == 1.0)
        #expect(records.first?.lastScore == 0.5)
    }
}

@Suite("Today's fix")
@MainActor
struct TodaysFixTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func practisingMarksItDoneAndMovesOnTomorrow() throws {
        let ctx = try context()
        let now = Date.now
        let big = MistakeRecord(pattern: "revert-back", wrong: "revert back", right: "get back to you", why: "", whyNative: nil, date: now.addingTimeInterval(-3600))
        big.count = 5
        let small = MistakeRecord(pattern: "prepone", wrong: "prepone", right: "move earlier", why: "", whyNative: nil, date: now.addingTimeInterval(-7200))
        small.count = 2
        ctx.insert(big); ctx.insert(small)

        #expect(LearningStore.todaysFix(from: [big, small], now: now) === big)
        #expect(!big.practisedToday(now: now))

        LearningStore.practised(big, now: now, in: ctx)
        // Still today's fix, now done; and today's minutes count it.
        #expect(LearningStore.todaysFix(from: [big, small], now: now) === big)
        #expect(big.practisedToday(now: now))
        let day = try ctx.fetch(FetchDescriptor<PracticeDay>()).first
        #expect(day?.seconds == 60)

        // Tomorrow: the practised one isn't picked again unless you make it again.
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(LearningStore.todaysFix(from: [big, small], now: tomorrow) === small)
        big.lastSeen = tomorrow.addingTimeInterval(-60)
        #expect(LearningStore.todaysFix(from: [big, small], now: tomorrow) === big)
    }
}
