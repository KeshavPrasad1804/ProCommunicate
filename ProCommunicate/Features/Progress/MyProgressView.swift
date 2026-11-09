import SwiftData
import SwiftUI

/// Progress, streak, recordings and what's coming (FEATURES.md §3 E–G).
/// Named `MyProgressView` to avoid clashing with SwiftUI's `ProgressView`.
struct MyProgressView: View {
    @Environment(\.modelContext) private var context
    @Query private var practiceDays: [PracticeDay]
    @Query private var lessonsDone: [LessonProgressRecord]
    @Query private var cards: [ReviewCard]
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]

    var body: some View {
        let weekStart = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let week = practiceDays.filter { $0.day >= weekStart }
        NavigationStack {
            List {
                Section("This week") {
                    LabeledContent("Practice time", value: "\(week.reduce(0) { $0 + $1.minutes }) min")
                    LabeledContent("Day streak", value: "\(LearningStore.streak(practiceDays: practiceDays.map(\.day)))")
                    LabeledContent("Days practised", value: "\(week.count) of 7")
                    WeekBars(days: practiceDays)
                        .frame(height: 90)
                        .padding(.vertical, 6)
                }
                Section("All time") {
                    LabeledContent("Lessons completed", value: "\(lessonsDone.count)")
                    LabeledContent("Phrases and fixes in review", value: "\(cards.count)")
                    LabeledContent("Remembered well", value: "\(cards.filter { $0.stability >= 21 }.count)")
                }
                Section {
                    if recordings.isEmpty {
                        Text("Your stand-up drills and calls will appear here, so you can listen back and hear yourself improve.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recordings) { recording in
                            RecordingRow(recording: recording)
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) { delete(recording) }
                                    Button(recording.starred ? "Unstar" : "Star", systemImage: "star") {
                                        recording.starred.toggle()
                                    }
                                    .tint(.yellow)
                                }
                        }
                    }
                } header: {
                    Text("Recordings")
                } footer: {
                    if !recordings.isEmpty {
                        Text("Swipe left to star or delete. Recordings stay on this iPhone.")
                    }
                }
                Section("Coming next") {
                    FeatureRow(systemImage: "exclamationmark.bubble.fill", title: "My Mistakes",
                               detail: "Every mistake from your calls, grouped by pattern, until you stop making it.", phase: "3")
                    FeatureRow(systemImage: "gauge.with.dots.needle.67percent", title: "Fluency tracker",
                               detail: "Speaking speed, fillers like 'umm' and 'actually', and long pauses over time.", phase: "4")
                    FeatureRow(systemImage: "doc.text.fill", title: "Weekly report",
                               detail: "What improved, and what to focus on next week.", phase: "4")
                }
            }
            .navigationTitle("Progress")
            .toolbar { SettingsToolbarButton() }
        }
    }

    private func delete(_ recording: Recording) {
        if AudioPlayback.shared.playingURL == recording.fileURL { AudioPlayback.shared.stop() }
        try? FileManager.default.removeItem(at: recording.fileURL)
        context.delete(recording)
        try? context.save()
    }
}

/// Minutes practised on each of the last 7 days.
struct WeekBars: View {
    let days: [PracticeDay]

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let week = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let minutes = week.map { day in days.first { $0.day == day }?.minutes ?? 0 }
        let maxMinutes = max(10, minutes.max() ?? 0)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(zip(week, minutes)), id: \.0) { day, value in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(value > 0 ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(height: max(4, 60 * CGFloat(value) / CGFloat(maxMinutes)))
                    Text(day, format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                        .foregroundStyle(calendar.isDateInToday(day) ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Minutes practised this week: \(minutes.map(String.init).joined(separator: ", "))")
    }
}

#Preview {
    MyProgressView()
        .environment(AppRouter())
        .modelContainer(for: AppSchema.models, inMemory: true)
}
