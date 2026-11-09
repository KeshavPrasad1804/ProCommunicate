import Foundation
import SwiftData

/// Writes learning activity: review cards from lessons, review grades, practice time and streaks.
@MainActor
enum LearningStore {
    static let scheduler = FSRS()

    // MARK: Cards

    /// Adds a lesson's phrases and its fix-the-mistake items to review (once), due tomorrow.
    static func addCards(from lesson: Lesson, now: Date = .now, in context: ModelContext) {
        let due = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        var cards: [ReviewCard] = lesson.phrases.map {
            ReviewCard(id: "\(lesson.id).\($0.id)", kind: .phrase, front: $0.native, back: $0.text,
                       hint: $0.note, lessonId: lesson.id, due: due, createdAt: now)
        }
        for step in lesson.steps where step.type == .fix {
            guard let wrong = step.wrong, let answer = step.answer else { continue }
            cards.append(ReviewCard(id: "\(lesson.id).\(step.id)", kind: .mistake, front: wrong, back: answer,
                                    hint: step.explanationNative ?? step.explanation, lessonId: lesson.id,
                                    due: due, createdAt: now))
        }
        let existing = Set(((try? context.fetch(FetchDescriptor<ReviewCard>())) ?? []).map(\.id))
        for card in cards where !existing.contains(card.id) {
            context.insert(card)
        }
        try? context.save()
    }

    /// After the learner changes their language: rewrites lesson cards' meanings and hints in the new
    /// language (progress and schedules are kept).
    static func relocalizeCards(lessons: [Lesson], in context: ModelContext) {
        var phrases: [String: Phrase] = [:]
        var steps: [String: LessonStep] = [:]
        for lesson in lessons {
            for phrase in lesson.phrases { phrases["\(lesson.id).\(phrase.id)"] = phrase }
            for step in lesson.steps where step.type == .fix { steps["\(lesson.id).\(step.id)"] = step }
        }
        for card in (try? context.fetch(FetchDescriptor<ReviewCard>())) ?? [] {
            if card.kind == .phrase, let phrase = phrases[card.id] {
                card.front = phrase.native
            } else if card.kind == .mistake, let step = steps[card.id] {
                card.hint = step.explanationNative ?? step.explanation
            }
        }
        try? context.save()
    }

    static func dueCards(now: Date = .now, in context: ModelContext) -> [ReviewCard] {
        let descriptor = FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.due <= now },
                                                     sortBy: [SortDescriptor(\.due)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Grading

    /// Applies a grade with FSRS and schedules the next review.
    static func grade(_ card: ReviewCard, _ grade: ReviewGrade, now: Date = .now) {
        let state: MemoryState
        if card.isNew {
            state = scheduler.initialState(grade: grade)
        } else {
            let elapsed = card.lastReview.map { now.timeIntervalSince($0) / 86_400 } ?? 0
            state = scheduler.next(MemoryState(stability: card.stability, difficulty: card.difficulty),
                                   grade: grade, elapsedDays: elapsed)
        }
        card.stability = state.stability
        card.difficulty = state.difficulty
        card.reps += 1
        if grade == .again { card.lapses += 1 }
        card.lastReview = now
        card.due = grade == .again
            ? now.addingTimeInterval(10 * 60)   // forgotten: see it again in 10 minutes
            : now.addingTimeInterval(scheduler.intervalDays(stability: state.stability) * 86_400)
    }

    /// What each button would schedule, for labels like "Good · 3d".
    static func preview(_ card: ReviewCard, now: Date = .now) -> [ReviewGrade: String] {
        var labels: [ReviewGrade: String] = [:]
        for grade in ReviewGrade.allCases {
            if grade == .again { labels[grade] = "10m"; continue }
            let state = card.isNew
                ? scheduler.initialState(grade: grade)
                : scheduler.next(MemoryState(stability: card.stability, difficulty: card.difficulty), grade: grade,
                                 elapsedDays: card.lastReview.map { now.timeIntervalSince($0) / 86_400 } ?? 0)
            labels[grade] = shortDuration(days: scheduler.intervalDays(stability: state.stability))
        }
        return labels
    }

    static func shortDuration(days: Double) -> String {
        switch days {
        case ..<1.5: "1d"
        case ..<30: "\(Int(days))d"
        case ..<365: "\(Int((days / 30).rounded()))mo"
        default: "1y"
        }
    }

    // MARK: Practice time and streak

    enum Activity { case lesson, review, drill, call }

    static func log(_ activity: Activity, seconds: Double, now: Date = .now, in context: ModelContext) {
        let day = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<PracticeDay>(predicate: #Predicate { $0.day == day })
        let record = (try? context.fetch(descriptor).first) ?? {
            let new = PracticeDay(day: day)
            context.insert(new)
            return new
        }()
        record.seconds += max(0, min(seconds, 3 * 3600))
        switch activity {
        case .lesson: record.lessons += 1
        case .review: record.reviews += 1
        case .drill: record.drills += 1
        case .call: record.calls += 1
        }
        try? context.save()
    }

    /// Consecutive days with practice, ending today (or yesterday, if today isn't done yet).
    static func streak(practiceDays: [Date], today: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(practiceDays.map { calendar.startOfDay(for: $0) })
        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
