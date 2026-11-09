import SwiftData
import SwiftUI

/// First launch: what the app does, about you, your goal, and the AI setup.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage(LearnerProfile.Key.name) private var name = ""
    @AppStorage(LearnerProfile.Key.role) private var role = ""
    @AppStorage(LearnerProfile.Key.target) private var target = ""
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = 20
    @AppStorage(SettingsKey.aiTutorEnabled) private var aiTutorEnabled = false
    @AppStorage(NativeLanguage.settingsKey) private var languageCode = NativeLanguage.tamil.rawValue
    @State private var page = 0

    private var language: NativeLanguage { NativeLanguage(rawValue: languageCode) ?? .tamil }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                welcome.tag(0)
                aboutYou.tag(1)
                aiSetup.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .safeAreaInset(edge: .bottom) {
                Button {
                    if page < 2 { withAnimation { page += 1 } } else { finish() }
                } label: {
                    Text(page < 2 ? "Continue" : "Start learning")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { finish() } }
            }
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        onboarded = true
        dismiss()
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LogoMark(barLevels: LogoMark.speakingLevels).frame(width: 84, height: 84)
                Text("Speak with confidence at work").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your language").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Your language", selection: $languageCode) {
                        ForEach(NativeLanguage.allCases) { Text($0.nativeName).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                Text("ProCommunicate helps \(language.name) speakers speak clear, professional English in client meetings and job interviews.")
                    .font(.title3)
                Text(language.text(.tagline))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Label("20 minutes a day: stand-up drill, review, a lesson and a call", systemImage: "sun.max.fill")
                    Label("Practice calls that feel like real phone or Teams calls", systemImage: "phone.fill")
                    Label("Your top fixes after every call, explained in \(language.name)", systemImage: "checkmark.seal.fill")
                    Label("Everything stays on your iPhone, even the AI", systemImage: "lock.shield.fill")
                }
                .font(.subheadline)
            }
            .padding(24)
        }
    }

    private var aboutYou: some View {
        Form {
            Section {
                TextField("Your name", text: $name).textContentType(.name)
                TextField("Your role (e.g. Java developer)", text: $role)
                TextField("What are you preparing for?", text: $target, axis: .vertical).lineLimit(2...3)
            } header: {
                Text("About you")
            } footer: {
                Text("Calls use this to talk about your real work. You can add more later in Settings → About you.")
            }
            Section("Daily goal") {
                Picker("Daily goal", selection: $dailyGoal) {
                    Text("10 min").tag(10)
                    Text("20 min").tag(20)
                    Text("30 min").tag(30)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var aiSetup: some View {
        Form {
            Section {
                Toggle(isOn: $aiTutorEnabled) { Label("Turn on the AI tutor", systemImage: "sparkles") }
                    .disabled(!DeviceCapability.supportsAITutor())
            } footer: {
                Text(DeviceCapability.supportsAITutor()
                     ? "The AI runs entirely on your iPhone. It needs two one-time downloads (about 3.3 GB, best on Wi-Fi). Lessons, review and drills work without it."
                     : "This iPhone doesn't have enough memory for the AI tutor. Lessons, review and drills still work.")
            }
            if aiTutorEnabled {
                AIModelSection(aiTutorEnabled: true)
                SpeechModelSection()
            }
        }
    }
}

/// The speaking check (placement): introduce yourself for up to a minute; get your numbers and a starting point.
struct SpeakingCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @State private var listener = SingleAnswerListener()
    @State private var result: CallTurn?
    @State private var working = false
    @AppStorage("speakingCheckWPM") private var savedWPM = 0.0
    @AppStorage("speakingCheckMistakes") private var savedMistakes = -1

    var body: some View {
        List {
            Section {
                Text("Introduce yourself as you would at the start of a client call or interview: your name, your role, your current project, and what you're good at. Speak for 30–60 seconds.")
                Text("ஒரு client call அல்லது interview தொடக்கத்தில் சொல்வது போல உங்களை அறிமுகப்படுத்துங்கள் (30–60 வினாடிகள்).")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                if !listener.available {
                    SpeechReadinessNote(readiness: listener.readiness) { Task { await listener.prepare() } }
                } else {
                    LevelBars(level: listener.level, active: listener.isRecording).frame(height: 22)
                    Button {
                        listener.isRecording ? listener.finish() : listener.start()
                    } label: {
                        Label(listener.isRecording ? "I'm done" : "Start speaking", systemImage: listener.isRecording ? "checkmark" : "mic.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(listener.isRecording ? .green : .accentColor)
                    .disabled(working)
                }
                if working { HStack { ProgressView(); Text("Listening to your answer…") } }
            }
            if let result {
                let wpm = FluencyMetrics.wordsPerMinute(words: result.words, seconds: result.seconds)
                let mistakes = result.ruleHits.count + (result.check?.mistakes.count ?? 0)
                Section("Your result") {
                    Text(result.text).font(.callout)
                    LabeledContent("Speaking speed", value: "\(Int(wpm)) words/min")
                    LabeledContent("Mistakes found", value: "\(mistakes)")
                    LabeledContent("Long pauses", value: "\(result.longPauses)")
                    Text(recommendation(wpm: wpm, mistakes: mistakes)).font(.subheadline.weight(.medium))
                    ForEach(ReportFix.top(from: [result])) { FixCard(fix: $0) }
                }
            } else if savedMistakes >= 0 {
                Section("Last time") {
                    LabeledContent("Speaking speed", value: "\(Int(savedWPM)) words/min")
                    LabeledContent("Mistakes found", value: "\(savedMistakes)")
                }
            }
        }
        .navigationTitle("Speaking check")
        .navigationBarTitleDisplayMode(.inline)
        .task { await listener.prepare() }
        .onDisappear { listener.stop() }
        .onChange(of: listener.result) { _, value in
            guard let value else { return }
            Task { await evaluate(value) }
        }
    }

    private func evaluate(_ answer: SingleAnswerListener.Result) async {
        working = true
        defer { working = false }
        var turn = CallTurn(speaker: .learner, text: answer.text, clipFile: answer.clipFile, seconds: answer.seconds, longPauses: answer.longPauses)
        turn.ruleHits = MistakeRules.check(answer.text).map { CallTurn.StoredHit(ruleId: $0.ruleId, wrong: $0.wrong) }
        if TutorService.isAvailable { turn.check = try? await TutorService.checkAnswer(answer.text) }
        result = turn
        savedWPM = FluencyMetrics.wordsPerMinute(words: turn.words, seconds: turn.seconds)
        savedMistakes = turn.ruleHits.count + (turn.check?.mistakes.count ?? 0)
        if let clip = answer.clipFile {
            modelContext.insert(Recording(kind: "check", title: "Speaking check · \(Date().formatted(date: .abbreviated, time: .omitted))",
                                          fileName: clip, duration: answer.seconds))
        }
        MistakeBook.record(turns: [turn], in: modelContext)
    }

    private func recommendation(wpm: Double, mistakes: Int) -> String {
        if mistakes >= 3 || wpm < 80 {
            return "Start with Meetings unit 1 (Daily stand-up) and do the lessons in order. Daily drills will build your speed."
        } else if mistakes >= 1 {
            return "Start with Meetings unit 3 (Status update) and do one quick role-play a day. Watch your top fix."
        } else {
            return "You're ready for full calls. Try a client meeting simulation this week, and use lessons for new phrases."
        }
    }
}
