import Foundation
import Observation

/// What the AI has written for you, cached in one small JSON file so Today opens instantly and the
/// AI only runs when something has changed (a new day, a new week, a new goal).
struct AdaptiveContent: Codable, Equatable, Sendable {
    /// The AI's reading of your "preparing for" text.
    struct FocusResult: Codable, Equatable, Sendable {
        var target: String
        var focus: LearningFocus
    }

    /// A phrase written for your real job, for one day.
    struct DailyPhrase: Codable, Equatable, Sendable {
        var day: String
        var unitId: String
        var english: String
        var tamil: String
        var when: String
    }

    /// This week's challenge call, written around your project and weak spots.
    struct WeeklyChallenge: Codable, Equatable, Sendable {
        var week: String
        var baseScenarioId: String
        var title: String
        var subtitle: String
        var situation: String
        var goals: [String]
    }

    /// A real meeting or interview you told the app about.
    struct UpcomingEvent: Codable, Equatable, Sendable, Identifiable {
        var id = UUID()
        var title: String
        var who: String
        var date: Date
        var phrases: [String] = []
    }

    /// This week's challenge scenario, pinned once chosen so it doesn't change mid-week.
    struct WeeklyPick: Codable, Equatable, Sendable {
        var week: String
        var scenarioId: String
    }

    var aiFocus: FocusResult?
    var weeklyPick: WeeklyPick?
    var phrase: DailyPhrase?
    var weekly: WeeklyChallenge?
    var events: [UpcomingEvent] = []
}

@MainActor @Observable
final class AdaptiveStore {
    static let shared = AdaptiveStore()

    /// UserDefaults key for the focus you chose in Settings ("auto" or a LearningFocus).
    static let focusKey = "adaptive.focus"

    private(set) var content: AdaptiveContent
    @ObservationIgnored let fileURL: URL

    init(fileURL: URL = AdaptiveStore.defaultURL) {
        self.fileURL = fileURL
        content = (try? JSONDecoder().decode(AdaptiveContent.self, from: Data(contentsOf: fileURL))) ?? AdaptiveContent()
    }

    nonisolated static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Adaptive/content.json")
    }

    func update(_ change: (inout AdaptiveContent) -> Void) {
        var copy = content
        change(&copy)
        guard copy != content else { return }
        content = copy
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(content).write(to: fileURL, options: .atomic)
        } catch {
            // A cache: if it can't be written, the AI simply writes it again next time.
        }
    }

    // MARK: - Focus

    /// Your choice in Settings wins; then the AI's reading of your goal; then a keyword guess.
    func focus(target: String, choice: String = UserDefaults.standard.string(forKey: AdaptiveStore.focusKey) ?? "auto") -> LearningFocus {
        if let chosen = LearningFocus(rawValue: choice) { return chosen }
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ai = content.aiFocus, ai.target == trimmed { return ai.focus }
        return LearningFocus.guess(from: trimmed)
    }

    // MARK: - Events

    func addEvent(_ event: AdaptiveContent.UpcomingEvent) {
        update { content in
            content.events.removeAll { abs($0.date.timeIntervalSince(event.date)) < 60 && $0.title == event.title }
            content.events.append(event)
        }
    }

    func removeEvent(_ id: UUID) {
        update { $0.events.removeAll { $0.id == id } }
    }

    /// Forgets meetings that are over.
    func pruneEvents(now: Date = .now) {
        let today = Calendar.current.startOfDay(for: now)
        update { $0.events.removeAll { $0.date < today } }
    }

    /// The next real meeting from today on.
    func nextEvent(now: Date = .now) -> UpcomingEventInfo? {
        let today = Calendar.current.startOfDay(for: now)
        return content.events.filter { $0.date >= today }.min { $0.date < $1.date }
            .map { UpcomingEventInfo(title: $0.title, who: $0.who, date: $0.date, phrases: $0.phrases) }
    }
}
