import Foundation

/// A practice call: who the AI plays, the situation, and how it opens.
struct CallScenario: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        /// A short role-play of one meeting moment or interview question (4–5 turns).
        case quick
        /// A full client meeting simulation.
        case meeting
        /// A full mock interview.
        case interview
    }

    let id: String
    let kind: Kind
    var unitId: String? = nil
    let title: String
    let subtitle: String
    let aiName: String
    let aiRole: String
    /// "en-IN", "en-GB" or "en-US".
    let voice: String
    let maxTurns: Int
    let goals: [String]
    let situation: String
    let opening: String

    var speechVoice: SpeechVoice { SpeechVoice(rawValue: voice) ?? .indian }
    var isFullCall: Bool { kind != .quick }

    /// The system prompt for the AI's role, with the learner's profile pinned in it so the AI
    /// keeps the key facts even if old turns are dropped from a long call.
    func systemPrompt(profile: LearnerProfile, extraContext: String? = nil) -> String {
        var prompt = """
        Role-play for English practice, as a realistic voice call. \(situation)
        YOU are \(aiName), \(aiRole). Stay in this role the whole time; never mention being an AI or a tutor, and never correct the learner's English.
        The learner is a \(NativeLanguage.current.name) speaker improving their professional English (about CEFR B1–B2). \(profile.summary)
        Speak naturally, as on a real call: one or two short sentences per turn (at most 40 words), then one question or a clear next step. No lists, no headings, no emojis, no stage directions.
        If the learner asks to end or stop the call, close politely right away with a goodbye.
        """
        if let extraContext, !extraContext.isEmpty {
            prompt += "\nExtra context from the learner about this call: \(extraContext)"
        }
        if isFullCall {
            prompt += "\nThis call has about \(maxTurns) exchanges. When it is time to finish, or the learner closes the call, end politely with a goodbye."
        }
        return prompt
    }

    func openingLine(profile: LearnerProfile) -> String {
        opening.replacingOccurrences(of: "{name}", with: profile.firstName)
    }
}

enum ScenarioLoader {
    private struct File: Codable { let scenarios: [CallScenario] }

    static func loadAll(folder: String = ContentLoader.defaultCourseFolder,
                        bundle: Bundle = Bundle(for: ContentBundleToken.self)) -> [CallScenario] {
        guard let url = bundle.url(forResource: "scenarios", withExtension: "json", subdirectory: "content/\(folder)"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.scenarios
    }

    /// The role-play for a unit: its own scenario if there is one, otherwise one built from the
    /// unit's goal and phrases (a UK client for meeting units, an HR interviewer for interview units).
    static func forUnit(_ unit: CourseUnit, all: [CallScenario] = loadAll()) -> CallScenario {
        if let own = all.first(where: { $0.unitId == unit.id && $0.kind == .quick }) { return own }
        let phrases = unit.examplePhrases.map { "\"\($0)\"" }.joined(separator: ", ")
        if unit.id.hasPrefix("interviews") {
            return CallScenario(id: "unit-\(unit.id)", kind: .quick, unitId: unit.id, title: unit.title,
                                subtitle: unit.goal, aiName: "Meena", aiRole: "HR interviewer", voice: "en-IN", maxTurns: 5,
                                goals: [unit.goal] + unit.examplePhrases.prefix(2).map { "Use: \($0)" },
                                situation: "You are Meena, an HR interviewer at a \(NativeLanguage.current.officeCity) IT services company. Interview the learner on this topic: \(unit.title). Ask questions that give them the chance to \(unit.goal.lowercased()) Follow up once or twice on what they say. Useful phrases they are practising: \(phrases).",
                                opening: "Hello {name}, thanks for coming in. Shall we begin?")
        }
        return CallScenario(id: "unit-\(unit.id)", kind: .quick, unitId: unit.id, title: unit.title,
                            subtitle: unit.goal, aiName: "Emma", aiRole: "Client project manager, London", voice: "en-GB", maxTurns: 5,
                            goals: [unit.goal] + unit.examplePhrases.prefix(2).map { "Use: \($0)" },
                            situation: "You are Emma, the client's project manager in London, on a call with the learner's offshore team. Create a realistic moment in the call about: \(unit.title). Give the learner a natural reason to \(unit.goal.lowercased()) React to what they say and ask follow-up questions. Useful phrases they are practising: \(phrases).",
                            opening: "Hi {name}, thanks for joining. Shall we get started?")
    }

    /// A one-off rehearsal built from "I have a meeting tomorrow".
    static func rehearsal(description: String, who: String) -> CallScenario {
        CallScenario(id: "rehearsal-\(UUID().uuidString.prefix(8))", kind: .quick, title: "Rehearsal",
                     subtitle: description, aiName: "Alex", aiRole: who.isEmpty ? "the other person in the meeting" : who,
                     voice: "en-GB", maxTurns: 6, goals: ["Use your cheat-sheet phrases"],
                     situation: "The learner is rehearsing a real conversation they will have soon. Play the other person realistically, based on this description: \(description)",
                     opening: "Hi {name}, thanks for joining. Shall we get started?")
    }
}

/// What you tell the app about yourself, used to make calls realistic (Settings → About you).
struct LearnerProfile: Sendable, Equatable {
    var name: String
    var role: String
    var company: String
    var years: String
    var project: String
    var target: String

    enum Key {
        static let name = "profile.name", role = "profile.role", company = "profile.company"
        static let years = "profile.years", project = "profile.project", target = "profile.target"
    }

    static var current: LearnerProfile {
        let d = UserDefaults.standard
        return LearnerProfile(name: d.string(forKey: Key.name) ?? "", role: d.string(forKey: Key.role) ?? "",
                              company: d.string(forKey: Key.company) ?? "", years: d.string(forKey: Key.years) ?? "",
                              project: d.string(forKey: Key.project) ?? "", target: d.string(forKey: Key.target) ?? "")
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? "there"
    }

    var isEmpty: Bool { [name, role, company, years, project, target].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }

    /// One line of facts for the AI's system prompt.
    var summary: String {
        var facts: [String] = []
        if !name.isEmpty { facts.append("Their name is \(name).") }
        if !role.isEmpty { facts.append("They work as \(role)\(company.isEmpty ? "" : " at \(company)").") }
        if !years.isEmpty { facts.append("Experience: \(years) years.") }
        if !project.isEmpty { facts.append("Current project: \(project).") }
        if !target.isEmpty { facts.append("They are preparing for: \(target).") }
        return facts.isEmpty ? "You don't know their background yet; ask naturally if needed." : facts.joined(separator: " ")
    }
}
