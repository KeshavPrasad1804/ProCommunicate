import SwiftUI

/// The daily 20-minute session from FEATURES.md §2.
struct TodayView: View {
    private struct Step: Identifiable {
        let id = UUID()
        let minutes: Int
        let systemImage: String
        let title: String
        let detail: String
        let phase: String
    }

    private let steps: [Step] = [
        Step(minutes: 2, systemImage: "person.wave.2.fill", title: "Stand-up drill",
             detail: "Say your real yesterday / today / blockers update out loud. One fix each day.", phase: "2"),
        Step(minutes: 3, systemImage: "arrow.trianglehead.2.clockwise", title: "Warm-up review",
             detail: "Say the phrases and fixes due today.", phase: "2"),
        Step(minutes: 6, systemImage: "book.fill", title: "Today's lesson",
             detail: "3–5 phrases for one meeting or interview situation.", phase: "1"),
        Step(minutes: 6, systemImage: "phone.fill", title: "Speak with the AI",
             detail: "A short client-call or interview role-play using today's phrases.", phase: "3"),
        Step(minutes: 3, systemImage: "checkmark.seal.fill", title: "Today's fix",
             detail: "Your #1 mistake, explained in Tamil, said correctly 3 times.", phase: "3"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your 20 minutes")
                            .font(.title2.bold())
                        Text("Focus: speaking in client meetings, then job interviews.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("Today's session") {
                    ForEach(steps) { step in
                        FeatureRow(systemImage: step.systemImage,
                                   title: "\(step.title) · \(step.minutes) min",
                                   detail: step.detail,
                                   phase: step.phase)
                    }
                }
                Section("This week") {
                    FeatureRow(systemImage: "person.3.fill", title: "Client meeting simulation",
                               detail: "A full status call with a UK client, as a voice call.", phase: "4")
                }
            }
            .navigationTitle("Today")
            .toolbar { SettingsToolbarButton() }
        }
    }
}

#Preview {
    TodayView()
        .environment(AppRouter())
}
