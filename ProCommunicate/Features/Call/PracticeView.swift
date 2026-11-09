import SwiftData
import SwiftUI

/// Call practice and the speaking helpers (FEATURES.md §3 C).
struct PracticeView: View {
    @State private var scenarios: [CallScenario] = []
    @Query(sort: \CallRecord.startedAt, order: .reverse) private var calls: [CallRecord]

    var body: some View {
        NavigationStack {
            List {
                AIStatusSection()
                Section {
                    ForEach(scenarios.filter { $0.kind == .meeting }) { scenario in
                        NavigationLink(value: scenario) { ScenarioRow(scenario: scenario, done: calls.contains { $0.scenarioId == scenario.id }) }
                    }
                } header: {
                    Text("Client meeting simulations")
                } footer: {
                    Text("10–15 minute voice calls. Ends with a report of your top fixes.")
                }
                Section("Mock interviews") {
                    ForEach(scenarios.filter { $0.kind == .interview }) { scenario in
                        NavigationLink(value: scenario) { ScenarioRow(scenario: scenario, done: calls.contains { $0.scenarioId == scenario.id }) }
                    }
                }
                Section("Quick role-plays (3–5 minutes)") {
                    ForEach(scenarios.filter { $0.kind == .quick }) { scenario in
                        NavigationLink(value: scenario) { ScenarioRow(scenario: scenario, done: calls.contains { $0.scenarioId == scenario.id }) }
                    }
                }
                Section("Prepare") {
                    NavigationLink {
                        MeetingPrepView()
                    } label: {
                        FeatureRow(systemImage: "calendar.badge.clock", title: "I have a meeting tomorrow",
                                   detail: "Describe it in English, \(NativeLanguage.current.name) or \(NativeLanguage.current.romanisedName). Get a cheat sheet and a rehearsal call.")
                    }
                    NavigationLink {
                        AskNativeView()
                    } label: {
                        FeatureRow(systemImage: "character.bubble.fill", title: "Ask in \(NativeLanguage.current.name)",
                                   detail: "Type in \(NativeLanguage.current.name) or \(NativeLanguage.current.romanisedName), get professional English to use.")
                    }
                }
                Section {
                    Label("Calls are voice-only, like a real phone or Teams call. Your answers are recorded so you can listen back. Everything stays on your iPhone.",
                          systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Practice")
            .navigationDestination(for: CallScenario.self) { ScenarioStartView(scenario: $0) }
            .toolbar { SettingsToolbarButton() }
            .task { if scenarios.isEmpty { scenarios = ScenarioLoader.loadAll() } }
        }
    }
}

private struct ScenarioRow: View {
    let scenario: CallScenario
    let done: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .font(.title3)
                .foregroundStyle(done ? Color.green : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(scenario.title).font(.headline)
                Text(scenario.subtitle).font(.subheadline).foregroundStyle(.secondary)
                Text("\(scenario.aiName) · \(scenario.aiRole)").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch scenario.kind {
        case .meeting: "person.3.fill"
        case .interview: "briefcase.fill"
        case .quick: "phone.bubble.fill"
        }
    }
}

/// What the call is about, who you'll talk to, and a Start button.
struct ScenarioStartView: View {
    let scenario: CallScenario
    @Environment(AppRouter.self) private var router
    @Environment(AIModelManager.self) private var aiModel
    @State private var extra = ""
    private var speech: SpeechModelManager { SpeechModelManager.shared }

    var body: some View {
        let profile = LearnerProfile.current
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(scenario.title).font(.title2.bold())
                    Text(scenario.subtitle).foregroundStyle(.secondary)
                    Label("\(scenario.aiName), \(scenario.aiRole) · \(scenario.speechVoice.title)", systemImage: "person.crop.circle")
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            Section("Practise") {
                ForEach(scenario.goals, id: \.self) { Label($0, systemImage: "target") }
            }
            if scenario.isFullCall {
                Section {
                    TextField(scenario.kind == .interview ? "Paste the job description (optional)" : "Anything specific about your project? (optional)",
                              text: $extra, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text("The AI uses this to make the call realistic. It stays on your iPhone.")
                }
            }
            Section {
                if !(LlamaEngine.isAvailable && aiModel.isReady) {
                    Label("The AI tutor isn't ready, so \(scenario.aiName) will only say a few scripted lines. Set it up in Settings → AI tutor.",
                          systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if !speech.isReady {
                    Label("You'll type your answers. Download the speech model in Settings to talk.", systemImage: "keyboard")
                        .foregroundStyle(.secondary)
                }
                if profile.isEmpty {
                    Label("Tip: fill in Settings → About you, so the call fits your real job.", systemImage: "person.text.rectangle")
                        .foregroundStyle(.secondary)
                }
                Button {
                    router.startCall(scenario, extraContext: extra.isEmpty ? nil : extra)
                } label: {
                    Label("Start call", systemImage: "phone.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } footer: {
                Text("Use earphones for the best experience. Speak naturally; \(scenario.aiName) replies when you pause, or tap I'm done.")
            }
        }
        .font(.body)
        .navigationTitle(scenario.kind == .quick ? "Role-play" : "Call")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    PracticeView()
        .environment(AppRouter())
        .environment(AIModelManager.shared)
        .modelContainer(for: AppSchema.models, inMemory: true)
}
