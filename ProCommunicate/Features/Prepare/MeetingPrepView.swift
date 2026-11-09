import SwiftData
import SwiftUI

/// "I have a meeting tomorrow": describe it, get a cheat sheet of phrases, then rehearse the call.
struct MeetingPrepView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var about = ""
    @State private var who = ""
    @State private var sheet: CheatSheet?
    @State private var working = false
    @State private var errorText: String?
    @State private var saved = false

    struct CheatSheet: Codable, Equatable {
        struct Item: Codable, Equatable, Hashable { let english: String; let when: String }
        let phrases: [Item]
        let tips: [String]
    }

    static let grammar = #"""
    root ::= "{" ws "\"phrases\":" ws "[" ws item ( ws "," ws item ){2,5} ws "]" ws "," ws "\"tips\":" ws "[" ws string ( ws "," ws string ){0,2} ws "]" ws "}"
    item ::= "{" ws "\"english\":" ws string ws "," ws "\"when\":" ws string ws "}"
    string ::= "\"" char{1,220} "\""
    char ::= [^"\\\x7F\x00-\x1F] | "\\" ( ["\\/bfnrt] | "u" [0-9a-fA-F]{4} )
    ws ::= [ \t\n]{0,10}
    """#

    static let system = """
    You are an English coach for Tamil-speaking IT professionals. The learner describes a real meeting or call they will have soon, in English, Tamil or Tanglish. \
    Give 4 to 6 ready-to-say, natural, polite professional English phrases for THAT exact situation, each with a short note (in simple English) on when to use it, \
    and up to 3 short tips. Never use Indian-English phrases like revert back, do the needful, today itself, prepone or "I have one doubt".
    """

    var body: some View {
        List {
            Section {
                TextField("What's the meeting about?", text: $about, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Who will be there? (e.g. UK client, my manager)", text: $who)
            } header: {
                Text("Your meeting")
            } footer: {
                Text("Write in English, Tamil or Tanglish, e.g. \"naalaikku client call la delay pathi sollanum\".")
            }
            Section {
                Button {
                    Task { await makeSheet() }
                } label: {
                    if working { HStack { ProgressView(); Text("Writing your cheat sheet…") } }
                    else { Label("Make my cheat sheet", systemImage: "wand.and.stars") }
                }
                .disabled(about.trimmingCharacters(in: .whitespaces).isEmpty || working || !TutorService.isAvailable)
                if !TutorService.isAvailable {
                    Text("Needs the AI tutor: Settings → AI tutor.").font(.caption).foregroundStyle(.secondary)
                }
                if let errorText { Text(errorText).font(.caption).foregroundStyle(.orange) }
            }
            if let sheet {
                Section("Say these") {
                    ForEach(sheet.phrases, id: \.self) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Text(item.english).font(.body.weight(.medium))
                                Spacer(minLength: 8)
                                SpeakButton(text: item.english)
                            }
                            Text(item.when).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    Button(saved ? "Saved to Review" : "Save all to Review", systemImage: saved ? "checkmark" : "tray.and.arrow.down") {
                        save(sheet)
                    }
                    .disabled(saved)
                }
                if !sheet.tips.isEmpty {
                    Section("Tips") {
                        ForEach(sheet.tips, id: \.self) { Label($0, systemImage: "lightbulb") }
                    }
                }
                Section {
                    Button {
                        let phrases = sheet.phrases.map(\.english).joined(separator: " | ")
                        router.startCall(ScenarioLoader.rehearsal(description: about, who: who),
                                         extraContext: "Phrases the learner wants to practise: \(phrases)")
                    } label: {
                        Label("Rehearse this call (5 minutes)", systemImage: "phone.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .navigationTitle("Meeting prep")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func makeSheet() async {
        working = true
        errorText = nil
        saved = false
        defer { working = false }
        do {
            let json = try await TutorService.json(system: Self.system,
                                                   user: "Meeting: \(about)\nWho will be there: \(who.isEmpty ? "not said" : who)",
                                                   grammar: Self.grammar, maxTokens: 700)
            sheet = try JSONDecoder().decode(CheatSheet.self, from: Data(json.utf8))
        } catch {
            errorText = "Couldn't make the cheat sheet: \(error.localizedDescription)"
        }
    }

    private func save(_ sheet: CheatSheet) {
        let due = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        for item in sheet.phrases {
            let id = "prep.\(AnswerChecker.normalize(item.english).prefix(60))"
            modelContext.insert(ReviewCard(id: id, kind: .phrase, front: item.when, back: item.english,
                                           hint: about, lessonId: nil, due: due))
        }
        try? modelContext.save()
        saved = true
    }
}
