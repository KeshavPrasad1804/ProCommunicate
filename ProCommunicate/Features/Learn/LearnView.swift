import SwiftData
import SwiftUI

/// Course map: tracks in your focus order, each unit with how well you know it now.
struct LearnView: View {
    let course: Course
    @Query private var progress: [LessonProgressRecord]
    @Query private var cards: [ReviewCard]
    @Query private var calls: [CallRecord]
    @Query private var mistakes: [MistakeRecord]
    @AppStorage(LearnerProfile.Key.target) private var target = ""
    @AppStorage(AdaptiveStore.focusKey) private var focusChoice = "auto"
    @State private var lessons: [Lesson] = []

    var body: some View {
        let completedUnits = Set(progress.map(\.unitId))
        let focus = AdaptiveStore.shared.focus(target: target, choice: focusChoice)
        let snapshot = lessons.isEmpty ? nil : LearnerModel.snapshot(
            course: course, lessons: lessons, progress: progress, cards: cards, calls: calls, mistakes: mistakes,
            focus: focus, level: 1, upcoming: nil, scenarios: [])
        NavigationStack {
            List {
                ForEach(orderedTracks(focus)) { track in
                    Section {
                        ForEach(track.units) { unit in
                            NavigationLink(value: unit) {
                                UnitRow(unit: unit, completed: completedUnits.contains(unit.id),
                                        mastery: snapshot?.mastery(of: unit.id))
                            }
                        }
                    } header: {
                        HStack {
                            Label(track.title, systemImage: track.systemImage)
                            if isFocus(track, focus) {
                                Spacer()
                                Text("Your focus").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                            }
                        }
                    } footer: {
                        Text(track.subtitle)
                    }
                }
            }
            .navigationTitle("Learn")
            .task { if lessons.isEmpty { lessons = TodayView.loadLessons(for: course) } }
            .navigationDestination(for: CourseUnit.self) { unit in
                UnitDetailView(unit: unit)
            }
        }
    }
}

extension LearnView {
    private func orderedTracks(_ focus: LearningFocus) -> [Track] {
        let tracks = course.tracksByPriority
        guard focus == .interviews else { return tracks }
        return tracks.filter { $0.id == "interviews" } + tracks.filter { $0.id != "interviews" }
    }

    private func isFocus(_ track: Track, _ focus: LearningFocus) -> Bool {
        (focus == .meetings && track.id == "meetings") || (focus == .interviews && track.id == "interviews")
    }
}

private struct UnitRow: View {
    let unit: CourseUnit
    let completed: Bool
    var mastery: UnitMastery?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(completed ? Color.green : Color.accentColor.opacity(0.12))
                if completed {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(unit.number)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityLabel(completed ? "Completed" : "Unit \(unit.number)")
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.title).font(.body)
                Text(unit.goal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let mastery, mastery.started {
                    let score = mastery.score
                    HStack(spacing: 6) {
                        ProgressView(value: score)
                            .tint(score >= AdaptivePlanner.masteredScore ? .green : (score < AdaptivePlanner.weakScore ? .orange : .accentColor))
                            .frame(maxWidth: 90)
                        Text(score >= AdaptivePlanner.masteredScore ? "Mastered" : "\(Int((score * 100).rounded()))%\(score < AdaptivePlanner.weakScore ? " · needs a refresh" : "")")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Mastery \(Int((score * 100).rounded())) percent")
                }
            }
        }
    }
}

struct UnitDetailView: View {
    let unit: CourseUnit
    @Environment(AppRouter.self) private var router
    @Query private var progress: [LessonProgressRecord]
    @State private var lesson: Lesson?

    var body: some View {
        let record = progress.first { $0.unitId == unit.id }
        List {
            Section("You will be able to") {
                Text(unit.goal)
            }
            Section("Key phrases") {
                ForEach(unit.examplePhrases, id: \.self) { phrase in
                    Label(phrase, systemImage: "quote.opening")
                }
            }
            Section {
                if let lesson {
                    Button {
                        router.open(lesson)
                    } label: {
                        Label(record == nil ? "Start lesson" : "Practise again",
                              systemImage: record == nil ? "play.circle.fill" : "arrow.counterclockwise.circle.fill")
                            .font(.headline)
                    }
                    if let record {
                        LabeledContent("Best score", value: record.bestScore.formatted(.percent.precision(.fractionLength(0))))
                        LabeledContent("Completed", value: "\(record.timesCompleted)×")
                    }
                } else {
                    FeatureRow(systemImage: "play.circle.fill", title: "Lesson",
                               detail: "This unit's lesson isn't available yet.")
                }
                let roleplay = ScenarioLoader.forUnit(unit)
                Button {
                    router.startCall(roleplay)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "phone.fill").font(.title3).foregroundStyle(.green).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Practise on a call").font(.headline)
                            Text("A short voice role-play with \(roleplay.aiName), \(roleplay.aiRole), using this unit's phrases.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(unit.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { lesson = try? ContentLoader.loadLesson(unitId: unit.id) }
    }
}

#Preview {
    LearnView(course: .preview)
        .environment(AppRouter())
        .modelContainer(for: AppSchema.models, inMemory: true)
}
