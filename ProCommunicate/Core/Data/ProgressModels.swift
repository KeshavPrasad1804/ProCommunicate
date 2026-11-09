import Foundation
import SwiftData

/// Your result for a lesson, saved on the phone.
@Model
final class LessonProgressRecord {
    @Attribute(.unique) var lessonId: String
    var unitId: String
    var firstCompletedAt: Date
    var lastCompletedAt: Date
    var timesCompleted: Int
    var bestScore: Double
    var lastScore: Double

    init(lessonId: String, unitId: String, score: Double, date: Date = .now) {
        self.lessonId = lessonId
        self.unitId = unitId
        self.firstCompletedAt = date
        self.lastCompletedAt = date
        self.timesCompleted = 1
        self.bestScore = score
        self.lastScore = score
    }
}

enum ProgressStore {
    /// Saves a finished lesson: creates the record the first time, then updates it.
    @MainActor
    static func recordCompletion(of lesson: Lesson, score: Double, date: Date = .now, in context: ModelContext) {
        let lessonId = lesson.id
        let descriptor = FetchDescriptor<LessonProgressRecord>(predicate: #Predicate { $0.lessonId == lessonId })
        if let existing = try? context.fetch(descriptor).first {
            existing.timesCompleted += 1
            existing.lastCompletedAt = date
            existing.lastScore = score
            existing.bestScore = max(existing.bestScore, score)
        } else {
            context.insert(LessonProgressRecord(lessonId: lesson.id, unitId: lesson.unitId, score: score, date: date))
        }
        try? context.save()
    }
}
