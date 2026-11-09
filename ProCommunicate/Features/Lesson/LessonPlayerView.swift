import SwiftUI

/// Plays one lesson full screen: intro → steps (missed ones come back) → results.
struct LessonPlayerView: View {
    let lesson: Lesson
    /// Called once when the lesson is finished, with the first-try score (0…1) and seconds spent.
    var onFinish: (Double, TimeInterval) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var session: LessonSession
    @State private var started: Bool
    @State private var answer: String?
    @State private var confirmExit = false
    @State private var reported = false
    @State private var startedAt = Date()

    init(lesson: Lesson, startAt: Int? = nil, onFinish: @escaping (Double, TimeInterval) -> Void = { _, _ in }) {
        self.lesson = lesson
        self.onFinish = onFinish
        _session = State(initialValue: LessonSession(lesson: lesson, startAt: startAt ?? 0))
        _started = State(initialValue: startAt != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            bottomBar
        }
        .background(Color(.systemGroupedBackground))
        .confirmationDialog("Leave this lesson?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Leave lesson", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your progress in this lesson won't be saved.")
        }
        .sensoryFeedback(trigger: session.lastResult) { _, new in
            guard let new else { return nil }
            return new.correct ? .success : .error
        }
        .onChange(of: session.isFinished) { _, finished in
            if finished && started && !reported {
                reported = true
                onFinish(session.score, Date().timeIntervalSince(startedAt))
            }
        }
        .onDisappear { Speaker.shared.stop() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                if started && !session.isFinished { confirmExit = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Close lesson")
            .tint(.primary)

            if started {
                ProgressView(value: session.progress)
                    .tint(.accentColor)
                    .animation(.easeInOut, value: session.progress)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !started {
            LessonIntroView(lesson: lesson)
        } else if let step = session.current {
            stepView(step)
                .id("\(session.position)-\(step.id)")
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
        } else {
            LessonCompleteView(lesson: lesson, session: session)
        }
    }

    @ViewBuilder
    private func stepView(_ step: LessonStep) -> some View {
        let locked = session.lastResult != nil
        switch step.type {
        case .learn:
            if let phrase = lesson.phrase(step.phraseId) {
                LearnStepView(phrase: phrase)
            }
        case .choice:
            VStack(alignment: .leading, spacing: 20) {
                StepTitle(kicker: "Choose the best reply", text: step.prompt ?? "", tamil: step.promptTamil)
                OptionsList(options: step.options ?? [], selection: $answer, result: session.lastResult, locked: locked)
            }
        case .listen:
            VStack(alignment: .leading, spacing: 20) {
                ListenHeader(text: step.audioText ?? "")
                OptionsList(options: step.options ?? [], selection: $answer, result: session.lastResult, locked: locked)
            }
        case .fix:
            VStack(alignment: .leading, spacing: 20) {
                FixHeader(wrong: step.wrong ?? "", prompt: step.prompt ?? "Which is correct?")
                OptionsList(options: (step.options ?? []).filter { $0 != step.wrong }, selection: $answer,
                            result: session.lastResult, locked: locked)
            }
        case .build:
            BuildStepView(step: step, answer: $answer, result: session.lastResult)
        case .speak:
            SpeakStepView(step: step, lesson: lesson)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let result = session.lastResult, let step = session.current {
                FeedbackPanel(result: result, step: step)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Button {
                primaryAction()
            } label: {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!primaryEnabled)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
        .animation(.spring(duration: 0.35), value: session.lastResult)
    }

    private var primaryTitle: String {
        guard started else { return "Start lesson" }
        guard let step = session.current else { return "Done" }
        if session.lastResult != nil { return "Continue" }
        switch step.type {
        case .learn: return "Continue"
        case .speak: return "I said it"
        default: return "Check"
        }
    }

    private var primaryEnabled: Bool {
        guard started, let step = session.current else { return true }
        if !step.isGraded || session.lastResult != nil { return true }
        return !(answer ?? "").isEmpty
    }

    private func primaryAction() {
        guard started else {
            startedAt = .now
            withAnimation { started = true }
            return
        }
        guard let step = session.current else {
            dismiss()
            return
        }
        if step.isGraded && session.lastResult == nil {
            if let answer { session.check(answer) }
            return
        }
        Speaker.shared.stop()
        withAnimation(.easeInOut(duration: 0.25)) {
            answer = nil
            session.advance()
        }
    }
}

#Preview {
    if let lesson = try? ContentLoader.loadLesson(unitId: "meetings-03-status") {
        LessonPlayerView(lesson: lesson)
    }
}
