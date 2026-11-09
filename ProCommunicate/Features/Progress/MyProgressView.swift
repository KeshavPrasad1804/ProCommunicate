import SwiftUI

/// Progress, mistakes and recordings (FEATURES.md §3 E–G).
/// Named `MyProgressView` to avoid clashing with SwiftUI's `ProgressView`.
struct MyProgressView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("This week") {
                    LabeledContent("Speaking time", value: "0 min")
                    LabeledContent("Day streak", value: "0")
                }
                Section {
                    FeatureRow(systemImage: "exclamationmark.bubble.fill", title: "My Mistakes",
                               detail: "Every mistake from your calls, grouped by pattern, until you stop making it.", phase: "3")
                    FeatureRow(systemImage: "waveform", title: "Recordings",
                               detail: "Listen back to your calls and answers, with the transcript in sync.", phase: "3")
                    FeatureRow(systemImage: "gauge.with.dots.needle.67percent", title: "Fluency tracker",
                               detail: "Speaking speed, fillers like 'umm' and 'actually', and long pauses over time.", phase: "4")
                    FeatureRow(systemImage: "doc.text.fill", title: "Weekly report",
                               detail: "What improved, and what to focus on next week.", phase: "4")
                }
            }
            .navigationTitle("Progress")
            .toolbar { SettingsToolbarButton() }
        }
    }
}

#Preview {
    MyProgressView()
        .environment(AppRouter())
}
