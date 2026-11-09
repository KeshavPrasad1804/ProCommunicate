import SwiftUI

/// Shows whether the AI tutor is ready, and leads to Settings when it isn't.
struct AIStatusSection: View {
    @AppStorage(SettingsKey.aiTutorEnabled) private var aiTutorEnabled = false
    @Environment(AIModelManager.self) private var aiModel
    @Environment(AppRouter.self) private var router

    private let deviceSupported = DeviceCapability.supportsAITutor()

    var body: some View {
        Section {
            if !deviceSupported {
                row(icon: "iphone.slash", tint: .secondary, title: "AI tutor not available",
                    detail: "This iPhone doesn't have enough memory for the AI tutor. Lessons and review still work.")
            } else if !aiTutorEnabled {
                row(icon: "sparkles", tint: .accentColor, title: "AI tutor is off",
                    detail: "Turn it on to practise calls, get corrections and use Ask in Tamil.",
                    action: "Set up")
            } else {
                switch aiModel.state {
                case .notDownloaded, .failed:
                    row(icon: "arrow.down.circle.fill", tint: .accentColor, title: "Download the AI model",
                        detail: "A one-time \(aiModel.model.sizeBytes.formattedBytes) download. Then everything works offline.",
                        action: "Download")
                case .downloading, .paused:
                    VStack(alignment: .leading, spacing: 6) {
                        Label(isPaused ? "AI model download paused" : "Downloading the AI model",
                              systemImage: isPaused ? "pause.circle" : "arrow.down.circle")
                            .font(.headline)
                        ProgressView(value: aiModel.state.fraction ?? 0)
                        Text("\(Int(((aiModel.state.fraction ?? 0) * 100).rounded()))% · you can keep using lessons meanwhile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { router.showSettings = true }
                case .verifying:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking the AI model…")
                    }
                case .ready:
                    Label("AI tutor ready · works offline", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var isPaused: Bool {
        if case .paused = aiModel.state { return true }
        return false
    }

    private func row(icon: String, tint: Color, title: String, detail: String, action: String? = nil) -> some View {
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
                    Button(action) { router.showSettings = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
