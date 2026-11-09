import SwiftData
import SwiftUI

/// Daily stand-up drill: say your real yesterday / today / blockers update, recorded and timed.
struct StandUpDrillView: View {
    static let targetSeconds: TimeInterval = 120

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Recording> { $0.kind == "standup" }, sort: \Recording.createdAt, order: .reverse)
    private var drills: [Recording]

    @State private var recorder = AudioRecorder()
    @State private var micDenied = false
    @State private var errorText: String?
    @State private var startedAt = Date()
    @State private var justSaved: Recording?

    private let prompts: [(title: String, starter: String, tamil: String)] = [
        ("Yesterday", "Yesterday I completed… / I worked on…", "நேற்று என்ன செய்தீர்கள்"),
        ("Today", "Today I'll be working on…", "இன்று என்ன செய்யப் போகிறீர்கள்"),
        ("Blockers", "I'm blocked on… and need help from… / No blockers.", "ஏதேனும் தடை இருக்கிறதா"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Say your real update, out loud, the way you would in your team's stand-up. Aim for under 2 minutes.")
                        Text("உங்கள் உண்மையான stand-up update-ஐ சத்தமாகச் சொல்லுங்கள்.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section("Cover these three") {
                    ForEach(prompts, id: \.title) { prompt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(prompt.title).font(.headline)
                            Text(prompt.starter).font(.subheadline)
                            Text(prompt.tamil).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section {
                    if micDenied {
                        Text("Microphone access is off. Turn it on in iPhone Settings → Privacy & Security → Microphone → ProCommunicate.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Your recording stays on this iPhone. When the AI tutor arrives (Phase 3), it will transcribe your update and give you one fix each day.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                if !drills.isEmpty {
                    Section("Your recent drills") {
                        ForEach(drills.prefix(5)) { drill in
                            RecordingRow(recording: drill)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                recordControl
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .background(.bar)
            }
            .navigationTitle("Stand-up drill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if recorder.isRecording { stopAndSave() }
                        dismiss()
                    }
                }
            }
            .onDisappear {
                if recorder.isRecording { stopAndSave() }
                AudioPlayback.shared.stop()
            }
        }
    }

    @ViewBuilder
    private var recordControl: some View {
        VStack(spacing: 10) {
            Text(timeText(recorder.elapsed))
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(recorder.elapsed > Self.targetSeconds ? .orange : .primary)
            ProgressView(value: min(recorder.elapsed, Self.targetSeconds), total: Self.targetSeconds)
            LevelBars(level: recorder.level, active: recorder.isRecording)
                .frame(height: 22)
            Button {
                recorder.isRecording ? stopAndSave() : startRecording()
            } label: {
                Label(recorder.isRecording ? "Stop" : "Record my update",
                      systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? .red : .accentColor)
            .controlSize(.large)
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.orange)
            }
            if let saved = justSaved, !recorder.isRecording {
                Label("Saved \(timeText(saved.duration)). Play it back and listen to yourself.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 8)
    }

    private func startRecording() {
        Task {
            guard await AudioRecorder.requestPermission() else {
                micDenied = true
                return
            }
            micDenied = false
            do {
                AudioPlayback.shared.stop()
                Speaker.shared.stop()
                let fileName = "standup-\(Int(Date().timeIntervalSince1970)).m4a"
                try recorder.start(to: RecordingStorage.directory.appending(path: fileName))
                pendingFileName = fileName
                startedAt = .now
                errorText = nil
            } catch {
                errorText = "Couldn't start recording: \(error.localizedDescription)"
            }
        }
    }

    @State private var pendingFileName: String?

    private func stopAndSave() {
        let duration = recorder.stop()
        guard let fileName = pendingFileName, duration >= 1 else { return }
        pendingFileName = nil
        let title = "Stand-up · \(Date().formatted(date: .abbreviated, time: .shortened))"
        let recording = Recording(kind: "standup", title: title, fileName: fileName, duration: duration)
        context.insert(recording)
        try? context.save()
        LearningStore.log(.drill, seconds: Date().timeIntervalSince(startedAt), in: context)
        justSaved = recording
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A recording with play/stop, length and date.
struct RecordingRow: View {
    let recording: Recording
    private var playback: AudioPlayback { AudioPlayback.shared }

    var body: some View {
        let playing = playback.playingURL == recording.fileURL
        HStack(spacing: 12) {
            Button {
                playback.toggle(recording.fileURL)
            } label: {
                Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel(playing ? "Stop" : "Play")
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title).font(.subheadline)
                Text(Duration.seconds(recording.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if recording.starred {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
        }
    }
}

/// A simple live level meter.
struct LevelBars: View {
    let level: Double
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<24, id: \.self) { index in
                let threshold = Double(index) / 24
                Capsule()
                    .fill(active && level > threshold ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}
