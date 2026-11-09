import Foundation

/// One message in a conversation with the model.
struct ChatMessage: Equatable, Sendable, Codable {
    enum Role: String, Sendable, Codable { case system, user, assistant }
    let role: Role
    let content: String
}

/// Formats a conversation in Gemma 4's chat format (checked against the model's own template
/// with llama-server on the Mac; thinking off):
///   <|turn>system\n…<turn|>\n<|turn>user\n…<turn|>\n<|turn>model\n
/// The tokenizer adds <bos> itself.
enum GemmaPrompt {
    static func format(_ messages: [ChatMessage], addGenerationPrompt: Bool = true) -> String {
        var prompt = ""
        for message in messages {
            let role = switch message.role {
            case .system: "system"
            case .user: "user"
            case .assistant: "model"
            }
            prompt += "<|turn>\(role)\n\(message.content.trimmingCharacters(in: .whitespacesAndNewlines))<turn|>\n"
        }
        if addGenerationPrompt { prompt += "<|turn>model\n" }
        return prompt
    }

    /// Removes any end-of-turn marker the model printed as text.
    static func clean(_ reply: String) -> String {
        reply.replacingOccurrences(of: "<turn|>", with: "")
            .replacingOccurrences(of: "<|turn>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A mistake found in a learner's answer.
struct AnswerMistake: Equatable, Sendable, Codable, Identifiable {
    var id: String { wrong + "→" + right }
    let wrong: String
    let right: String
    let type: String
    let why: String
}

/// The model's check of one answer: a better version plus up to 3 mistakes.
struct AnswerCheck: Equatable, Sendable, Codable {
    let better: String
    let mistakes: [AnswerMistake]
}

enum TutorPrompts {
    /// Tested on the Mac (bench/): no invented mistakes on correct sentences, catches the common
    /// Indian-English patterns, and "better" fixes what it lists.
    static let answerCheckSystem = """
    You are a careful English coach for Tamil speakers practising professional English. Check the learner's spoken answer. \
    Report a problem only if a native speaker would clearly say it differently; many answers are already correct, and then the mistakes list must be empty. \
    Report at most the 3 most important problems, grammar mistakes and common Indian-English phrases first (for example: myself, I am having, revert back, today itself, discuss about, do the needful, since with present continuous). \
    'wrong' quotes the learner's exact words; 'right' is the corrected words; 'why' is one short sentence in simple English. \
    'better' is the whole answer rewritten naturally and professionally, and it must fix every mistake you list.
    """

    /// GBNF grammar forcing the answer-check JSON: {"better": "...", "mistakes": [≤3 × {wrong, right, type, why}]}.
    static let answerCheckGrammar = #"""
    root ::= "{" ws "\"better\":" ws string "," ws "\"mistakes\":" ws mistakes ws "}"
    mistakes ::= "[" ws ( mistake ( ws "," ws mistake ){0,2} )? ws "]"
    mistake ::= "{" ws "\"wrong\":" ws string "," ws "\"right\":" ws string "," ws "\"type\":" ws kind "," ws "\"why\":" ws string ws "}"
    kind ::= "\"grammar\"" | "\"style\""
    string ::= "\"" char{0,300} "\""
    char ::= [^"\\\x7F\x00-\x1F] | "\\" ( ["\\/bfnrt] | "u" [0-9a-fA-F]{4} )
    ws ::= [ \t\n]{0,10}
    """#

    static func explainInTamilSystem() -> String {
        "You are an English coach for Tamil speakers. Explain the correction in ONE or TWO short sentences of simple Tamil (Tamil script). English words may stay in English. No greeting, no extra text."
    }

    static func explainInTamilUser(_ mistake: AnswerMistake) -> String {
        "Learner said: \"\(mistake.wrong)\". Better: \"\(mistake.right)\". Reason: \(mistake.why)"
    }

    /// Parses the model's JSON and drops entries that are no use to the learner:
    /// no change (wrong == right), or "wrong" text that isn't actually in the answer.
    static func parseAnswerCheck(_ json: String, answer: String) -> AnswerCheck? {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(AnswerCheck.self, from: data) else { return nil }
        let normalizedAnswer = AnswerChecker.normalize(answer)
        let kept = raw.mistakes.filter { mistake in
            let wrong = AnswerChecker.normalize(mistake.wrong)
            return !wrong.isEmpty
                && wrong != AnswerChecker.normalize(mistake.right)
                && normalizedAnswer.contains(wrong)
        }
        return AnswerCheck(better: raw.better.trimmingCharacters(in: .whitespacesAndNewlines), mistakes: kept)
    }
}
