import Foundation
import Testing
@testable import ProCommunicate

@Suite("Lesson content")
struct LessonContentTests {
    @Test func statusUpdateLessonLoadsAndIsValid() throws {
        let lesson = try #require(try ContentLoader.loadLesson(unitId: "meetings-03-status"))
        #expect(lesson.validationProblems() == [])
        #expect(lesson.phrases.count == 5)
        #expect(lesson.gradedSteps.count == 8)
    }

    @Test func everyLessonBelongsToARealUnit() throws {
        let course = try ContentLoader.loadCourse()
        let unitIds = Set(course.tracks.flatMap(\.units).map(\.id))
        let lesson = try #require(try ContentLoader.loadLesson(unitId: "meetings-03-status"))
        #expect(unitIds.contains(lesson.unitId))
    }

    @Test func everyUnitHasAValidLesson() throws {
        let course = try ContentLoader.loadCourse()
        for unit in course.tracks.flatMap(\.units) {
            let lesson = try #require(try ContentLoader.loadLesson(unitId: unit.id), "missing lesson for \(unit.id)")
            #expect(lesson.validationProblems() == [], "\(unit.id)")
            #expect(lesson.unitId == unit.id)
            #expect(lesson.phrases.count == 5, "\(unit.id)")
        }
    }

    @Test func unknownUnitReturnsNil() throws {
        #expect(try ContentLoader.loadLesson(unitId: "no-such-unit") == nil)
    }

    @Test func modelPhrasesNeverTriggerTheMistakeRules() throws {
        let course = try ContentLoader.loadCourse()
        for unit in course.tracks.flatMap(\.units) {
            guard let lesson = try ContentLoader.loadLesson(unitId: unit.id) else { continue }
            for phrase in lesson.phrases.map(\.text) {
                #expect(MistakeRules.check(phrase).isEmpty, "\(unit.id): \(phrase)")
            }
        }
    }
}

@Suite("Answer checking")
struct AnswerCheckerTests {
    @Test(arguments: [
        ("We’ve completed about 80% of the testing", "We've completed about 80% of the testing."),
        ("  we've   COMPLETED about 80% of the testing. ", "We've completed about 80% of the testing."),
        ("I'll share a written update after the call!", "I'll share a written update after the call."),
    ])
    func acceptsTheSameSentenceWrittenDifferently(given: String, expected: String) {
        #expect(AnswerChecker.isCorrect(given, expected: expected))
    }

    @Test func rejectsDifferentWords() {
        #expect(!AnswerChecker.isCorrect("We completed about 80% of the testing.", expected: "We've completed about 80% of the testing."))
        #expect(!AnswerChecker.isCorrect("I have one doubt.", expected: "I have a question."))
    }
}

@MainActor
@Suite("Lesson session")
struct LessonSessionTests {
    static let lesson = Lesson(
        id: "test", unitId: "u", title: "Test", intro: "", introNative: "", nativeReviewed: true,
        phrases: [Phrase(id: "p", text: "Hello.", native: "வணக்கம்.", note: nil)],
        steps: [
            LessonStep(id: "learn", type: .learn, phraseId: "p"),
            LessonStep(id: "q1", type: .choice, prompt: "?", options: ["A.", "B."], answer: "A."),
            LessonStep(id: "q2", type: .fix, prompt: "?", wrong: "b", options: ["A.", "B."], answer: "B."),
            LessonStep(id: "speak", type: .speak, prompt: "Say it"),
        ])

    @Test func allCorrectGivesFullScore() {
        let session = LessonSession(lesson: Self.lesson)
        session.advance()                       // learn
        #expect(session.check("A.")?.correct == true)
        session.advance()
        #expect(session.check("b")?.correct == true)   // case and full stop ignored
        session.advance()
        session.advance()                       // speak
        #expect(session.isFinished)
        #expect(session.score == 1)
    }

    @Test func wrongAnswerComesBackAtTheEndAndCostsTheFirstTryPoint() {
        let session = LessonSession(lesson: Self.lesson)
        session.advance()
        #expect(session.check("B.")?.correct == false)
        #expect(session.queue.count == 5)
        session.advance()
        session.check("B.")
        session.advance()
        session.advance()                       // speak
        #expect(session.current?.id == "q1")    // the missed question again
        #expect(session.check("A.")?.correct == true)
        session.advance()
        #expect(session.isFinished)
        #expect(session.score == 0.5)           // q2 first try, q1 only on retry
    }

    @Test func gradedStepCannotBeSkippedWithoutChecking() {
        let session = LessonSession(lesson: Self.lesson)
        session.advance()
        session.advance()                       // not checked yet: stays
        #expect(session.current?.id == "q1")
    }

    @Test func cannotCheckTwice() {
        let session = LessonSession(lesson: Self.lesson)
        session.advance()
        session.check("B.")
        #expect(session.check("A.") == nil)
        #expect(session.queue.count == 5)
    }

    @Test func progressGoesFromZeroToOne() {
        let session = LessonSession(lesson: Self.lesson)
        #expect(session.progress == 0)
        let finished = LessonSession(lesson: Self.lesson, startAt: 99)
        #expect(finished.isFinished)
        #expect(finished.progress == 1)
    }
}
