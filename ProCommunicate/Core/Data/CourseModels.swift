import Foundation

/// A course for speakers of `sourceLang` learning `targetLang`, for example Tamil → English.
/// Decoded from `Resources/content/<course>/course.json`, which a future Android app can share.
struct Course: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let sourceLang: String
    let targetLang: String
    let title: String
    let tracks: [Track]

    /// Tracks in the learner's priority order (1 = most important).
    var tracksByPriority: [Track] { tracks.sorted { $0.priority < $1.priority } }
}

struct Track: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let priority: Int
    let title: String
    let subtitle: String
    let systemImage: String
    let units: [CourseUnit]
}

struct CourseUnit: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let number: Int
    let title: String
    /// What the learner will be able to do after the unit.
    let goal: String
    /// A few of the key phrases the unit teaches.
    let examplePhrases: [String]
}

/// Marker type used to find the app's resource bundle, including from unit tests.
final class ContentBundleToken {}

enum ContentLoaderError: Error, CustomStringConvertible {
    case missingFile(String)

    var description: String {
        switch self {
        case .missingFile(let name): "Missing course file: \(name)"
        }
    }
}

enum ContentLoader {
    /// The content folder for the learner's language.
    static var defaultCourseFolder: String { NativeLanguage.current.contentFolder }

    static func loadCourse(folder: String = defaultCourseFolder,
                           bundle: Bundle = Bundle(for: ContentBundleToken.self)) throws -> Course {
        guard let url = bundle.url(forResource: "course", withExtension: "json", subdirectory: "content/\(folder)")
                ?? bundle.url(forResource: "course", withExtension: "json") else {
            throw ContentLoaderError.missingFile("content/\(folder)/course.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Course.self, from: data)
    }
}

extension Course {
    /// Small sample used by SwiftUI previews.
    static let preview = Course(
        id: "preview",
        sourceLang: "ta",
        targetLang: "en",
        title: "Business English for Tamil speakers",
        tracks: [
            Track(id: "meetings", priority: 1, title: "Meetings and client calls",
                  subtitle: "Speak clearly and confidently on calls", systemImage: "person.3.fill",
                  units: [CourseUnit(id: "meetings-01", number: 1, title: "Daily stand-up",
                               goal: "Give a clear yesterday / today / blockers update",
                               examplePhrases: ["Yesterday I completed…", "Today I'll be working on…"])]),
        ]
    )
}
