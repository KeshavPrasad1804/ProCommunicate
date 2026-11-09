import Foundation

/// Small one-off AI jobs outside calls: Tamil explanations, answer checks, Ask in Tamil, meeting prep.
/// Loads the model on demand (only on a real iPhone with the model downloaded).
@MainActor
enum TutorService {
    static var isAvailable: Bool { LlamaEngine.isAvailable && AIModelManager.shared.isReady }

    static func ensureLoaded() async throws {
        guard isAvailable else { throw LlamaError.unavailable }
        try await LlamaEngine.shared.load(modelPath: AIModelManager.shared.modelFileURL.path)
    }

    /// A short Tamil explanation of a correction.
    static func explainInNative(wrong: String, right: String, why: String) async throws -> String {
        try await ensureLoaded()
        let prompt = GemmaPrompt.format([
            ChatMessage(role: .system, content: TutorPrompts.explainInNativeSystem()),
            ChatMessage(role: .user, content: TutorPrompts.explainInNativeUser(AnswerMistake(wrong: wrong, right: right, type: "", why: why))),
        ])
        let result = try await LlamaEngine.shared.generate(prompt: prompt, slot: .utility,
                                                          options: GenerationOptions(maxTokens: 160, temperature: 0.2))
        return result.text
    }

    /// Checks one answer (same prompt and grammar as during calls).
    static func checkAnswer(_ text: String) async throws -> AnswerCheck? {
        try await ensureLoaded()
        let prompt = GemmaPrompt.format([
            ChatMessage(role: .system, content: TutorPrompts.answerCheckSystem),
            ChatMessage(role: .user, content: text),
        ])
        let result = try await LlamaEngine.shared.generate(
            prompt: prompt, slot: .utility,
            options: GenerationOptions(maxTokens: 450, temperature: 0, grammar: TutorPrompts.answerCheckGrammar))
        return TutorPrompts.parseAnswerCheck(result.text, answer: text)
    }

    /// Streams an answer to a free-form request (Ask in Tamil).
    static func ask(system: String, user: String, maxTokens: Int = 350, onPiece: @escaping @Sendable (String) -> Void) async throws -> String {
        try await ensureLoaded()
        let prompt = GemmaPrompt.format([ChatMessage(role: .system, content: system), ChatMessage(role: .user, content: user)])
        let result = try await LlamaEngine.shared.generate(prompt: prompt, slot: .utility,
                                                          options: GenerationOptions(maxTokens: maxTokens, temperature: 0.5),
                                                          onPiece: onPiece)
        return result.text
    }

    /// Runs a grammar-constrained JSON request.
    static func json(system: String, user: String, grammar: String, maxTokens: Int = 600) async throws -> String {
        try await ensureLoaded()
        let prompt = GemmaPrompt.format([ChatMessage(role: .system, content: system), ChatMessage(role: .user, content: user)])
        let result = try await LlamaEngine.shared.generate(prompt: prompt, slot: .utility,
                                                          options: GenerationOptions(maxTokens: maxTokens, temperature: 0.3, grammar: grammar))
        return result.text
    }
}

/// A correction shown to the learner, from a rule or from the AI.
struct ReportFix: Identifiable, Equatable {
    let id: String
    let pattern: String
    let title: String
    let wrong: String
    let right: String
    let why: String
    let whyNative: String?
    let clipFile: String?
    let sentence: String
    var count: Int

    /// Up to `limit` fixes, most useful first: repeated patterns, then grammar, then style.
    static func top(from turns: [CallTurn], limit: Int = 3) -> [ReportFix] {
        var fixes: [String: ReportFix] = [:]
        for turn in turns where turn.speaker == .learner {
            for hit in turn.ruleHits {
                guard let rule = MistakeRules.rule(hit.ruleId) else { continue }
                if fixes[rule.id] != nil { fixes[rule.id]!.count += 1; continue }
                fixes[rule.id] = ReportFix(id: rule.id, pattern: rule.id, title: rule.title, wrong: hit.wrong, right: rule.right,
                                           why: rule.why, whyNative: rule.whyNative, clipFile: turn.clipFile, sentence: turn.text, count: 1)
            }
            for mistake in turn.check?.mistakes ?? [] {
                let overlaps = turn.ruleHits.contains {
                    let a = AnswerChecker.normalize($0.wrong), b = AnswerChecker.normalize(mistake.wrong)
                    return a.contains(b) || b.contains(a)
                }
                guard !overlaps else { continue }
                let key = mistake.type + ":" + AnswerChecker.normalize(mistake.wrong)
                if fixes[key] != nil { fixes[key]!.count += 1; continue }
                fixes[key] = ReportFix(id: key, pattern: mistake.type, title: mistake.wrong, wrong: mistake.wrong, right: mistake.right,
                                       why: mistake.why, whyNative: nil, clipFile: turn.clipFile, sentence: turn.text, count: 1)
            }
        }
        func rank(_ fix: ReportFix) -> Int {
            if MistakeRules.rule(fix.pattern) != nil { return 0 }
            return fix.pattern == "grammar" ? 1 : 2
        }
        return fixes.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            return $0.id < $1.id
        }
        .prefix(limit).map { $0 }
    }
}
