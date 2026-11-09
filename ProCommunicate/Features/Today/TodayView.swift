import SwiftData
import SwiftUI

/// The daily session from FEATURES.md §2: stand-up drill, review, lesson, then AI practice.
struct TodayView: View {
    let course: Course

    @Environment(AppRouter.self) private var router
    @Query private var progress: [LessonProgressRecord]
    @Query private var cards: [ReviewCard]
    @Query private var practiceDays: [PracticeDay]
    @Query(sort: [SortDescriptor(\MistakeRecord.lastSeen, order: .reverse)]) private var mistakes: [MistakeRecord]
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = 20
    @State private var lessons: [Lesson] = []
    @State private var scenarios: [CallScenario] = []

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let todayRecord = practiceDays.first { $0.day == today }
        let streak = LearningStore.streak(practiceDays: practiceDays.map(\.day))
        let dueCount = cards.filter { $0.due <= .now }.count

        NavigationStack {
            List {
                Section {
                    DailyGoalHeader(minutes: todayRecord?.minutes ?? 0, goal: dailyGoal, streak: streak)
                }
                Section("Today's session") {
                    ActionRow(systemImage: "person.wave.2.fill", title: "Stand-up drill · 2 min",
                              detail: (todayRecord?.drills ?? 0) > 0
                                ? "Done today. Do another, or listen back in Progress."
                                : "Say your real yesterday / today / blockers update out loud.",
                              done: (todayRecord?.drills ?? 0) > 0) {
                        router.showStandUpDrill = true
                    }
                    ActionRow(systemImage: "arrow.trianglehead.2.clockwise", title: "Warm-up review · 3 min",
                              detail: reviewDetail(due: dueCount, total: cards.count),
                              done: !cards.isEmpty && dueCount == 0, enabled: dueCount > 0) {
                        router.showReviewSession = true
                    }
                    lessonRow
                    if let roleplay = todaysRolePlay {
                        ActionRow(systemImage: "phone.fill", title: "Speak with the AI · 6 min", subtitle: roleplay.title,
                                  detail: "A short voice call with \(roleplay.aiName), \(roleplay.aiRole).",
                                  done: (todayRecord?.calls ?? 0) > 0) {
                            router.startCall(roleplay)
                        }
                    }
                    if let fix = todaysFix {
                        NavigationLink {
                            MistakeDetailView(mistake: fix)
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "checkmark.seal.fill").font(.title3).foregroundStyle(.orange).frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Today's fix · 3 min").font(.headline)
                                    Text("\(fix.wrong) → \(fix.right)").font(.subheadline.weight(.medium))
                                    Text("Heard \(fix.count)×. Hear it, read why in Tamil, say it right 3 times.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        FeatureRow(systemImage: "checkmark.seal.fill", title: "Today's fix · 3 min",
                                   detail: "After your first call or drill, your #1 mistake shows up here.")
                    }
                }
                if let weekly = weeklyCall {
                    Section {
                        NavigationLink {
                            ScenarioStartView(scenario: weekly)
                        } label: {
                            FeatureRow(systemImage: weekly.kind == .interview ? "briefcase.fill" : "person.3.fill",
                                       title: weekly.title, detail: weekly.subtitle)
                        }
                    } header: {
                        Text(weekly.kind == .interview ? "This week: mock interview" : "This week: client meeting")
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar { SettingsToolbarButton() }
            .task {
                lessons = Self.loadLessons(for: course)
                scenarios = ScenarioLoader.loadAll()
            }
        }
    }

    /// A quick role-play for the next lesson's unit, or a status call by default.
    private var todaysRolePlay: CallScenario? {
        let done = Set(progress.map(\.lessonId))
        let unitId = (lessons.first { !done.contains($0.id) } ?? lessons.first)?.unitId
        let quick = scenarios.filter { $0.kind == .quick }
        return quick.first { $0.unitId == unitId } ?? quick.first { $0.id == "quick-status" } ?? quick.first
    }

    /// Your most repeated mistake from the last two weeks.
    private var todaysFix: MistakeRecord? {
        mistakes.filter { Date().timeIntervalSince($0.lastSeen) < 14 * 86_400 }.max { ($0.count, $0.lastSeen) < ($1.count, $1.lastSeen) }
    }

    /// Alternates weekly: client meeting one week, mock interview the next.
    private var weeklyCall: CallScenario? {
        let week = Calendar.current.component(.weekOfYear, from: .now)
        let kind: CallScenario.Kind = week.isMultiple(of: 2) ? .meeting : .interview
        let options = scenarios.filter { $0.kind == kind }
        return options.isEmpty ? nil : options[(week / 2) % options.count]
    }

    private func reviewDetail(due: Int, total: Int) -> String {
        if total == 0 { return "Finish a lesson first; its phrases come back here." }
        if due == 0 { return "All caught up. Nothing due right now." }
        return "\(due) \(due == 1 ? "card" : "cards") due. Say each one out loud."
    }

    /// The first lesson (in priority order) you haven't finished yet, or the first one to practise again.
    @ViewBuilder
    private var lessonRow: some View {
        let done = Set(progress.map(\.lessonId))
        if let next = lessons.first(where: { !done.contains($0.id) }) ?? lessons.first {
            let isDone = done.contains(next.id)
            ActionRow(systemImage: "book.fill", title: "Today's lesson · 6 min",
                      subtitle: next.title,
                      detail: isDone ? "Done. Practise it again any time." : next.intro,
                      done: isDone) {
                router.open(next)
            }
        }
    }

    static func loadLessons(for course: Course) -> [Lesson] {
        course.tracksByPriority.flatMap(\.units).compactMap { try? ContentLoader.loadLesson(unitId: $0.id) }
    }
}

/// Today's minutes against the daily goal, plus the streak.
struct DailyGoalHeader: View {
    let minutes: Int
    let goal: Int
    let streak: Int

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(1, Double(minutes) / Double(max(goal, 1))))
                    .stroke(minutes >= goal ? Color.green : Color.accentColor,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(minutes)").font(.title3.bold().monospacedDigit())
                    Text("of \(goal)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(minutes) of \(goal) minutes today")

            VStack(alignment: .leading, spacing: 6) {
                Text(minutes >= goal ? "Goal done for today!" : "Your \(goal) minutes")
                    .font(.title3.bold())
                Label(streak == 0 ? "Start a streak today" : "\(streak)-day streak",
                      systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(streak > 0 ? .orange : .secondary)
                Text("Focus: client meetings, then interviews.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

/// A tappable session row with a done tick.
struct ActionRow: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    let detail: String
    var done = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: done ? "checkmark.circle.fill" : systemImage)
                    .font(.title3)
                    .foregroundStyle(done ? Color.green : Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.subheadline.weight(.medium)) }
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if enabled {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

#Preview {
    TodayView(course: .preview)
        .environment(AppRouter())
        .modelContainer(for: AppSchema.models, inMemory: true)
}
