import SwiftData
import SwiftUI

/// The daily 20-minute session from FEATURES.md §2.
struct TodayView: View {
    let course: Course

    @Environment(AppRouter.self) private var router
    @Query private var progress: [LessonProgressRecord]
    @State private var lessons: [Lesson] = []

    private struct Step: Identifiable {
        let id = UUID()
        let minutes: Int
        let systemImage: String
        let title: String
        let detail: String
        let phase: String
    }

    private let laterSteps: [Step] = [
        Step(minutes: 6, systemImage: "phone.fill", title: "Speak with the AI",
             detail: "A short client-call or interview role-play using today's phrases.", phase: "3"),
        Step(minutes: 3, systemImage: "checkmark.seal.fill", title: "Today's fix",
             detail: "Your #1 mistake, explained in Tamil, said correctly 3 times.", phase: "3"),
    ]

    private let earlierSteps: [Step] = [
        Step(minutes: 2, systemImage: "person.wave.2.fill", title: "Stand-up drill",
             detail: "Say your real yesterday / today / blockers update out loud. One fix each day.", phase: "2"),
        Step(minutes: 3, systemImage: "arrow.trianglehead.2.clockwise", title: "Warm-up review",
             detail: "Say the phrases and fixes due today.", phase: "2"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your 20 minutes")
                            .font(.title2.bold())
                        Text("Focus: speaking in client meetings, then job interviews.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("Today's session") {
                    ForEach(earlierSteps) { row($0) }
                    lessonRow
                    ForEach(laterSteps) { row($0) }
                }
                Section("This week") {
                    FeatureRow(systemImage: "person.3.fill", title: "Client meeting simulation",
                               detail: "A full status call with a UK client, as a voice call.", phase: "4")
                }
            }
            .navigationTitle("Today")
            .toolbar { SettingsToolbarButton() }
            .task { lessons = Self.loadLessons(for: course) }
        }
    }

    private func row(_ step: Step) -> some View {
        FeatureRow(systemImage: step.systemImage, title: "\(step.title) · \(step.minutes) min",
                   detail: step.detail, phase: step.phase)
    }

    /// The first lesson (in priority order) you haven't finished yet, or the first one to practise again.
    @ViewBuilder
    private var lessonRow: some View {
        let done = Set(progress.map(\.lessonId))
        if let next = lessons.first(where: { !done.contains($0.id) }) ?? lessons.first {
            let isDone = done.contains(next.id)
            Button {
                router.open(next)
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "book.fill")
                        .font(.title3)
                        .foregroundStyle(isDone ? Color.green : Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's lesson · 6 min").font(.headline)
                        Text(next.title).font(.subheadline.weight(.medium))
                        Text(isDone ? "Done. Practise it again any time." : next.intro)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    static func loadLessons(for course: Course) -> [Lesson] {
        course.tracksByPriority.flatMap(\.units).compactMap { try? ContentLoader.loadLesson(unitId: $0.id) }
    }
}

#Preview {
    TodayView(course: .preview)
        .environment(AppRouter())
        .modelContainer(for: LessonProgressRecord.self, inMemory: true)
}
