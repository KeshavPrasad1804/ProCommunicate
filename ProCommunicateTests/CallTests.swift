import Foundation
import SwiftData
import Testing
@testable import ProCommunicate

@Suite("Call scenarios")
struct CallScenarioTests {
    let scenarios = ScenarioLoader.loadAll()

    @Test func loadsMeetingsInterviewsAndQuickRolePlays() {
        #expect(scenarios.filter { $0.kind == .meeting }.count >= 4)
        #expect(scenarios.filter { $0.kind == .interview }.count >= 3)
        #expect(scenarios.filter { $0.kind == .quick }.count >= 8)
        #expect(Set(scenarios.map(\.id)).count == scenarios.count)
    }

    @Test func quickRolePlaysPointToRealUnits() throws {
        let unitIds = Set(try ContentLoader.loadCourse().tracks.flatMap(\.units).map(\.id))
        for scenario in scenarios where scenario.unitId != nil {
            #expect(unitIds.contains(scenario.unitId!), "\(scenario.id)")
        }
    }

    @Test func everyScenarioHasAKnownVoiceAndPersonalisedOpening() {
        for scenario in scenarios {
            #expect(SpeechVoice(rawValue: scenario.voice) != nil, "\(scenario.id)")
            #expect(scenario.opening.contains("{name}"), "\(scenario.id)")
        }
    }

    @Test func systemPromptPinsTheProfileAndRole() throws {
        let scenario = try #require(scenarios.first { $0.id == "interview-hr" })
        let profile = LearnerProfile(name: "Priya Ramesh", role: "Java developer", company: "Infosys", years: "3",
                                     project: "a loan approval system", target: "senior developer roles")
        let prompt = scenario.systemPrompt(profile: profile, extraContext: "Spring Boot, AWS")
        #expect(prompt.contains("YOU are Meena"))
        #expect(prompt.contains("Their name is Priya Ramesh."))
        #expect(prompt.contains("a loan approval system"))
        #expect(prompt.contains("Spring Boot, AWS"))
        #expect(prompt.contains("never correct the learner's English"))
        #expect(scenario.openingLine(profile: profile).contains("Priya"))
        #expect(!scenario.openingLine(profile: profile).contains("Ramesh"))
    }

    @Test func emptyProfileStillWorks() {
        let empty = LearnerProfile(name: "", role: "", company: "", years: "", project: "", target: "")
        #expect(empty.isEmpty)
        #expect(empty.firstName == "there")
        #expect(empty.summary.contains("don't know their background"))
    }
}

@Suite("Sentence splitting for speech")
struct SentenceSplitterTests {
    @Test func speaksSentencesAsTheyArrive() {
        var splitter = SentenceSplitter()
        #expect(splitter.add("Thanks for the up") == [])
        #expect(splitter.add("date. What is the ") == ["Thanks for the update."])
        #expect(splitter.add("new date? ") == ["What is the new date?"])
        #expect(splitter.flush() == nil)
    }

    @Test func flushesTheLastSentenceWithoutPunctuation() {
        var splitter = SentenceSplitter()
        _ = splitter.add("Great, see you Monday")
        #expect(splitter.flush() == "Great, see you Monday")
    }
}

@Suite("Report fixes")
struct ReportFixTests {
    @Test func repeatedPatternsComeFirstAndAIDuplicatesAreDropped() {
        var t1 = CallTurn(speaker: .learner, text: "I am having three years experience.")
        t1.ruleHits = [CallTurn.StoredHit(ruleId: "am-having", wrong: "I am having three")]
        t1.check = AnswerCheck(better: "I have three years of experience.", mistakes: [
            AnswerMistake(wrong: "I am having three", right: "I have three", type: "grammar", why: "-"),   // same as the rule
            AnswerMistake(wrong: "years experience", right: "years of experience", type: "grammar", why: "-"),
        ])
        var t2 = CallTurn(speaker: .learner, text: "We are having good knowledge.")
        t2.ruleHits = [CallTurn.StoredHit(ruleId: "am-having", wrong: "We are having good")]
        let fixes = ReportFix.top(from: [CallTurn(speaker: .ai, text: "Hi"), t1, t2])
        #expect(fixes.map(\.id) == ["am-having", "grammar:years experience"])
        #expect(fixes.first?.count == 2)
        #expect(fixes.first?.whyTamil != nil)
    }
}

@MainActor
@Suite("My Mistakes")
struct MistakeBookTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func samePatternAddsUpAndCreatesOneReviewCard() throws {
        let context = try makeContext()
        var t1 = CallTurn(speaker: .learner, text: "I will revert back today itself.")
        t1.ruleHits = MistakeRules.check(t1.text).map { CallTurn.StoredHit(ruleId: $0.ruleId, wrong: $0.wrong) }
        var t2 = CallTurn(speaker: .learner, text: "Please revert back by Friday.")
        t2.ruleHits = MistakeRules.check(t2.text).map { CallTurn.StoredHit(ruleId: $0.ruleId, wrong: $0.wrong) }
        MistakeBook.record(turns: [t1, t2], in: context)
        let records = try context.fetch(FetchDescriptor<MistakeRecord>())
        #expect(records.first { $0.pattern == "revert-back" }?.count == 2)
        #expect(records.first { $0.pattern == "itself" }?.count == 1)
        let cards = try context.fetch(FetchDescriptor<ReviewCard>())
        #expect(cards.count == 2)
        #expect(cards.allSatisfy { $0.kind == .mistake })
    }

    @Test func callRecordComputesFluencyNumbers() {
        let turns = [
            CallTurn(speaker: .ai, text: "Tell me about yourself."),
            CallTurn(speaker: .learner, text: "Um, I am a Java developer, actually with three years.", seconds: 6, longPauses: 1),
        ]
        let record = CallRecord(scenarioId: "s", title: "t", kind: "quick", startedAt: .now, seconds: 30, turns: turns)
        #expect(record.learnerWords == 10)
        #expect(record.fillers == 2)
        #expect(record.longPauses == 1)
        #expect(Int(record.wordsPerMinute) == 100)
        #expect(record.turns.count == 2)
    }
}

@Suite("Ask in Tamil")
struct AskTamilParsingTests {
    @Test func keepsEnglishSentencesAndDropsTamilAndHeadings() {
        let answer = """
        Here are a couple of options:

        **Option 1 (More formal):** "I would like to request leave for tomorrow."
        **Option 2 (Slightly softer):** "Could I please take tomorrow off?"

        **தமிழ் விளக்கம்:**
        இந்த வாக்கியங்களை நீங்கள் மேனேஜருடன் பேசும்போது பயன்படுத்தலாம்.
        """
        let sentences = AskTamilView.englishSentences(in: answer)
        #expect(sentences.contains("I would like to request leave for tomorrow."))
        #expect(sentences.contains("Could I please take tomorrow off?"))
        #expect(!sentences.contains { $0.unicodeScalars.contains { (0x0B80...0x0BFF).contains($0.value) } })
    }
}
