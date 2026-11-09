import SwiftUI

/// Entry points for call mode and the speaking helpers (FEATURES.md §3 C).
struct PracticeView: View {
    var body: some View {
        NavigationStack {
            List {
                AIStatusSection()
                Section {
                    FeatureRow(systemImage: "person.3.fill", title: "Client meeting simulation",
                               detail: "A 15–20 minute voice call with a UK client and your project manager. Ends with a meeting report.",
                               phase: "4")
                    FeatureRow(systemImage: "briefcase.fill", title: "Mock interview",
                               detail: "15–25 questions for your role, as a phone or Teams-style call. Ends with an interview report.",
                               phase: "4")
                } header: {
                    Text("Full calls")
                }
                Section("Quick practice") {
                    FeatureRow(systemImage: "phone.bubble.fill", title: "Call-mode role-play",
                               detail: "One meeting moment or one interview question, by voice.", phase: "3")
                    FeatureRow(systemImage: "calendar.badge.clock", title: "I have a meeting tomorrow",
                               detail: "Describe it in English, Tamil or Tanglish. Get a cheat sheet and a 5-minute rehearsal.",
                               phase: "3")
                    FeatureRow(systemImage: "character.bubble.fill", title: "Ask in Tamil",
                               detail: "Type in Tamil or Tanglish, get professional English to use.", phase: "3")
                }
                Section {
                    Label("Calls are voice-only, like a real phone or Teams call, and are recorded so you can listen back. Everything stays on your iPhone.",
                          systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Practice")
            .toolbar { SettingsToolbarButton() }
        }
    }
}

#Preview {
    PracticeView()
        .environment(AppRouter())
        .environment(AIModelManager.shared)
}
