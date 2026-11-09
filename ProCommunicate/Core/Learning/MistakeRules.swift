import Foundation
import os

/// A common Indian-English pattern, caught instantly without the AI, with a hand-written
/// explanation in the learner's language (marked for native review like the lessons).
struct MistakeRule: Sendable, Identifiable {
    let id: String
    /// Short name for grouping in My Mistakes.
    let title: String
    /// Case-insensitive ICU regular expression.
    let pattern: String
    let right: String
    let why: String

    /// The explanation in the learner's language (from content/<language>/rules.json).
    var whyNative: String { RuleNotes.text(for: id) ?? why }
}

/// A rule match in a learner's sentence.
struct RuleHit: Sendable, Equatable {
    let ruleId: String
    let title: String
    let wrong: String
    let right: String
    let why: String
    let whyNative: String

    var asMistake: AnswerMistake { AnswerMistake(wrong: wrong, right: right, type: "pattern", why: why) }
}

enum MistakeRules {
    static let all: [MistakeRule] = [
        MistakeRule(id: "myself-intro", title: "\"Myself …\" to introduce yourself",
                    pattern: #"(^|[.!?,]\s*|\b(hi|hello|morning|afternoon|evening|sir|madam|everyone)\s+)myself\s+(is\s+)?[a-z]+"#,
                    right: "I'm … / My name is …",
                    why: "Introduce yourself with \"I'm Priya\" or \"My name is Priya\"."),
        MistakeRule(id: "am-having", title: "\"I am having\" for experience or knowledge",
                    pattern: #"\b(i am|i'm|we are|we're|he is|she is|they are) having\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten|a|an|good|some|strong|experience|knowledge|exposure)\b"#,
                    right: "I have …",
                    why: "For experience, knowledge or things you own, say \"I have\", not \"I am having\"."),
        MistakeRule(id: "since-continuous", title: "\"I am working … since …\"",
                    pattern: #"\b(i am|i'm|we are|we're|he is|she is) (working|living|staying|handling|doing|leading|managing)\b[^.?!]{0,50}\bsince\b"#,
                    right: "I have been working … since …",
                    why: "With \"since\" or \"for\" + a time, use \"have been working\"."),
        MistakeRule(id: "revert-back", title: "\"Revert back\"",
                    pattern: #"\brevert(ed|ing|s)?\s+back\b"#,
                    right: "get back to you",
                    why: "Say \"I'll get back to you\". Outside India, \"revert\" means \"go back to an old state\"."),
        MistakeRule(id: "revert-to-me", title: "\"Revert to me\" for reply",
                    pattern: #"\brevert(ed|ing|s)?\s+to\s+(me|you|us|him|her|them)\b"#,
                    right: "get back to me / reply to me",
                    why: "To ask for a reply, say \"Please get back to me\" or \"Please reply\"."),
        MistakeRule(id: "itself", title: "\"today itself\", \"now itself\"",
                    pattern: #"\b(today|tomorrow|now|here|there|then|yesterday|tonight) itself\b"#,
                    right: "today / by end of today",
                    why: "Drop \"itself\": say \"today\" or \"by the end of today\"."),
        MistakeRule(id: "do-the-needful", title: "\"Do the needful\"",
                    pattern: #"\bdo\s+the\s+needful\b"#,
                    right: "say exactly what you need",
                    why: "\"Do the needful\" is vague and old-fashioned. Say the exact action: \"Please send the files\"."),
        MistakeRule(id: "discuss-about", title: "\"Discuss about\"",
                    pattern: #"\bdiscuss(ed|es|ing)?\s+about\b"#,
                    right: "discuss …",
                    why: "\"Discuss\" doesn't take \"about\": \"We discussed the budget\"."),
        MistakeRule(id: "doubt-question", title: "\"Doubt\" meaning question",
                    pattern: #"\b(i have|i've got|i am having|i'm having|i had|small|one|a few|some)\s+(a\s+|one\s+|small\s+)?doubts?\b"#,
                    right: "I have a question",
                    why: "To ask something, say \"I have a question\". \"Doubt\" sounds like you don't believe them."),
        MistakeRule(id: "prepone", title: "\"Prepone\"",
                    pattern: #"\bprepon(e|ed|ing)\b"#,
                    right: "bring forward / move earlier",
                    why: "\"Prepone\" isn't understood outside India. Say \"bring the meeting forward\" or \"move it earlier\"."),
        MistakeRule(id: "good-name", title: "\"What is your good name?\"",
                    pattern: #"\bgood\s+name\b"#,
                    right: "May I know your name?",
                    why: "Say \"May I know your name?\" or \"What's your name?\"."),
        MistakeRule(id: "cousin-brother", title: "\"Cousin brother / sister\"",
                    pattern: #"\bcousin\s+(brother|sister)\b"#,
                    right: "cousin",
                    why: "In English, just say \"cousin\"."),
        MistakeRule(id: "passed-out", title: "\"Passed out\" for graduated",
                    pattern: #"\bpassed\s+out\s+(in|from|of)\b"#,
                    right: "graduated in / from",
                    why: "\"Passed out\" means fainted. Say \"I graduated in 2019\"."),
        MistakeRule(id: "updation", title: "\"Updation\"",
                    pattern: #"\bupdation\b"#,
                    right: "update",
                    why: "The word is \"update\"."),
        MistakeRule(id: "the-same", title: "\"… of the same\"",
                    pattern: #"\b(of|for|on|about|regarding)\s+the\s+same\b\s*[.?!]?$"#,
                    right: "it / this / them",
                    why: "Use \"it\" or name the thing: \"Please share the details\", not \"details of the same\"."),
        MistakeRule(id: "out-of-station", title: "\"Out of station\"",
                    pattern: #"\bout\s+of\s+station\b"#,
                    right: "out of town / travelling",
                    why: "Say \"I'm out of town\" or \"I'm travelling\"."),
        MistakeRule(id: "my-native", title: "\"My native\" for hometown",
                    pattern: #"\bmy\s+native\b(?!\s+(language|speaker|tongue|place))"#,
                    right: "my hometown",
                    why: "Say \"my hometown is Madurai\"."),
        MistakeRule(id: "do-one-thing", title: "\"Do one thing\"",
                    pattern: #"\bdo\s+one\s+thing\b"#,
                    right: "say the request directly",
                    why: "Say the request directly: \"Could you please…\"."),
        MistakeRule(id: "only-emphasis", title: "\"only\" for emphasis",
                    pattern: #"\b(fine|good|okay|ok|here|now|like this|that way|this way|true|correct)\s+only\b"#,
                    right: "drop \"only\"",
                    why: "\"Only\" for emphasis is Indian English. Just drop it."),
        MistakeRule(id: "did-past", title: "\"did + past tense\"",
                    pattern: #"\bdid(n't|\s+not)?\s+(went|came|saw|told|said|gave|took|wrote|got|made|knew|thought|brought|sent)\b"#,
                    right: "did + base verb (did go, didn't come)",
                    why: "After \"did\" or \"didn't\", use the base verb: \"I didn't go\"."),
        MistakeRule(id: "more-better", title: "\"more better\"",
                    pattern: #"\bmore\s+(better|worse|bigger|smaller|faster|easier|cheaper)\b"#,
                    right: "better / much better",
                    why: "\"Better\" already means \"more good\": say \"better\" or \"much better\"."),
    ]

    /// All rule matches in a sentence, at most one per rule, in the order they appear.
    static func check(_ text: String) -> [RuleHit] {
        let range = NSRange(text.startIndex..., in: text)
        var hits: [(location: Int, hit: RuleHit)] = []
        for rule in all {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: range),
                  let matchRange = Range(match.range, in: text) else { continue }
            let wrong = String(text[matchRange]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            hits.append((match.range.location, RuleHit(ruleId: rule.id, title: rule.title, wrong: wrong, right: rule.right,
                                                        why: rule.why, whyNative: rule.whyNative)))
        }
        return hits.sorted { $0.location < $1.location }.map(\.hit)
    }

    static func rule(_ id: String) -> MistakeRule? { all.first { $0.id == id } }
}

/// Speaking-speed and filler numbers from a transcript.
enum FluencyMetrics {
    static let fillers = ["um", "umm", "uh", "uhh", "erm", "er", "ah", "actually", "basically", "literally", "you know", "i mean"]

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace }.filter { $0.contains(where: \.isLetter) }.count
    }

    static func wordsPerMinute(words: Int, seconds: Double) -> Double {
        seconds > 1 ? Double(words) / seconds * 60 : 0
    }

    static func fillerCount(_ text: String) -> Int {
        let lowered = " " + text.lowercased().replacingOccurrences(of: #"[^a-z' ]"#, with: " ", options: .regularExpression) + " "
        return fillers.reduce(0) { count, filler in
            count + lowered.components(separatedBy: " \(filler) ").count - 1
        }
    }
}

/// The mistake rules' explanations in each language, from `content/<language>/rules.json`.
enum RuleNotes {
    private static let cache = OSAllocatedUnfairLock<[NativeLanguage: [String: String]]>(initialState: [:])

    static func text(for ruleId: String, language: NativeLanguage = .current) -> String? {
        notes(for: language)[ruleId]
    }

    static func notes(for language: NativeLanguage) -> [String: String] {
        cache.withLock { cache in
            if let notes = cache[language] { return notes }
            let bundle = Bundle(for: ContentBundleToken.self)
            let notes = bundle.url(forResource: "rules", withExtension: "json", subdirectory: "content/\(language.contentFolder)")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            cache[language] = notes
            return notes
        }
    }
}
