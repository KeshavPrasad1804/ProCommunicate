import SwiftData
import SwiftUI

/// After a call: your numbers, top 3 fixes linked to your recording, and the transcript.
struct CallReportView: View {
    let record: CallRecord
    var onDone: () -> Void

    @Environment(AppRouter.self) private var router
    @State private var retryTurn: CallTurn?

    var body: some View {
        let turns = record.turns
        let fixes = ReportFix.top(from: turns)
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.title).font(.title2.bold())
                        Text("\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(Duration.seconds(record.seconds).formatted(.time(pattern: .minuteSecond)))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if record.reportPending {
                    Section {
                        let progress = ReportProcessor.shared.progress[record.id]
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(progress.map { "Checking your answers… \($0.done) of \($0.total)" } ?? "Waiting to check your answers…")
                                    .font(.subheadline.weight(.semibold))
                                Text("The report fills in as each answer is checked. We'll notify you when it's done. Keep the app open: checks pause when it's in the background.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    MetricRow(title: "Speaking speed", value: record.learnerSeconds > 5 ? "\(Int(record.wordsPerMinute)) words/min" : "–",
                              note: speedNote(record.wordsPerMinute))
                    MetricRow(title: "Words you spoke", value: "\(record.learnerWords)", note: nil)
                    MetricRow(title: "Fillers (umm, actually, basically…)", value: "\(record.fillers)",
                              note: record.fillers == 0 ? "Clean." : "Try a short pause instead of a filler.")
                    MetricRow(title: "Long pauses", value: "\(record.longPauses)",
                              note: record.longPauses > 3 ? "Use a linking phrase while you think: \"Let me think…\", \"The main point is…\"" : nil)
                } header: {
                    Text("Your numbers")
                }

                Section {
                    if fixes.isEmpty {
                        if record.reportPending {
                            Label("Nothing from the quick pattern check. The AI is still checking your answers.", systemImage: "hourglass")
                                .foregroundStyle(.secondary)
                        } else {
                            Label(turns.contains { $0.speaker == .learner && $0.check == nil }
                                  ? "Answer checks need the AI tutor. Pattern checks found nothing."
                                  : "No mistakes found. Well done!", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    ForEach(fixes) { fix in
                        FixCard(fix: fix)
                    }
                } header: {
                    Text("Your top fixes")
                } footer: {
                    if !fixes.isEmpty { Text("These go into My Mistakes and come back in Review.") }
                }

                Section("Transcript") {
                    ForEach(turns) { turn in
                        TranscriptRow(turn: turn, aiName: record.title) { retryTurn = turn }
                    }
                }
            }
            .navigationTitle("Call report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
            .sheet(item: $retryTurn) { turn in
                let index = turns.firstIndex(of: turn) ?? 0
                let question = turns[..<index].last { $0.speaker == .ai }?.text ?? ""
                AnswerRetryView(question: question, previous: turn)
            }
        }
    }

    private func speedNote(_ wpm: Double) -> String? {
        switch wpm {
        case 0: nil
        case ..<90: "A little slow. Aim for 110–150 words a minute on calls."
        case ..<160: "A clear, comfortable speed for calls."
        default: "Quite fast. Slow down a little so clients can follow."
        }
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title, value: value)
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// One correction: what you said, the better way, why, in Tamil, and audio.
struct FixCard: View {
    let fix: ReportFix
    @State private var tamil: String?
    @State private var loadingTamil = false
    @State private var tamilError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                Text(fix.wrong).strikethrough(color: .orange)
                if fix.count > 1 {
                    Spacer()
                    Text("×\(fix.count)").font(.caption.weight(.bold)).foregroundStyle(.orange)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(fix.right).fontWeight(.semibold)
            }
            Text(fix.why).font(.subheadline).foregroundStyle(.secondary)
            if let text = tamil ?? fix.whyTamil {
                Text(text).font(.subheadline)
            } else if let tamilError {
                Text(tamilError).font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                if let clip = fix.clipFile {
                    ClipButton(fileName: clip, title: "What I said")
                }
                SpeakButton(text: fix.right.contains("…") ? fix.sentence : fix.right)
                if tamil == nil && fix.whyTamil == nil {
                    Button {
                        Task { await explain() }
                    } label: {
                        if loadingTamil { ProgressView() } else { Label("தமிழில்", systemImage: "character.bubble") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(loadingTamil || !TutorService.isAvailable)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 6)
    }

    private func explain() async {
        loadingTamil = true
        defer { loadingTamil = false }
        do {
            tamil = try await TutorService.explainInTamil(wrong: fix.wrong, right: fix.right, why: fix.why)
        } catch {
            tamilError = error.localizedDescription
        }
    }
}

/// Plays one of your recorded answers.
struct ClipButton: View {
    let fileName: String
    var title = "Play"
    private var playback: AudioPlayback { AudioPlayback.shared }

    var body: some View {
        let url = RecordingStorage.directory.appending(path: fileName)
        let playing = playback.playingURL == url
        Button {
            playback.toggle(url)
        } label: {
            Label(title, systemImage: playing ? "stop.fill" : "play.fill")
        }
        .buttonStyle(.bordered)
        .disabled(!FileManager.default.fileExists(atPath: url.path))
    }
}

struct TranscriptRow: View {
    let turn: CallTurn
    let aiName: String
    var onRetry: () -> Void
    @State private var showBetter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.speaker == .ai ? "THEM" : "YOU")
                .font(.caption2.weight(.bold))
                .foregroundStyle(turn.speaker == .ai ? Color.secondary : Color.accentColor)
            Text(turn.text).font(.body)
            if turn.speaker == .learner {
                if let better = turn.check?.better, AnswerChecker.normalize(better) != AnswerChecker.normalize(turn.text) {
                    DisclosureGroup("Say it better", isExpanded: $showBetter) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(better).font(.callout)
                            SpeakButton(text: better)
                        }
                        .padding(.top, 4)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                HStack(spacing: 10) {
                    if let clip = turn.clipFile { ClipButton(fileName: clip) }
                    Button("Try this answer again", systemImage: "arrow.counterclockwise", action: onRetry)
                        .buttonStyle(.bordered)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}
