import SwiftUI

/// Small label showing which build phase a feature arrives in.
struct PhaseBadge: View {
    let phase: String

    var body: some View {
        Text("Phase \(phase)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.tint.opacity(0.12), in: Capsule())
            .foregroundStyle(.tint)
            .accessibilityLabel("Coming in phase \(phase)")
    }
}

/// A row with an icon, a title, a short description and an optional phase badge.
struct FeatureRow: View {
    let systemImage: String
    let title: String
    let detail: String
    var phase: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer(minLength: 8)
                    if let phase { PhaseBadge(phase: phase) }
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Explains why voice input isn't available yet (or that it's still getting ready).
struct SpeechReadinessNote: View {
    let readiness: SpeechReadiness
    var retry: () -> Void = {}

    var body: some View {
        switch readiness {
        case .ready:
            EmptyView()
        case .preparing:
            HStack(spacing: 12) {
                ProgressView()
                Text("Getting speech recognition ready… The first time after installing or updating the app takes about 2–3 minutes while iOS prepares it for your iPhone. After that it's ready in seconds.")
                    .foregroundStyle(.secondary)
            }
        case .needsDownload:
            Label("Download the speech model in Settings → AI tutor to answer by voice.", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .micDenied:
            Label("Microphone access is off. Turn it on in iPhone Settings → Privacy & Security → Microphone → ProCommunicate.",
                  systemImage: "mic.slash")
                .foregroundStyle(.orange)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Speech recognition couldn't start: \(message)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Try again", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.bordered)
            }
        }
    }
}
