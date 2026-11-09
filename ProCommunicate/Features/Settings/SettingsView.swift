import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIModelManager.self) private var aiModel
    @AppStorage(SettingsKey.aiTutorEnabled) private var aiTutorEnabled = false
    @AppStorage(SpeechVoice.settingsKey) private var speechVoice = SpeechVoice.indian.rawValue
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = 20
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKey.reminderMinuteOfDay) private var reminderMinute = 19 * 60
    @State private var reminderDenied = false

    private let deviceSupported = DeviceCapability.supportsAITutor()

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinute / 60, minute: reminderMinute % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinute = (parts.hour ?? 19) * 60 + (parts.minute ?? 0)
        }
    }

    private func updateReminder(on: Bool) {
        guard on else {
            ReminderScheduler.cancel()
            reminderDenied = false
            return
        }
        Task {
            let allowed = await ReminderScheduler.requestPermission()
            reminderDenied = !allowed
            if allowed { ReminderScheduler.schedule(minuteOfDay: reminderMinute, goalMinutes: dailyGoal) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $aiTutorEnabled) {
                        Label("AI tutor", systemImage: "sparkles")
                    }
                    .disabled(!deviceSupported)
                } footer: {
                    if deviceSupported {
                        Text("Powers call practice, the mock interview and meeting simulation, corrections, and Ask in Tamil. Runs entirely on your iPhone: nothing you say is sent anywhere. Lessons and review work without it.")
                    } else {
                        Text("This iPhone doesn't have enough memory for the AI tutor (it needs 6 GB). Lessons and review still work.")
                    }
                }

                if deviceSupported && (aiTutorEnabled || aiModel.state != .notDownloaded) {
                    AIModelSection(aiTutorEnabled: aiTutorEnabled)
                }

                Section {
                    Picker(selection: $dailyGoal) {
                        Text("10 minutes").tag(10)
                        Text("20 minutes").tag(20)
                        Text("30 minutes").tag(30)
                    } label: {
                        Label("Daily goal", systemImage: "target")
                    }
                    Toggle(isOn: $reminderEnabled) {
                        Label("Daily reminder", systemImage: "bell.fill")
                    }
                    if reminderEnabled {
                        DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                    if reminderDenied {
                        Text("Notifications are off for ProCommunicate. Turn them on in iPhone Settings → Notifications.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Daily practice")
                }
                .onChange(of: reminderEnabled) { _, on in updateReminder(on: on) }
                .onChange(of: reminderMinute) { _, _ in updateReminder(on: reminderEnabled) }
                .onChange(of: dailyGoal) { _, _ in updateReminder(on: reminderEnabled) }

                Section {
                    Picker(selection: $speechVoice) {
                        ForEach(SpeechVoice.allCases) { voice in
                            Text(voice.title).tag(voice.rawValue)
                        }
                    } label: {
                        Label("Voice", systemImage: "speaker.wave.2.fill")
                    }
                    Button("Play a sample", systemImage: "play.circle") {
                        Speaker.shared.speak("We're on track to deliver by Friday.",
                                             voice: SpeechVoice(rawValue: speechVoice) ?? .indian)
                    }
                } header: {
                    Text("Speaking voice")
                } footer: {
                    Text("Used for phrases and listening practice. For a more natural voice, download an \"Enhanced\" English voice in iPhone Settings → Accessibility → Spoken Content → Voices.")
                }

                if aiModel.isReady {
                    Section {
                        NavigationLink {
                            AILabView()
                        } label: {
                            Label("AI test lab", systemImage: "flask")
                        }
                    } footer: {
                        Text("Measure the AI's speed and memory on this iPhone, and try role-play and answer checks.")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Download, progress, verification and deletion of the on-device model.
struct AIModelSection: View {
    let aiTutorEnabled: Bool
    @Environment(AIModelManager.self) private var aiModel
    @State private var confirmDelete = false
    @State private var confirmCancel = false

    var body: some View {
        @Bindable var aiModel = aiModel
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(aiModel.model.displayName).font(.headline)
                Text("\(aiModel.model.detail) · \(aiModel.model.sizeBytes.formattedBytes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            switch aiModel.state {
            case .notDownloaded:
                notDownloadedRows(useMobileData: $aiModel.useMobileData)

            case .downloading(let received, let total):
                progressRows(received: received, total: total, title: "Downloading…")
                Button("Pause", systemImage: "pause.fill") { aiModel.pauseDownload() }
                Button("Cancel download", systemImage: "xmark", role: .destructive) { confirmCancel = true }

            case .paused(let received, let total):
                progressRows(received: received, total: total, title: "Paused")
                Button("Resume", systemImage: "play.fill") { aiModel.resumeDownload() }
                Button("Cancel download", systemImage: "xmark", role: .destructive) { confirmCancel = true }

            case .verifying:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Checking the download…")
                }

            case .ready:
                Label("Ready · works offline", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if !aiTutorEnabled {
                    Text("The AI tutor is off. The model stays downloaded, so you can turn it back on instantly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Delete model (frees \(aiModel.model.sizeBytes.formattedBytes))", systemImage: "trash", role: .destructive) {
                    confirmDelete = true
                }

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                Button(aiModel.hasResumeData ? "Resume download" : "Try again", systemImage: "arrow.clockwise") {
                    aiModel.startDownload()
                }
                if aiModel.hasResumeData {
                    Button("Cancel download", systemImage: "xmark", role: .destructive) { confirmCancel = true }
                }
            }
        } header: {
            Text("AI model")
        } footer: {
            footer
        }
        .confirmationDialog("Delete the AI model?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete model", role: .destructive) { aiModel.deleteModel() }
        } message: {
            Text("Call practice and corrections will need the model again. Downloading it takes \(aiModel.model.sizeBytes.formattedBytes).")
        }
        .confirmationDialog("Cancel the download?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel download", role: .destructive) { aiModel.cancelDownload() }
            Button("Keep downloading", role: .cancel) {}
        } message: {
            Text("What's been downloaded so far will be deleted.")
        }
    }

    @ViewBuilder
    private func notDownloadedRows(useMobileData: Binding<Bool>) -> some View {
        let available = DeviceCapability.availableStorageBytes()
        let enoughRoom = available.map { DeviceCapability.hasRoom(forDownloadOf: aiModel.model.sizeBytes, available: $0) } ?? true
        if let available {
            LabeledContent("Free on this iPhone", value: available.formattedBytes)
        }
        Toggle("Download over mobile data", isOn: useMobileData)
        Button {
            aiModel.startDownload()
        } label: {
            Label("Download (\(aiModel.model.sizeBytes.formattedBytes))", systemImage: "arrow.down.circle.fill")
        }
        .disabled(!enoughRoom)
        if !enoughRoom {
            Text("Free up some space first: you need about \((aiModel.model.sizeBytes + DeviceCapability.storageMarginBytes).formattedBytes) free.")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func progressRows(received: Int64, total: Int64, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: aiModel.state.fraction ?? 0) {
                Text(title).font(.subheadline.weight(.semibold))
            }
            Text("\(received.formattedBytes) of \(total.formattedBytes) · \(Int(((aiModel.state.fraction ?? 0) * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var footer: some View {
        switch aiModel.state {
        case .notDownloaded:
            Text(aiModel.useMobileData
                 ? "One-time download. After that, the AI works without internet."
                 : "One-time download over Wi-Fi. If you're on mobile data, it waits until you're on Wi-Fi. After that, the AI works without internet.")
        case .downloading:
            Text("You can leave the app; the download continues in the background.")
        default:
            EmptyView()
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(AIModelManager.shared)
}
