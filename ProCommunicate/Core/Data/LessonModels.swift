import Foundation

/// One lesson for a unit, decoded from `content/<course>/lessons/<unitId>.json`.
struct Lesson: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let unitId: String
    let title: String
    let intro: String
    let introTamil: String
    /// False until a native Tamil speaker has checked the Tamil text.
    let tamilReviewed: Bool
    let phrases: [Phrase]
    let steps: [LessonStep]

    func phrase(_ id: String?) -> Phrase? {
        guard let id else { return nil }
        return phrases.first { $0.id == id }
    }

    var gradedSteps: [LessonStep] { steps.filter(\.isGraded) }
}

/// A ready-to-use English phrase with its Tamil meaning.
struct Phrase: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let text: String
    let tamil: String
    let note: String?
}

/// One screen of a lesson. A flat structure (rather than an enum with payloads) keeps the JSON
/// simple to write by hand and easy to share with a future Android app.
struct LessonStep: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        /// Meet a phrase: hear it, see the Tamil meaning, say it aloud.
        case learn
        /// Pick the best reply for a situation.
        case choice
        /// Build the English sentence from tiles, given a Tamil prompt.
        case build
        /// Hear a sentence and pick what was said.
        case listen
        /// Pick the correct version of a common mistake.
        case fix
        /// Say your own sentences aloud (transcribed and checked when the speech model is downloaded).
        case speak
    }

    let id: String
    let type: Kind
    var phraseId: String? = nil
    var prompt: String? = nil
    var promptTamil: String? = nil
    var audioText: String? = nil
    var wrong: String? = nil
    var options: [String]? = nil
    var tiles: [String]? = nil
    var answer: String? = nil
    var explanation: String? = nil
    var explanationTamil: String? = nil
    var suggestedPhraseIds: [String]? = nil

    /// Learn and speak steps aren't marked right or wrong.
    var isGraded: Bool {
        switch type {
        case .learn, .speak: false
        case .choice, .build, .listen, .fix: true
        }
    }
}

enum AnswerChecker {
    /// Lower-case, curly quotes made straight, spaces collapsed, final punctuation ignored.
    static func normalize(_ text: String) -> String {
        let straight = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        let words = straight.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.trimmingCharacters(in: CharacterSet(charactersIn: ".!?").union(.whitespaces))
    }

    static func isCorrect(_ given: String, expected: String) -> Bool {
        normalize(given) == normalize(expected)
    }
}

extension ContentLoader {
    /// The lesson for a unit, or nil if that unit has no lesson yet.
    static func loadLesson(unitId: String, folder: String = defaultCourseFolder,
                           bundle: Bundle = Bundle(for: ContentBundleToken.self)) throws -> Lesson? {
        guard let url = bundle.url(forResource: unitId, withExtension: "json",
                                   subdirectory: "content/\(folder)/lessons") else { return nil }
        return try JSONDecoder().decode(Lesson.self, from: Data(contentsOf: url))
    }
}

extension Lesson {
    /// Problems that would make a step impossible or confusing. Empty means the lesson is valid.
    func validationProblems() -> [String] {
        var problems: [String] = []
        let phraseIds = Set(phrases.map(\.id))
        if Set(steps.map(\.id)).count != steps.count { problems.append("duplicate step ids") }
        for step in steps {
            let where_ = "step \(step.id)"
            switch step.type {
            case .learn:
                if !phraseIds.contains(step.phraseId ?? "") { problems.append("\(where_): unknown phraseId") }
            case .choice, .listen, .fix:
                guard let answer = step.answer, let options = step.options, options.count >= 2 else {
                    problems.append("\(where_): needs an answer and at least 2 options"); continue
                }
                if options.filter({ AnswerChecker.isCorrect($0, expected: answer) }).count != 1 {
                    problems.append("\(where_): exactly one option must match the answer")
                }
                if step.type == .listen && step.audioText == nil { problems.append("\(where_): listen needs audioText") }
                if step.type == .fix && step.wrong == nil { problems.append("\(where_): fix needs the wrong sentence") }
                if step.type == .choice && step.prompt == nil { problems.append("\(where_): choice needs a prompt") }
            case .build:
                guard let answer = step.answer, let tiles = step.tiles, step.promptTamil != nil else {
                    problems.append("\(where_): build needs answer, tiles and promptTamil"); continue
                }
                // Tiles carry no punctuation (it would give away the last word); compare normalised words.
                var available = tiles.map(AnswerChecker.normalize)
                for word in answer.split(separator: " ").map({ AnswerChecker.normalize(String($0)) }) {
                    if let index = available.firstIndex(of: word) { available.remove(at: index) }
                    else { problems.append("\(where_): tile missing for \"\(word)\"") }
                }
                if tiles.contains(where: { $0.hasSuffix(".") || $0.hasSuffix("?") || $0.hasSuffix("!") }) {
                    problems.append("\(where_): tiles shouldn't end with punctuation")
                }
            case .speak:
                if step.prompt == nil { problems.append("\(where_): speak needs a prompt") }
                for id in step.suggestedPhraseIds ?? [] where !phraseIds.contains(id) {
                    problems.append("\(where_): unknown suggested phrase \(id)")
                }
            }
        }
        return problems
    }
}
