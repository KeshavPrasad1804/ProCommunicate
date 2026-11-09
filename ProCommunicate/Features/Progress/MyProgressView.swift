import SwiftData
import SwiftUI

/// Progress: weekly report, fluency over time, calls, mistakes and recordings (FEATURES.md §3 E–G).
/// Named `MyProgressView` to avoid clashing with SwiftUI's `ProgressView`.
struct MyProgressView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var practiceDays: [PracticeDay]
    @Query private var lessonsDone: [LessonProgressRecord]
    @Query private var cards: [ReviewCard]
    @Query(sort: \CallRecord.startedAt, order: .reverse) private var calls: [CallRecord]
    @Query private var mistakes: [MistakeRecord]
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]

    var body: some View {
        let report = WeeklyReport(days: practiceDays, calls: calls, mistakes: mistakes)
        NavigationStack {
            List {
                Section {
                    WeeklyReportCard(report: report)
                    WeekBars(days: practiceDays).frame(height: 90).padding(.vertical, 6)
                } header: {
                    Text("This week")
                }

                Section {
                    if calls.count < 1 {
                        Text("After your first call, your speaking speed, fillers and pauses are tracked here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        let recent = Array(calls.prefix(10).reversed())
                        TrendRow(title: "Speaking speed", unit: "words/min", values: recent.map(\.wordsPerMinute), higherIsBetter: true)
                        TrendRow(title: "Fillers per minute", unit: "/min", values: recent.map(\.fillersPerMinute), higherIsBetter: false)
                        TrendRow(title: "Long pauses per call", unit: "", values: recent.map { Double($0.longPauses) }, higherIsBetter: false)
                        TrendRow(title: "Mistakes per call", unit: "", values: recent.map { Double($0.mistakeCount) }, higherIsBetter: false)
                    }
                } header: {
                    Text("Fluency over your last calls")
                }

                Section {
                    NavigationLink {
                        MistakesView()
                    } label: {
                        LabeledContent {
                            Text("\(mistakes.count)")
                        } label: {
                            Label("My Mistakes", systemImage: "exclamationmark.bubble.fill")
                        }
                    }
                    LabeledContent("Lessons completed", value: "\(lessonsDone.count)")
                    LabeledContent("Calls", value: "\(calls.count)")
                    LabeledContent("Cards in review", value: "\(cards.count)")
                    LabeledContent("Remembered well", value: "\(cards.filter { $0.stability >= 21 }.count)")
                } header: {
                    Text("All time")
                }

                if !calls.isEmpty {
                    Section("Calls") {
                        ForEach(calls.prefix(20)) { call in
                            Button {
                                router.openReport = call.id
                            } label: {
                                HStack {
                                    Image(systemName: call.kind == "interview" ? "briefcase.fill" : (call.kind == "meeting" ? "person.3.fill" : "phone.fill"))
                                        .foregroundStyle(.tint).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(call.title).font(.subheadline.weight(.medium))
                                        Text(call.reportPending
                                             ? "\(call.startedAt.formatted(date: .abbreviated, time: .shortened)) · report being prepared…"
                                             : "\(call.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(call.wordsPerMinute)) wpm · \(call.mistakeCount) fixes")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    if recordings.isEmpty {
                        Text("Your stand-up drills and answer retries will appear here, so you can hear yourself improve.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recordings) { recording in
                            VStack(alignment: .leading, spacing: 4) {
                                RecordingRow(recording: recording)
                                if let transcript = recording.transcript {
                                    Text(transcript).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
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
                        Text("Swipe left to star or delete. Recordings stay on this iPhone. Call answers are in each call's report.")
                    }
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

/// The weekly report: what you did, what's improving, and what to focus on next.
@MainActor
struct WeeklyReport {
    let minutes: Int
    let daysPractised: Int
    let streak: Int
    let callsThisWeek: Int
    let topMistake: MistakeRecord?
    let improved: [MistakeRecord]
    let speedChange: Double?

    init(days: [PracticeDay], calls: [CallRecord], mistakes: [MistakeRecord], now: Date = .now) {
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let week = days.filter { $0.day >= weekStart }
        minutes = week.reduce(0) { $0 + $1.minutes }
        daysPractised = week.count
        streak = LearningStore.streak(practiceDays: days.map(\.day), today: now)
        let thisWeekCalls = calls.filter { $0.startedAt >= weekStart }
        callsThisWeek = thisWeekCalls.count
        topMistake = mistakes.filter { $0.lastSeen >= weekStart }.max { $0.count < $1.count }
        // Mistakes you made before but not in the last two weeks (and you've practised since).
        improved = mistakes.filter { $0.count >= 2 && now.timeIntervalSince($0.lastSeen) > 14 * 86_400 }
        let earlier = calls.filter { $0.startedAt < weekStart && $0.learnerSeconds > 10 }.prefix(5)
        if !thisWeekCalls.isEmpty, !earlier.isEmpty {
            let now = thisWeekCalls.map(\.wordsPerMinute).reduce(0, +) / Double(thisWeekCalls.count)
            let before = earlier.map(\.wordsPerMinute).reduce(0, +) / Double(earlier.count)
            speedChange = now - before
        } else {
            speedChange = nil
        }
    }
}

struct WeeklyReportCard: View {
    let report: WeeklyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You practised \(report.minutes) minutes on \(report.daysPractised) of 7 days\(report.callsThisWeek > 0 ? ", with \(report.callsThisWeek) \(report.callsThisWeek == 1 ? "call" : "calls")" : "").")
                .font(.headline)
            if report.streak > 0 {
                Label("\(report.streak)-day streak", systemImage: "flame.fill").foregroundStyle(.orange).font(.subheadline)
            }
            if let change = report.speedChange, abs(change) >= 5 {
                Label(change > 0 ? "You spoke \(Int(change)) words/min faster than before." : "You spoke \(Int(-change)) words/min slower than before.",
                      systemImage: "speedometer").font(.subheadline)
            }
            if !report.improved.isEmpty {
                Label("You stopped saying: \(report.improved.prefix(2).map { "\"\($0.wrong)\"" }.joined(separator: ", ")).",
                      systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.subheadline)
            }
            if let top = report.topMistake {
                Label("Next focus: \(top.title) → \(top.right)", systemImage: "target").font(.subheadline)
            } else if report.minutes == 0 {
                Label("Start with today's stand-up drill. Two minutes is enough.", systemImage: "target").font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A metric's last values as a mini chart with the latest value.
struct TrendRow: View {
    let title: String
    let unit: String
    let values: [Double]
    let higherIsBetter: Bool

    var body: some View {
        let latest = values.last ?? 0
        let first = values.first ?? 0
        let improving = values.count >= 2 && (higherIsBetter ? latest > first : latest < first)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(String(format: latest >= 10 ? "%.0f %@" : "%.1f %@", latest, unit))
                    .font(.headline.monospacedDigit())
            }
            Spacer()
            Sparkline(values: values, color: improving ? .green : .accentColor)
                .frame(width: 110, height: 32)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 0.001)
            let minValue = values.min() ?? 0
            let span = max(maxValue - minValue, 0.001)
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = values.count > 1 ? geo.size.width * CGFloat(index) / CGFloat(values.count - 1) : geo.size.width / 2
                    let y = geo.size.height * (1 - CGFloat((value - minValue) / span))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
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
