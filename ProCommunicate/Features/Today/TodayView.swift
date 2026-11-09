import SwiftData
import SwiftUI

/// The landing page: a hero with your daily goal and one "Continue" button, today's plan as a
/// checklist (chosen for you by AdaptivePlanner, with the reason for each step), the phrase of the
/// day, and this week's challenge call.
struct TodayView: View {
    let course: Course

    @Environment(AppRouter.self) private var router
    @Query private var progress: [LessonProgressRecord]
    @Query private var cards: [ReviewCard]
    @Query private var practiceDays: [PracticeDay]
    @Query(sort: [SortDescriptor(\MistakeRecord.lastSeen, order: .reverse)]) private var mistakes: [MistakeRecord]
    @Query private var calls: [CallRecord]
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = 20
    @AppStorage(LearnerProfile.Key.name) private var name = ""
    @AppStorage(LearnerProfile.Key.target) private var target = ""
    @AppStorage(AdaptiveStore.focusKey) private var focusChoice = "auto"
    @AppStorage("speakingCheckWPM") private var checkWPM = 0.0
    @AppStorage("speakingCheckMistakes") private var checkMistakes = -1
    @State private var lessons: [Lesson] = []
    @State private var scenarios: [CallScenario] = []
    @State private var openFix: MistakeRecord?
    @State private var openWeekly: CallScenario?

    private var store: AdaptiveStore { AdaptiveStore.shared }
    private var jobs: AdaptiveJobs { AdaptiveJobs.shared }

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let record = practiceDays.first { $0.day == today }
        let day = dayPlan()
        let plan = makePlan(record: record, day: day)
        let next = plan.first { !$0.done && $0.enabled }

        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HeroCard(greeting: greeting, minutes: record?.minutes ?? 0, goal: dailyGoal,
                             streak: LearningStore.streak(practiceDays: practiceDays.map(\.day)),
                             stepsLeft: plan.filter { !$0.done && $0.enabled }.count,
                             focus: day?.snapshot.focus ?? .meetings,
                             next: next)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Today's plan", trailing: "\(plan.filter(\.done).count) of \(plan.count) done")
                        ForEach(plan) { step in
                            PlanStepCard(step: step)
                        }
                        if let working = jobs.working {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.mini)
                                Text("AI tutor: \(working)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        }
                    }

                    if let phrase = day?.phrase {
                        PhraseOfTheDayCard(phrase: phrase.phrase, unitTitle: phrase.unitTitle, reason: phrase.reason,
                                           aiWritten: phrase.aiWritten)
                    }

                    if let weekly = day?.weekly {
                        WeeklyCallCard(scenario: weekly.scenario, difficulty: weekly.difficulty, reason: weekly.reason,
                                       aiWritten: weekly.aiWritten, days: practiceDays) { openWeekly = weekly.scenario }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            #if DEBUG
            .task {
                if UserDefaults.standard.bool(forKey: "scrollToBottom") {
                    try? await Task.sleep(for: .seconds(1))
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            #endif
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SettingsToolbarButton() }
            .navigationDestination(item: $openFix) { MistakeDetailView(mistake: $0) }
            .navigationDestination(item: $openWeekly) { ScenarioStartView(scenario: $0) }
            .task(id: course.id) {
                // Reloads when the learner switches language (a different course).
                lessons = Self.loadLessons(for: course)
                scenarios = ScenarioLoader.loadAll()
                store.pruneEvents()
            }
            .task(id: day?.jobInputs) {
                guard let day else { return }
                // Pin this week's challenge so it doesn't change mid-week.
                if let base = day.weekly?.base, store.content.weeklyPick?.week != day.jobInputs.week {
                    store.update { $0.weeklyPick = .init(week: day.jobInputs.week, scenarioId: base.id) }
                }
                jobs.schedule(day.jobInputs)
            }
        }
    }

    // MARK: - Choosing today's content

    /// Everything Today shows, chosen from the learner model.
    struct DayPlan {
        struct PhraseChoice { let phrase: Phrase; let unitTitle: String; let reason: String; let aiWritten: Bool }
        struct WeeklyChoice {
            let scenario: CallScenario
            let base: CallScenario
            let difficulty: CallDifficulty
            let reason: String
            let aiWritten: Bool
        }

        let snapshot: LearnerSnapshot
        let lesson: Lesson?
        let lessonReason: String?
        let lessonUnit: CourseUnit?
        let call: (scenario: CallScenario, reason: String, extra: String?)?
        let phrase: PhraseChoice?
        let weekly: WeeklyChoice?
        let jobInputs: AdaptiveJobInputs
    }

    private func dayPlan(now: Date = .now) -> DayPlan? {
        guard !lessons.isEmpty else { return nil }
        let content = store.content
        let focus = store.focus(target: target, choice: focusChoice)
        let level = LearnerModel.level(speakingCheckWPM: checkWPM, speakingCheckMistakes: checkMistakes)
        let snapshot = LearnerModel.snapshot(course: course, lessons: lessons, progress: progress, cards: cards, calls: calls,
                                             mistakes: mistakes, focus: focus, level: level, upcoming: store.nextEvent(now: now),
                                             scenarios: scenarios, now: now)
        let order = AdaptivePlanner.unitOrder(course, focus: focus)
        let units = Dictionary(course.tracks.flatMap(\.units).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let lessonByUnit = Dictionary(lessons.map { ($0.unitId, $0) }, uniquingKeysWith: { a, _ in a })

        // Today's lesson: the one you already did today, otherwise the planner's pick.
        var lesson: Lesson?
        var reason: String?
        var kind: LessonPick.Kind?
        if let doneToday = progress.filter({ Calendar.current.isDate($0.lastCompletedAt, inSameDayAs: now) })
            .max(by: { $0.lastCompletedAt < $1.lastCompletedAt }), let done = lessons.first(where: { $0.id == doneToday.lessonId }) {
            lesson = done
        } else if let pick = AdaptivePlanner.pickLesson(snapshot: snapshot, order: order, available: Set(lessonByUnit.keys), now: now) {
            lesson = lessonByUnit[pick.unitId]
            reason = pick.reason
            kind = pick.kind
        }
        let lessonUnit = lesson.flatMap { units[$0.unitId] }
        let call = AdaptivePlanner.pickCall(lessonUnit: lessonUnit, lessonKind: kind, upcoming: snapshot.upcoming,
                                            scenarios: scenarios, now: now)

        // Phrase of the day: the AI's, written for your job today, or one from your weakest unit.
        let day = AdaptivePlanner.dayKey(now)
        let phraseUnitId = AdaptivePlanner.phraseUnit(snapshot: snapshot, order: order, lessonUnitId: lessonUnit?.id)
        var phrase: DayPlan.PhraseChoice?
        if let ai = content.phrase, ai.day == day {
            phrase = .init(phrase: Phrase(id: "ai-\(day)", text: ai.english, native: ai.native, note: ai.when),
                           unitTitle: units[ai.unitId]?.title ?? "", reason: ai.when, aiWritten: true)
        } else if let unitId = phraseUnitId, let unitLesson = lessonByUnit[unitId], !unitLesson.phrases.isEmpty {
            let ordinal = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
            let started = snapshot.mastery(of: unitId).started
            phrase = .init(phrase: unitLesson.phrases[ordinal % unitLesson.phrases.count], unitTitle: unitLesson.title,
                           reason: started ? "From a skill you're still building." : "From today's lesson.", aiWritten: false)
        }

        // This week's challenge: pinned for the week, harder as you improve, rewritten by the AI for your job.
        let week = AdaptivePlanner.weekKey(now)
        let weekNumber = Calendar.current.component(.weekOfYear, from: now)
        var weekly: DayPlan.WeeklyChoice?
        let pinned = content.weeklyPick.flatMap { pick in pick.week == week ? scenarios.first { $0.id == pick.scenarioId } : nil }
        let kindForWeek = pinned?.kind ?? AdaptivePlanner.weeklyKind(snapshot: snapshot, week: weekNumber)
        if let base = pinned ?? AdaptivePlanner.weeklyScenario(kind: kindForWeek, scenarios: scenarios, snapshot: snapshot, week: weekNumber) {
            let difficulty = AdaptivePlanner.difficulty(for: base.kind, snapshot: snapshot)
            let doneBefore = snapshot.scenarioCounts[base.id] ?? 0
            var reason = base.kind == .interview ? "Interviews are your focus." : "Client meetings are your focus."
            if snapshot.focus == .both { reason = "You've practised this kind of call less." }
            reason += " Level: \(difficulty.title.lowercased())" + (doneBefore > 0 ? ", harder than last time." : ".")
            if let ai = content.weekly, ai.week == week, ai.baseScenarioId == base.id {
                weekly = .init(scenario: base.adapted(difficulty: difficulty, title: ai.title, subtitle: ai.subtitle,
                                                      situation: ai.situation, goals: ai.goals.isEmpty ? nil : ai.goals),
                               base: base, difficulty: difficulty, reason: reason, aiWritten: true)
            } else {
                weekly = .init(scenario: base.adapted(difficulty: difficulty), base: base, difficulty: difficulty,
                               reason: reason, aiWritten: false)
            }
        }

        let weakSpots = mistakes.filter { now.timeIntervalSince($0.lastSeen) < 14 * 86_400 }
            .sorted { $0.count > $1.count }.prefix(3)
            .map { MistakeRules.rule($0.pattern) != nil ? "\($0.title) (say \"\($0.right)\")" : "\"\($0.wrong)\" → \"\($0.right)\"" }
        let phraseUnit = phraseUnitId.flatMap { units[$0] }
        let inputs = AdaptiveJobInputs(profile: LearnerProfile.current, day: day, week: week,
                                       phraseUnit: phraseUnit.map { .init(id: $0.id, title: $0.title, goal: $0.goal, examples: $0.examplePhrases) },
                                       weeklyBase: weekly?.base, weakSpots: Array(weakSpots))

        return DayPlan(snapshot: snapshot, lesson: lesson, lessonReason: reason, lessonUnit: lessonUnit, call: call,
                       phrase: phrase, weekly: weekly, jobInputs: inputs)
    }

    private func makePlan(record: PracticeDay?, day: DayPlan?) -> [PlanStep] {
        let due = cards.filter { $0.due <= .now }.count
        var steps: [PlanStep] = [
            PlanStep(id: "drill", icon: "person.wave.2.fill", tint: .indigo, title: "Stand-up drill", minutes: 2,
                     detail: "Say your real yesterday / today / blockers update.",
                     done: (record?.drills ?? 0) > 0, enabled: true) { router.showStandUpDrill = true },
            PlanStep(id: "review", icon: "arrow.trianglehead.2.clockwise", tint: .teal, title: "Warm-up review", minutes: 3,
                     detail: cards.isEmpty ? "Unlocks after your first lesson."
                        : (due == 0 ? "All caught up." : "\(due) \(due == 1 ? "phrase" : "phrases") to say out loud."),
                     done: (record?.reviews ?? 0) > 0 || (!cards.isEmpty && due == 0), enabled: due > 0) { router.showReviewSession = true },
        ]
        if let lesson = day?.lesson {
            steps.append(PlanStep(id: "lesson", icon: "book.fill", tint: .blue, title: "Today's lesson", minutes: 6,
                                  detail: lesson.title, done: (record?.lessons ?? 0) > 0, enabled: true,
                                  reason: day?.lessonReason) { router.open(lesson) })
        }
        if let call = day?.call {
            let scenario = call.scenario
            steps.append(PlanStep(id: "call", icon: "phone.fill", tint: .green, title: "Call with \(scenario.aiName)", minutes: 6,
                                  detail: "\(scenario.title) · \(scenario.aiRole)", done: (record?.calls ?? 0) > 0, enabled: true,
                                  reason: call.reason, avatar: scenario.aiName) { router.startCall(scenario, extraContext: call.extra) })
        }
        if let fix = todaysFix {
            steps.append(PlanStep(id: "fix", icon: "checkmark.seal.fill", tint: .orange, title: "Today's fix", minutes: 3,
                                  detail: "\(fix.wrong) → \(fix.right)", done: fix.practisedToday(), enabled: true,
                                  reason: fix.count > 1 ? "You've said this \(fix.count) times." : nil) { openFix = fix })
        }
        return steps
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let first = name.split(separator: " ").first.map(String.init)
        return first.map { "\(part), \($0)" } ?? part
    }

    /// See LearningStore.todaysFix: done today, or your most repeated mistake not yet practised.
    private var todaysFix: MistakeRecord? { LearningStore.todaysFix(from: mistakes) }

    static func loadLessons(for course: Course) -> [Lesson] {
        course.tracksByPriority.flatMap(\.units).compactMap { try? ContentLoader.loadLesson(unitId: $0.id) }
    }
}

// MARK: - Pieces

struct PlanStep: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let title: String
    let minutes: Int
    let detail: String
    let done: Bool
    let enabled: Bool
    /// Why the planner chose this step for you.
    var reason: String? = nil
    var avatar: String? = nil
    let action: () -> Void
}

/// Greeting, goal ring, streak and the one big "Continue" button.
private struct HeroCard: View {
    let greeting: String
    let minutes: Int
    let goal: Int
    let streak: Int
    let stepsLeft: Int
    let focus: LearningFocus
    let next: PlanStep?

    @State private var animatedProgress: Double = 0

    var body: some View {
        let target = min(1, Double(minutes) / Double(max(goal, 1)))
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(greeting)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? .orange : .white.opacity(0.6))
                    Text("\(streak)").font(.headline.monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.18), in: Capsule())
                .accessibilityLabel("\(streak)-day streak")
            }

            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(.white.opacity(0.22), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: animatedProgress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(minutes)").font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        Text("of \(goal) min").font(.caption2.weight(.medium)).opacity(0.8)
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 104, height: 104)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(minutes) of \(goal) minutes today")

                VStack(alignment: .leading, spacing: 6) {
                    Text(minutes >= goal ? "Goal done today! 🎉" : (minutes == 0 ? "Let's get talking" : "Keep going"))
                        .font(.headline)
                    Text(stepsLeft == 0 ? "Everything on today's plan is done." : "\(stepsLeft) \(stepsLeft == 1 ? "step" : "steps") left in today's plan.")
                        .font(.subheadline)
                        .opacity(0.85)
                    Text("Focus: \(focus.shortTitle)")
                        .font(.caption)
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
            }

            if let next {
                Button(action: next.action) {
                    HStack {
                        Image(systemName: next.icon)
                        Text("Next: \(next.title)").lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(LogoMark.gradientBottom)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: next.id)
            }
        }
        .padding(20)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [LogoMark.gradientTop, LogoMark.gradientBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                // A big, faint logo mark for character.
                LogoMark(barLevels: LogoMark.speakingLevels)
                    .frame(width: 190, height: 190)
                    .opacity(0.10)
                    .rotationEffect(.degrees(-12))
                    .offset(x: 60, y: -30)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: LogoMark.gradientBottom.opacity(0.35), radius: 18, y: 10)
        .padding(.top, 4)
        .onAppear { withAnimation(.spring(duration: 1.0, bounce: 0.2).delay(0.15)) { animatedProgress = target } }
        .onChange(of: target) { _, value in withAnimation(.spring(duration: 0.8)) { animatedProgress = value } }
    }
}

private struct SectionTitle: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 4)
    }
}

/// One step of today's plan, as a tappable card with a done tick.
private struct PlanStep_Card_Icon: View {
    let step: PlanStep

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(step.done ? Color.green.opacity(0.15) : step.tint.opacity(0.15))
            if step.done {
                Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(.green)
            } else if let avatar = step.avatar {
                Text(String(avatar.prefix(1))).font(.title3.bold()).foregroundStyle(step.tint)
            } else {
                Image(systemName: step.icon).font(.title3).foregroundStyle(step.tint)
            }
        }
        .frame(width: 48, height: 48)
    }
}

private struct PlanStepCard: View {
    let step: PlanStep

    var body: some View {
        Button(action: step.action) {
            HStack(spacing: 14) {
                PlanStep_Card_Icon(step: step)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(step.title).font(.headline).lineLimit(1)
                        Text("\(step.minutes) min")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    Text(step.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let reason = step.reason, !step.done {
                        Label(reason, systemImage: "lightbulb.min")
                            .font(.caption)
                            .foregroundStyle(step.tint)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: step.done ? "checkmark.circle.fill" : "chevron.right")
                    .font(step.done ? .title3 : .footnote.weight(.semibold))
                    .foregroundStyle(step.done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(step.enabled || step.done ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!step.enabled)
        .accessibilityLabel("\(step.title), \(step.minutes) minutes, \(step.done ? "done" : step.detail + ". " + (step.reason ?? ""))")
    }
}

/// A useful phrase each day, with its meaning in your language and audio.
private struct PhraseOfTheDayCard: View {
    let phrase: Phrase
    let unitTitle: String
    let reason: String
    let aiWritten: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(aiWritten ? "Phrase of the day · for your job" : "Phrase of the day", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                Spacer()
                Text(unitTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("“\(phrase.text)”")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(phrase.native)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                SpeakButton(text: phrase.text)
                SpeakButton(text: phrase.text, slow: true)
                Spacer()
            }
            Label(aiWritten ? "When: \(reason)" : reason, systemImage: aiWritten ? "clock" : "lightbulb.min")
                .font(.caption)
                .foregroundStyle(.secondary)
            if aiWritten {
                Text("Written by your on-device AI tutor. The \(NativeLanguage.current.name) may need a check.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color.orange.opacity(0.16), Color.orange.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.orange.opacity(0.25)))
    }
}

/// This week's big call (meeting or interview), and the week at a glance.
private struct WeeklyCallCard: View {
    let scenario: CallScenario
    let difficulty: CallDifficulty
    let reason: String
    let aiWritten: Bool
    let days: [PracticeDay]
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(scenario.kind == .interview ? "THIS WEEK: MOCK INTERVIEW" : "THIS WEEK: CLIENT MEETING")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                DifficultyChip(difficulty: difficulty)
            }
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [LogoMark.gradientTop, LogoMark.gradientBottom],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(String(scenario.aiName.prefix(1))).font(.title2.bold()).foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(scenario.title).font(.headline)
                    Text("\(scenario.aiName) · \(scenario.aiRole)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if aiWritten {
                Text(scenario.subtitle).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            Label(aiWritten ? "Written for your job. " + reason : reason, systemImage: aiWritten ? "sparkles" : "lightbulb.min")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: open) {
                Label("Prepare and start", systemImage: "phone.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Divider()
            WeekDots(days: days)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Gentle / Standard / Challenging.
private struct DifficultyChip: View {
    let difficulty: CallDifficulty

    var body: some View {
        let level = CallDifficulty.allCases.firstIndex(of: difficulty) ?? 0
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i <= level ? tint : Color(.tertiarySystemFill)).frame(width: 4, height: 6 + CGFloat(i) * 3)
                }
            }
            Text(difficulty.title).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
        .foregroundStyle(tint)
        .accessibilityLabel("Difficulty: \(difficulty.title)")
    }

    private var tint: Color {
        switch difficulty {
        case .gentle: .green
        case .standard: .blue
        case .challenging: .orange
        }
    }
}

/// Seven dots for the last seven days: filled when you practised.
private struct WeekDots: View {
    let days: [PracticeDay]

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let week = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let practised = Set(days.filter { $0.seconds > 0 }.map(\.day))
        HStack {
            Text("Your week").font(.subheadline.weight(.medium))
            Spacer()
            HStack(spacing: 10) {
                ForEach(week, id: \.self) { day in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(practised.contains(day) ? Color.accentColor : Color(.tertiarySystemFill))
                            .frame(width: 14, height: 14)
                            .overlay {
                                if calendar.isDateInToday(day) { Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3) }
                            }
                        Text(day, format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Practised \(week.filter { practised.contains($0) }.count) of the last 7 days")
    }
}

#Preview {
    TodayView(course: .preview)
        .environment(AppRouter())
        .modelContainer(for: AppSchema.models, inMemory: true)
}
