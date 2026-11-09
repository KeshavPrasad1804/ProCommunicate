import Foundation
import Observation

/// Result of checking one answer.
struct StepResult: Equatable, Sendable {
    let correct: Bool
    let expected: String
}

/// Runs one lesson: the order of steps, checking answers, and bringing missed steps back at the end.
@MainActor @Observable
final class LessonSession {
    let lesson: Lesson
    /// The steps still to do, in order. Missed steps are appended again at the end.
    private(set) var queue: [LessonStep]
    private(set) var position: Int
    /// Set after checking the current step; cleared when moving on.
    private(set) var lastResult: StepResult?
    /// Graded steps answered correctly on the first try.
    private(set) var firstTryCorrect: Set<String> = []
    /// Graded steps that were answered wrongly at least once.
    private(set) var missed: Set<String> = []

    init(lesson: Lesson, startAt: Int = 0) {
        self.lesson = lesson
        self.queue = lesson.steps
        self.position = min(max(0, startAt), lesson.steps.count)
    }

    var current: LessonStep? { position < queue.count ? queue[position] : nil }
    var isFinished: Bool { position >= queue.count }
    var progress: Double { queue.isEmpty ? 1 : Double(position) / Double(queue.count) }
    var gradedCount: Int { lesson.gradedSteps.count }

    /// Share of graded steps right on the first try, 0…1.
    var score: Double {
        gradedCount == 0 ? 1 : Double(firstTryCorrect.count) / Double(gradedCount)
    }

    /// Checks an answer for the current graded step. A wrong answer brings the step back at the end.
    @discardableResult
    func check(_ answer: String) -> StepResult? {
        guard let step = current, step.isGraded, lastResult == nil, let expected = step.answer else { return nil }
        let correct = AnswerChecker.isCorrect(answer, expected: expected)
        if correct {
            if !missed.contains(step.id) { firstTryCorrect.insert(step.id) }
        } else {
            missed.insert(step.id)
            queue.append(step)
        }
        let result = StepResult(correct: correct, expected: expected)
        lastResult = result
        return result
    }

    /// Moves to the next step. Learn and speak steps can always move on; graded ones after checking.
    func advance() {
        guard let step = current else { return }
        guard !step.isGraded || lastResult != nil else { return }
        lastResult = nil
        position += 1
    }
}
