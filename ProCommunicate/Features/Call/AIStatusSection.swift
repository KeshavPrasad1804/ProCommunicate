import SwiftUI

/// Shows whether the AI tutor (Gemma) and the speech model (Whisper) are ready, and leads to Settings when not.
struct AIStatusSection: View {
    @AppStorage(SettingsKey.aiTutorEnabled) private var aiTutorEnabled = false
    @Environment(AIModelManager.self) private var aiModel
    @Environment(AppRouter.self) private var router
    private var speech: SpeechModelManager { SpeechModelManager.shared }

    private let deviceSupported = DeviceCapability.supportsAITutor()

    var body: some View {
        Section {
            if !deviceSupported {
                row(icon: "iphone.slash", tint: .secondary, title: "AI tutor not available",
                    detail: "This iPhone doesn't have enough memory for the AI tutor. Lessons, review and drills still work.")
            } else if !aiTutorEnabled {
                row(icon: "sparkles", tint: .accentColor, title: "AI tutor is off",
                    detail: "Turn it on to have real conversations, get corrections and use Ask in Tamil.",
                    action: "Set up")
            } else {
                switch aiModel.state {
                case .notDownloaded, .failed:
                    row(icon: "arrow.down.circle.fill", tint: .accentColor, title: "Download the AI models",
                        detail: "One-time downloads: AI tutor \(aiModel.model.sizeBytes.formattedBytes), speech \(SpeechModelManager.approximateBytes.formattedBytes). Then everything works offline.",
                        action: "Download")
                case .downloading, .paused:
                    progressRow(title: isPaused ? "AI model download paused" : "Downloading the AI model",
                                fraction: aiModel.state.fraction ?? 0)
                case .verifying:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking the AI model…")
                    }
                case .ready:
                    switch speech.state {
                    case .ready:
                        Label("AI tutor and speech ready · works offline", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .downloading(let fraction):
                        progressRow(title: "Downloading the speech model", fraction: fraction)
                    case .notDownloaded, .failed:
                        row(icon: "waveform.badge.mic", tint: .accentColor, title: "Download the speech model",
                            detail: "\(SpeechModelManager.approximateBytes.formattedBytes), so you can talk instead of typing.",
                            action: "Download") { speech.download() }
                    }
                }
            }
        }
    }

    private var isPaused: Bool {
        if case .paused = aiModel.state { return true }
        return false
    }

    private func progressRow(title: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "arrow.down.circle").font(.headline)
            ProgressView(value: fraction)
            Text("\(Int((fraction * 100).rounded()))% · you can keep using lessons meanwhile")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { router.showSettings = true }
    }

    private func row(icon: String, tint: Color, title: String, detail: String, action: String? = nil,
                     perform: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action) { if let perform { perform() } else { router.showSettings = true } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
