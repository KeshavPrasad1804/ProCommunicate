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
