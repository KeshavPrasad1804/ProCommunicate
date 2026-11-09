import SwiftData
import SwiftUI

/// Answer the same question again and compare with your earlier attempt.
struct AnswerRetryView: View {
    let question: String
    let previous: CallTurn

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var listener = SingleAnswerListener()
    @State private var attempt: CallTurn?
    @State private var working = false
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            List {
                if !question.isEmpty {
                    Section("The question") {
                        HStack {
                            Text(question)
                            Spacer(minLength: 8)
                            SpeakButton(text: question)
                        }
                    }
                }
                Section("Before") {
                    AttemptSummary(turn: previous)
                    if let better = previous.check?.better {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("A better version").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(better).font(.callout)
                            SpeakButton(text: better)
                        }
                    }
                }
                Section("Now") {
                    if let attempt {
                        AttemptSummary(turn: attempt)
                        comparison(before: previous, now: attempt)
                    } else if listener.available {
                        recordControls
                    } else if listener.readiness != .needsDownload {
                        SpeechReadinessNote(readiness: listener.readiness) { Task { await listener.prepare() } }
                    } else {
                        TextField("Type your new answer", text: $typed, axis: .vertical).lineLimit(2...6)
                        Button("Check my answer") { Task { await evaluate(text: typed, clip: nil, seconds: Double(FluencyMetrics.wordCount(typed)) / 2.2, pauses: 0) } }
                            .disabled(typed.isEmpty || working)
                        Text("Download the speech model in Settings to answer by voice.").font(.caption).foregroundStyle(.secondary)
                    }
                    if working { HStack { ProgressView(); Text("Checking…") } }
                }
            }
            .navigationTitle("Try again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if attempt != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Again") { attempt = nil }
                    }
                }
            }
            .task { await listener.prepare() }
            .onDisappear { listener.stop() }
            .onChange(of: listener.result) { _, result in
                guard let result else { return }
                Task { await evaluate(text: result.text, clip: result.clipFile, seconds: result.seconds, pauses: result.longPauses) }
            }
        }
    }

    private var recordControls: some View {
        VStack(spacing: 12) {
            LevelBars(level: listener.level, active: listener.isRecording).frame(height: 22)
            Button {
                listener.isRecording ? listener.finish() : listener.start()
            } label: {
                Label(listener.isRecording ? "I'm done" : "Answer again", systemImage: listener.isRecording ? "checkmark" : "mic.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(listener.isRecording ? .green : .accentColor)
            .disabled(working)
            Text(listener.isRecording ? "Speak now. It stops when you pause, or tap I'm done." : "Say your answer out loud.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func comparison(before: CallTurn, now: CallTurn) -> some View {
        let beforeMistakes = before.ruleHits.count + (before.check?.mistakes.count ?? 0)
        let nowMistakes = now.ruleHits.count + (now.check?.mistakes.count ?? 0)
        let beforeWPM = FluencyMetrics.wordsPerMinute(words: before.words, seconds: before.seconds)
        let nowWPM = FluencyMetrics.wordsPerMinute(words: now.words, seconds: now.seconds)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Compared with before").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Label("Mistakes: \(beforeMistakes) → \(nowMistakes)", systemImage: nowMistakes < beforeMistakes ? "arrow.down.circle.fill" : "equal.circle")
                .foregroundStyle(nowMistakes < beforeMistakes ? .green : .primary)
            Label("Speed: \(Int(beforeWPM)) → \(Int(nowWPM)) words/min", systemImage: "speedometer")
            Label("Long pauses: \(before.longPauses) → \(now.longPauses)", systemImage: "pause.circle")
        }
        .font(.subheadline)
    }

    private func evaluate(text: String, clip: String?, seconds: Double, pauses: Int) async {
        working = true
        defer { working = false }
        var turn = CallTurn(speaker: .learner, text: text, clipFile: clip, seconds: seconds, longPauses: pauses)
        turn.ruleHits = MistakeRules.check(text).map { CallTurn.StoredHit(ruleId: $0.ruleId, wrong: $0.wrong) }
        if TutorService.isAvailable { turn.check = try? await TutorService.checkAnswer(text) }
        attempt = turn
        if let clip {
            modelContext.insert(Recording(kind: "retry", title: "Retry · \(question.prefix(40))", fileName: clip, duration: seconds))
        }
        MistakeBook.record(turns: [turn], in: modelContext)
    }
}

private struct AttemptSummary: View {
    let turn: CallTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.text)
            HStack {
                if let clip = turn.clipFile { ClipButton(fileName: clip) }
                Spacer()
                Text("\(turn.words) words").font(.caption).foregroundStyle(.secondary)
            }
            let mistakes = turn.ruleHits.compactMap { MistakeRules.rule($0.ruleId).map { "\($0.title) → \($0.right)" } }
                + (turn.check?.mistakes.map { "\($0.wrong) → \($0.right)" } ?? [])
            ForEach(mistakes, id: \.self) { line in
                Label(line, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

/// Records and transcribes one spoken answer (used by retries, drills and the placement check).
@MainActor @Observable
final class SingleAnswerListener {
    struct Result: Equatable {
        let text: String
        let clipFile: String?
        let seconds: Double
        let longPauses: Int
    }

    private(set) var readiness: SpeechReadiness = .preparing
    var available: Bool { readiness == .ready }
    private(set) var isRecording = false
    private(set) var level: Double = 0
    private(set) var result: Result?
    @ObservationIgnored private var capture: VoiceCapture?

    func prepare() async {
        readiness = await SpeechReadiness.prepare()
    }

    func start() {
        result = nil
        AudioPlayback.shared.stop()
        Speaker.shared.stop()
        let capture = VoiceCapture(detection: { var d = TurnDetection.current; d.endSilence = max(d.endSilence, 2.5); return d }()) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        do {
            try capture.start()
            capture.setListening(true)
            self.capture = capture
            isRecording = true
        } catch {
            isRecording = false
        }
    }

    func finish() { capture?.finishTurnNow() }

    func stop() {
        capture?.stop()
        capture = nil
        isRecording = false
    }

    private func handle(_ event: VoiceEvent) {
        switch event {
        case .level(let value): level = value
        case .speechStarted: break
        case .turnEnded(let samples, let seconds, let pauses):
            stop()
            Task {
                let text = (try? await SpeechRecognizer.shared.transcribe(samples))?.text ?? ""
                let name = "answer-\(Int(Date().timeIntervalSince1970)).m4a"
                let url = RecordingStorage.directory.appending(path: name)
                let saved = await Task.detached { (try? AudioFileWriter.writeM4A(samples, to: url)) != nil }.value
                result = Result(text: text, clipFile: saved ? name : nil, seconds: seconds, longPauses: pauses)
            }
        }
    }
}
