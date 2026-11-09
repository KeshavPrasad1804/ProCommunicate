import SwiftData
import SwiftUI

/// Every mistake from your calls and drills, grouped by pattern, until you stop making it.
struct MistakesView: View {
    @Query(sort: [SortDescriptor(\MistakeRecord.count, order: .reverse), SortDescriptor(\MistakeRecord.lastSeen, order: .reverse)])
    private var mistakes: [MistakeRecord]

    var body: some View {
        let improving = mistakes.filter { Date().timeIntervalSince($0.lastSeen) > 14 * 86_400 }
        let active = mistakes.filter { Date().timeIntervalSince($0.lastSeen) <= 14 * 86_400 }
        List {
            if mistakes.isEmpty {
                ContentUnavailableView("No mistakes yet",
                                       systemImage: "checkmark.seal",
                                       description: Text("Mistakes from your calls, drills and retries will collect here, grouped by pattern."))
            }
            if !active.isEmpty {
                Section {
                    ForEach(active) { mistake in
                        NavigationLink { MistakeDetailView(mistake: mistake) } label: { MistakeRow(mistake: mistake) }
                    }
                } header: {
                    Text("Working on")
                } footer: {
                    Text("Seen in the last 2 weeks. They also come back in Review.")
                }
            }
            if !improving.isEmpty {
                Section {
                    ForEach(improving) { mistake in
                        NavigationLink { MistakeDetailView(mistake: mistake) } label: { MistakeRow(mistake: mistake) }
                    }
                } header: {
                    Text("Improving")
                } footer: {
                    Text("Not heard for 2 weeks or more. Nice work.")
                }
            }
        }
        .navigationTitle("My Mistakes")
    }
}

private struct MistakeRow: View {
    let mistake: MistakeRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(mistake.title).font(.headline).lineLimit(2)
                Spacer()
                Text("×\(mistake.count)").font(.caption.weight(.bold)).foregroundStyle(.orange)
            }
            Text("\(mistake.wrong) → \(mistake.right)").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Text("Last: \(mistake.lastSeen.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct MistakeDetailView: View {
    @Bindable var mistake: MistakeRecord
    @State private var loading = false
    @State private var errorText: String?
    @State private var saidCount = 0

    var body: some View {
        List {
            Section("What you said") {
                Label(mistake.wrong, systemImage: "xmark.circle.fill").foregroundStyle(.orange)
                if let context = mistake.lastContext {
                    Text("\"\(context)\"").font(.callout).foregroundStyle(.secondary)
                }
                if let clip = mistake.lastClipFile { ClipButton(fileName: clip, title: "Hear yourself") }
            }
            Section("Say it this way") {
                Label(mistake.right, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text(mistake.why).font(.subheadline)
                if let tamil = mistake.whyNative {
                    Text(tamil).font(.subheadline)
                } else {
                    Button {
                        Task { await explain() }
                    } label: {
                        if loading { ProgressView() } else { Label("Explain in \(NativeLanguage.current.name)", systemImage: "character.bubble") }
                    }
                    .disabled(loading || !TutorService.isAvailable)
                    if let errorText { Text(errorText).font(.caption).foregroundStyle(.orange) }
                }
            }
            Section {
                HStack {
                    SpeakButton(text: speakable)
                    SpeakButton(text: speakable, slow: true)
                }
                Button {
                    saidCount = min(3, saidCount + 1)
                } label: {
                    Label(saidCount >= 3 ? "Done: said it 3 times" : "I said it out loud (\(saidCount)/3)",
                          systemImage: saidCount >= 3 ? "checkmark.seal.fill" : "mouth")
                }
                .disabled(saidCount >= 3)
            } header: {
                Text("Practise")
            } footer: {
                Text("Hear it, then say the correct version out loud three times.")
            }
            Section {
                LabeledContent("Times heard", value: "\(mistake.count)")
                LabeledContent("First", value: mistake.firstSeen.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Last", value: mistake.lastSeen.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .navigationTitle(mistake.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// For pattern rules the "right" text is a template ("I have …"); speak the explanation's example instead.
    private var speakable: String {
        if mistake.right.contains("…"), let quote = mistake.why.range(of: #""[^"]+""#, options: .regularExpression) {
            return String(mistake.why[quote]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return mistake.right
    }

    private func explain() async {
        loading = true
        defer { loading = false }
        do {
            mistake.whyNative = try await TutorService.explainInNative(wrong: mistake.wrong, right: mistake.right, why: mistake.why)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
