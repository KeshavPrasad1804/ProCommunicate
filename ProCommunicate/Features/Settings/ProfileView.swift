import SwiftUI

/// Speech model (Whisper) download row for Settings.
struct SpeechModelSection: View {
    private var speech: SpeechModelManager { SpeechModelManager.shared }
    @State private var confirmDelete = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speech recognition (Whisper small)").font(.headline)
                Text("OpenAI Whisper via WhisperKit · English · \(SpeechModelManager.approximateBytes.formattedBytes)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            switch speech.state {
            case .notDownloaded:
                Button("Download speech model", systemImage: "arrow.down.circle.fill") { speech.download() }
            case .downloading(let fraction):
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: fraction) { Text("Downloading…").font(.subheadline.weight(.semibold)) }
                    Text("\(Int((fraction * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            case .ready:
                Label("Ready · works offline", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Delete speech model", systemImage: "trash", role: .destructive) { confirmDelete = true }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.subheadline)
                Button("Try again", systemImage: "arrow.clockwise") { speech.download() }
            }
        } footer: {
            Text("Lets you answer calls and drills by voice. Without it, you type your answers.")
        }
        .confirmationDialog("Delete the speech model?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { speech.delete() }
        }
    }
}

/// About you: used to make calls and interviews fit your real job.
struct ProfileView: View {
    @AppStorage(LearnerProfile.Key.name) private var name = ""
    @AppStorage(LearnerProfile.Key.role) private var role = ""
    @AppStorage(LearnerProfile.Key.company) private var company = ""
    @AppStorage(LearnerProfile.Key.years) private var years = ""
    @AppStorage(LearnerProfile.Key.project) private var project = ""
    @AppStorage(LearnerProfile.Key.target) private var target = ""

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $name).textContentType(.name)
                TextField("Your role (e.g. Java developer)", text: $role)
                TextField("Company (optional)", text: $company)
                TextField("Years of experience", text: $years).keyboardType(.decimalPad)
            } header: {
                Text("You")
            }
            Section {
                TextField("Your current project, in a few words", text: $project, axis: .vertical).lineLimit(2...4)
                TextField("What you're preparing for (e.g. senior developer interviews)", text: $target, axis: .vertical).lineLimit(2...4)
            } header: {
                Text("Your work")
            } footer: {
                Text("The AI uses this so clients and interviewers talk about your real work. It stays on your iPhone.")
            }
        }
        .navigationTitle("About you")
        .navigationBarTitleDisplayMode(.inline)
    }
}
