import SwiftData
import SwiftUI

/// What ProCommunicate keeps on your iPhone, and how long call audio is kept.
struct StorageView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(RecordingCleanup.keepDaysKey) private var keepDays = RecordingCleanup.defaultKeepDays
    @State private var sizes: Sizes?
    @State private var freed: RecordingCleanup.Result?

    struct Sizes {
        var aiModel: Int64
        var speechModel: Int64
        var recordings: Int64
        var personalised: Int64
    }

    var body: some View {
        List {
            Section {
                if let sizes {
                    row("AI tutor model", "sparkles", sizes.aiModel)
                    row("Speech model", "waveform", sizes.speechModel)
                    row("Your recordings", "mic.fill", sizes.recordings)
                    row("Written for you (AI)", "doc.text", sizes.personalised)
                } else {
                    ProgressView()
                }
            } header: {
                Text("On this iPhone")
            } footer: {
                Text("Everything stays on your iPhone. The models are kept out of iCloud backup and can be downloaded again any time.")
            }

            Section {
                Picker(selection: $keepDays) {
                    Text("30 days").tag(30)
                    Text("60 days").tag(60)
                    Text("90 days").tag(90)
                    Text("Forever").tag(0)
                } label: {
                    Label("Keep call audio", systemImage: "clock.arrow.circlepath")
                }
                Button("Clean up now", systemImage: "trash") {
                    freed = RecordingCleanup.run(in: modelContext, keepDays: keepDays)
                    Task { await measure() }
                }
                .disabled(keepDays == 0)
                if let freed {
                    Text(freed.files == 0 ? "Nothing old enough to remove." : "Removed \(freed.files) old \(freed.files == 1 ? "clip" : "clips"), freed \(freed.bytes.formattedBytes).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Recordings")
            } footer: {
                Text("Old audio is removed automatically. Starred recordings and the clip saved with each mistake are always kept, and so are your transcripts, reports and progress.")
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task { await measure() }
    }

    private func row(_ title: String, _ icon: String, _ bytes: Int64) -> some View {
        LabeledContent {
            Text(bytes == 0 ? "—" : bytes.formattedBytes).monospacedDigit()
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func measure() async {
        let ai = AIModelManager.shared.modelFileURL
        let speech = SpeechModelManager.downloadBase
        let recordings = RecordingStorage.directory
        let adaptive = AdaptiveStore.defaultURL.deletingLastPathComponent()
        sizes = await Task.detached {
            Sizes(aiModel: RecordingCleanup.size(of: ai), speechModel: RecordingCleanup.size(of: speech),
                  recordings: RecordingCleanup.size(of: recordings), personalised: RecordingCleanup.size(of: adaptive))
        }.value
    }
}
