import SwiftData
import SwiftUI

/// Course map: tracks in priority order, each with its units.
struct LearnView: View {
    let course: Course
    @Query private var progress: [LessonProgressRecord]

    var body: some View {
        let completedUnits = Set(progress.map(\.unitId))
        NavigationStack {
            List {
                ForEach(course.tracksByPriority) { track in
                    Section {
                        ForEach(track.units) { unit in
                            NavigationLink(value: unit) {
                                UnitRow(unit: unit, completed: completedUnits.contains(unit.id))
                            }
                        }
                    } header: {
                        Label(track.title, systemImage: track.systemImage)
                    } footer: {
                        Text(track.subtitle)
                    }
                }
            }
            .navigationTitle("Learn")
            .navigationDestination(for: CourseUnit.self) { unit in
                UnitDetailView(unit: unit)
            }
        }
    }
}

private struct UnitRow: View {
    let unit: CourseUnit
    let completed: Bool

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
