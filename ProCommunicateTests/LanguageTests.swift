import Foundation
import SwiftData
import Testing
@testable import ProCommunicate

@Suite("Language packs")
@MainActor
struct LanguagePackTests {
    private func lessons(_ language: NativeLanguage) throws -> [Lesson] {
        let course = try ContentLoader.loadCourse(folder: language.contentFolder)
        return try course.tracksByPriority.flatMap(\.units).compactMap { try ContentLoader.loadLesson(unitId: $0.id, folder: language.contentFolder) }
    }

    @Test(arguments: NativeLanguage.allCases)
    func everyLanguageHasTheFullCourse(language: NativeLanguage) throws {
        let course = try ContentLoader.loadCourse(folder: language.contentFolder)
        #expect(course.sourceLang == language.rawValue)
        #expect(course.title.contains(language.name))
        let lessons = try lessons(language)
        #expect(lessons.count == 22)
        for lesson in lessons {
            #expect(lesson.validationProblems().isEmpty, "\(language.name) \(lesson.id): \(lesson.validationProblems())")
            #expect(language.containsScript(lesson.introNative), "\(lesson.id) intro")
            for phrase in lesson.phrases { #expect(language.containsScript(phrase.native), "\(lesson.id).\(phrase.id)") }
            for step in lesson.steps {
                if let prompt = step.promptNative { #expect(language.containsScript(prompt), "\(lesson.id).\(step.id) prompt") }
                if let explanation = step.explanationNative { #expect(language.containsScript(explanation), "\(lesson.id).\(step.id)") }
            }
        }
    }

    @Test func theEnglishIsTheSameInEveryLanguage() throws {
        let tamil = try lessons(.tamil), hindi = try lessons(.hindi)
        #expect(tamil.map(\.id) == hindi.map(\.id))
        for (t, h) in zip(tamil, hindi) {
            #expect(t.intro == h.intro && t.title == h.title)
            #expect(t.phrases.map(\.text) == h.phrases.map(\.text))
            #expect(t.steps.map(\.id) == h.steps.map(\.id))
            #expect(t.steps.map(\.answer) == h.steps.map(\.answer))
            #expect(t.steps.map(\.options) == h.steps.map(\.options))
        }
    }

    @Test(arguments: NativeLanguage.allCases)
    func everyMistakeRuleIsExplainedInEveryLanguage(language: NativeLanguage) {
        let notes = RuleNotes.notes(for: language)
        for rule in MistakeRules.all {
            let note = notes[rule.id]
            #expect(note.map(language.containsScript) == true, "\(language.name) \(rule.id)")
        }
    }

    @Test func scenariosUseTheLanguagesCity() {
        let hindi = ScenarioLoader.loadAll(folder: NativeLanguage.hindi.contentFolder)
        let tamil = ScenarioLoader.loadAll(folder: NativeLanguage.tamil.contentFolder)
        #expect(hindi.count == tamil.count)
        #expect(hindi.contains { $0.situation.contains("Pune") })
        #expect(!hindi.contains { $0.situation.contains("Chennai") })
    }

    @Test func switchingLanguageRewritesReviewCards() throws {
        let ctx = ModelContext(try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let tamil = try lessons(.tamil), hindi = try lessons(.hindi)
        LearningStore.addCards(from: tamil[0], in: ctx)
        let before = try ctx.fetch(FetchDescriptor<ReviewCard>())
        #expect(before.contains { NativeLanguage.tamil.containsScript($0.front) })
        LearningStore.relocalizeCards(lessons: hindi, in: ctx)
        let after = try ctx.fetch(FetchDescriptor<ReviewCard>())
        #expect(after.count == before.count)
        for card in after where card.kind == .phrase { #expect(NativeLanguage.hindi.containsScript(card.front), "\(card.id)") }
    }

    @Test func languageDetails() {
        #expect(NativeLanguage.hindi.containsScript("नमस्ते"))
        #expect(!NativeLanguage.hindi.containsScript("வணக்கம்"))
        #expect(NativeLanguage.tamil.contentFolder == "ta-en")
        #expect(NativeLanguage.hindi.romanisedName == "Hinglish")
        #expect(LearningFocus.guess(from: "naukri badalni hai") == .interviews)
    }

    @Test func askAnswersKeepOnlyTheEnglish() {
        let answer = """
        Here are a couple of options:
        **English:** "Could I please request a day off tomorrow?"
        **Hindi:** आप मैनेजर से विनम्रता से पूछ सकते हैं।
        *(Aap manager se vinamrata se pooch sakte hain.)*
        """
        #expect(AskNativeView.englishSentences(in: answer) == ["Could I please request a day off tomorrow?"])
    }
}

@Suite("Listening")
struct ListeningTests {
    @Test func readsMeaningAndSay() {
        let reply = "MEANING: How do I ask the client to extend the deadline?\nSAY: \"Could we discuss extending the deadline?\""
        let parsed = Listening.parse(reply)
        #expect(parsed.meaning == "How do I ask the client to extend the deadline?")
        #expect(parsed.say == "Could we discuss extending the deadline?")
        #expect(Listening.parse("nonsense").say.isEmpty)
    }

    @Test func promptsNameTheLearnersLanguage() {
        #expect(Listening.meaningSystem(.hindi).contains("Hindi"))
        #expect(Listening.meaningSystem(.tamil).contains("Tamil script"))
        #expect(Listening.transcribeInstruction.contains("Do not translate"))
    }
}
