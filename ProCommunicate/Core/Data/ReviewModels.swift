import Foundation
import SwiftData

/// A phrase or a corrected mistake that comes back for review.
@Model
final class ReviewCard {
    enum Kind: String, Codable {
        /// Tamil meaning → say the English phrase.
        case phrase
        /// A common mistake → say the correct version.
        case mistake
    }

    @Attribute(.unique) var id: String
    var kindRaw: String
    /// What you see first (Tamil meaning, or the wrong sentence).
    var front: String
    /// The English you should say.
    var back: String
    /// Optional explanation shown with the answer.
    var hint: String?
    var lessonId: String?
    var createdAt: Date
    var due: Date
    var stability: Double
    var difficulty: Double
    var reps: Int
    var lapses: Int
    var lastReview: Date?

    var kind: Kind { Kind(rawValue: kindRaw) ?? .phrase }
    var isNew: Bool { reps == 0 }

    init(id: String, kind: Kind, front: String, back: String, hint: String?, lessonId: String?, due: Date, createdAt: Date = .now) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.front = front
        self.back = back
        self.hint = hint
        self.lessonId = lessonId
        self.createdAt = createdAt
        self.due = due
        self.stability = 0
        self.difficulty = 0
        self.reps = 0
        self.lapses = 0
    }
}

/// One day of practice, for streaks and the daily goal.
@Model
final class PracticeDay {
    @Attribute(.unique) var day: Date
    var seconds: Double
    var lessons: Int
    var reviews: Int
    var drills: Int
    var calls: Int

    init(day: Date) {
        self.day = day
        self.seconds = 0
        self.lessons = 0
        self.reviews = 0
        self.drills = 0
        self.calls = 0
    }

    var minutes: Int { Int((seconds / 60).rounded()) }
}

/// A saved voice recording (stand-up drill now; calls and answers in Phase 3).
@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var kind: String
    var title: String
    var fileName: String
    var duration: Double
    var createdAt: Date
    var transcript: String?
    var starred: Bool

    init(kind: String, title: String, fileName: String, duration: Double, createdAt: Date = .now) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.fileName = fileName
        self.duration = duration
        self.createdAt = createdAt
        self.starred = false
    }

    var fileURL: URL { RecordingStorage.directory.appending(path: fileName) }
}

enum RecordingStorage {
    static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try? ModelStorage.excludeFromBackup(url)
        }
        return url
    }
}

/// All SwiftData model types, so the app and tests use the same schema.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        LessonProgressRecord.self, ReviewCard.self, PracticeDay.self, Recording.self,
    ]
}
