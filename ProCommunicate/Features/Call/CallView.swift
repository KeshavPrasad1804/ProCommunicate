import SwiftData
import SwiftUI

/// A practice call that looks and works like a phone / Teams call: you listen and answer out loud.
struct CallView: View {
    let launch: CallLaunch

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: CallSession
    @State private var captionsOn = true
    @State private var showKeyboard = false
    @State private var confirmEnd = false

    init(launch: CallLaunch) {
        self.launch = launch
        _session = State(initialValue: CallSession(scenario: launch.scenario, extraContext: launch.extraContext))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.22), Color(red: 0.03, green: 0.05, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                header
                Spacer(minLength: 8)
                avatar
                statusText
                if captionsOn { captions }
                Spacer(minLength: 8)
                if session.typingMode || showKeyboard { typingBar }
                controls
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .foregroundStyle(.white)

        }
        .preferredColorScheme(.dark)
        .task {
            UIApplication.shared.isIdleTimerDisabled = true   // don't let the screen lock mid-call
            ReportProcessor.shared.callInProgress = true       // background report checks wait for the call
            LlamaEngine.shared.cancelCurrent()
            await session.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: session.appDidEnterBackground()
            case .active: session.appDidBecomeActive()
            default: break
            }
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .ended { finishAndClose() }
        }
        .confirmationDialog("End the call?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End call", role: .destructive) { Task { await session.end() } }
            Button("Keep talking", role: .cancel) {}
        } message: {
            Text("Your report is prepared in the background. We'll notify you when it's ready.")
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            ReportProcessor.shared.callInProgress = false
            if session.isActive { Task { await session.end() } }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: session.phase == .listening)
    }

    /// Saves the call and closes the screen right away; answer checks continue in the background.
    private func finishAndClose() {
        let pending = session.save(in: modelContext)
        ReportProcessor.shared.callInProgress = false
        if let id = session.savedRecordId {
            if pending {
                ReportProcessor.shared.enqueue(id)
            } else {
                ReportProcessor.shared.banner = .init(text: "Call saved. Your report is ready.", reportId: id)
            }
        }
        if !pending {
            Task {
                await SpeechRecognizer.shared.unload()
                await LlamaEngine.shared.unload()   // free memory: the AI loads only while practising
            }
        }
        dismiss()
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(launch.scenario.title).font(.subheadline.weight(.semibold))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds((session.endedAt ?? context.date).timeIntervalSince(session.startedAt))
                        .formatted(.time(pattern: .minuteSecond)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            if !session.aiAvailable {
                Label("AI off", systemImage: "sparkles.slash")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.15), in: Capsule())
            }
        }
        .padding(.top, 8)
    }

    private var avatar: some View {
        let speaking = session.phase == .aiSpeaking
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 168, height: 168)
                    .scaleEffect(speaking ? 1.08 : 1)
                    .animation(speaking ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: speaking)
                Circle()
                    .fill(LinearGradient(colors: [LogoMark.gradientTop, LogoMark.gradientBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 128, height: 128)
                Text(initials(launch.scenario.aiName))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
            }
            Text(launch.scenario.aiName).font(.title2.bold())
            Text(launch.scenario.aiRole).font(.subheadline).foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusText: some View {
        switch session.phase {
        case .preparing(let message):
            Label(message, systemImage: "hourglass").font(.subheadline)
        case .aiSpeaking:
            Label("\(launch.scenario.aiName) is speaking… (start talking to interrupt)", systemImage: "waveform")
                .font(.subheadline)
        case .listening:
            Label(session.typingMode ? "Your turn: type your answer" : "Your turn: speak now", systemImage: "mic.fill")
                .font(.headline)
                .foregroundStyle(.green)
        case .learnerSpeaking:
            VStack(spacing: 8) {
                Label("Listening…", systemImage: "mic.fill").font(.headline).foregroundStyle(.green)
                LevelBars(level: session.level, active: true).frame(height: 18).tint(.green)
            }
        case .thinking:
            Label("\(launch.scenario.aiName) is thinking…", systemImage: "ellipsis").font(.subheadline)
        case .ended:
            Label("Call ended", systemImage: "phone.down.fill").font(.subheadline)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange)
        }
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let ai = session.lastAIText {
                Text("\(launch.scenario.aiName): \(ai)")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
            }
            if let me = session.lastLearnerText {
                Text("You: \(me)")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .lineLimit(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .animation(.default, value: session.turns.count)
    }

    private var typingBar: some View {
        HStack(spacing: 10) {
            TextField("Type your answer", text: $session.typedAnswer, axis: .vertical)
                .lineLimit(1...4)
                .padding(10)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .submitLabel(.send)
                .onSubmit { session.submitTypedAnswer() }
            Button {
                session.submitTypedAnswer()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.largeTitle)
            }
            .disabled(session.typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty || session.phase == .thinking)
            .accessibilityLabel("Send")
        }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            callButton(captionsOn ? "captions.bubble.fill" : "captions.bubble", label: "Captions", tint: .white.opacity(0.15)) {
                captionsOn.toggle()
            }
            if !session.typingMode {
                callButton("keyboard", label: "Type", tint: .white.opacity(showKeyboard ? 0.35 : 0.15)) {
                    showKeyboard.toggle()
                }
                callButton("checkmark", label: "I'm done", tint: session.phase == .learnerSpeaking ? .green : .white.opacity(0.15)) {
                    session.finishTurnNow()
                }
                .disabled(session.phase != .learnerSpeaking)
            }
            callButton("phone.down.fill", label: "End", tint: .red) {
                confirmEnd = true
            }
        }
        .padding(.top, 4)
    }

    private func callButton(_ icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(tint, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.8))
        }
    }

    private func initials(_ name: String) -> String {
        String(name.split(separator: " ").compactMap(\.first).prefix(2))
    }
}

/// Loads a saved call by id and shows its report.
struct CallReportContainer: View {
    let recordId: UUID
    var onDone: () -> Void
    @Query private var records: [CallRecord]

    init(recordId: UUID, onDone: @escaping () -> Void) {
        self.recordId = recordId
        self.onDone = onDone
        _records = Query(filter: #Predicate<CallRecord> { $0.id == recordId })
    }

    var body: some View {
        if let record = records.first {
            CallReportView(record: record, onDone: onDone)
        } else {
            ProgressView()
        }
    }
}
