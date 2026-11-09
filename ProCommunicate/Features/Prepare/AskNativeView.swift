import SwiftData
import SwiftUI

/// Ask in your language (script or romanised, e.g. Tanglish / Hinglish); get professional English to use
/// (tested on the Mac: bench/TAMIL_RESULTS.md, bench/HINDI_RESULTS.md).
struct AskNativeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var question = ""
    @State private var answer = ""
    @State private var asked = ""
    @State private var working = false
    @State private var errorText: String?
    @State private var savedSentences: Set<String> = []

    static var system: String {
        let l = NativeLanguage.current
        return """
        You are a friendly English coach for \(l.name) speakers. The learner may write in \(l.name) (\(l.scriptName)), in \(l.romanisedName) (\(l.name) written in English letters), or in English. \
        Give them 1-2 ready-to-use professional English sentences (or a short email if they ask for one), then one or two short lines in simple \(l.name) (\(l.scriptName)) explaining when to use it. \(l.styleNote) \
        Keep the whole answer short. Never use Indian-English phrases like revert back, do the needful, today itself or prepone.
        """
    }

    private var language: NativeLanguage { NativeLanguage.current }

    var body: some View {
        List {
            Section {
                TextField(language.askPlaceholder, text: $question, axis: .vertical)
                    .lineLimit(2...6)
                Button {
                    Task { await ask() }
                } label: {
                    if working { HStack { ProgressView(); Text("Thinking…") } } else { Label("Ask", systemImage: "paperplane.fill") }
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || working || !TutorService.isAvailable)
            } header: {
                Text("Ask in \(language.name), \(language.romanisedName) or English")
            } footer: {
                if TutorService.isAvailable {
                    Text("For example: \"\(language.askExample)\"")
                } else {
                    Text("Needs the AI tutor: Settings → AI tutor.")
                }
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.orange) }
            }
            if !answer.isEmpty {
                Section {
                    Text(.init(answer)).textSelection(.enabled)
                } header: {
                    Text(asked).textCase(nil)
                }
                let sentences = Self.englishSentences(in: answer)
                if !working, !sentences.isEmpty {
                    Section("Say it, then save it to Review") {
                        ForEach(sentences, id: \.self) { sentence in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sentence)
                                HStack {
                                    SpeakButton(text: sentence)
                                    Button(savedSentences.contains(sentence) ? "Saved" : "Save",
                                           systemImage: savedSentences.contains(sentence) ? "checkmark" : "tray.and.arrow.down") {
                                        save(sentence)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(savedSentences.contains(sentence))
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Ask in \(language.name)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ask() async {
        working = true
        errorText = nil
        answer = ""
        asked = question
        defer { working = false }
        do {
            let final = try await TutorService.ask(system: Self.system, user: question) { piece in
                Task { @MainActor in answer += piece }
            }
            answer = final
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func save(_ sentence: String) {
        let due = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let id = "ask.\(AnswerChecker.normalize(sentence).prefix(60))"
        modelContext.insert(ReviewCard(id: id, kind: .phrase, front: asked, back: sentence, hint: nil, lessonId: nil, due: due))
        try? modelContext.save()
        savedSentences.insert(sentence)
    }

    /// English sentences from the answer (no Indian-script lines, no bracketed transliterations), without markdown or quotes.
    nonisolated static func englishSentences(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: #"^\s*([-*•]|\d+\.)\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^(Option \d+[^:]*|English|Formal|Polite)[^:]{0,30}:\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”>"))
            }
            .filter { line in
                line.count > 12
                    && !line.unicodeScalars.contains { (0x0900...0x0DFF).contains($0.value) }
                    && !line.hasPrefix("(")
                    && line.contains(where: \.isLetter)
                    && !line.hasSuffix(":")
            }
    }
}
