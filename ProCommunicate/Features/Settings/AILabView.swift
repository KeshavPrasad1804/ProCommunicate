import SwiftUI

/// "AI test lab": measures Gemma on this iPhone (load time, memory, speed) and tries the two
/// tutor jobs: role-play replies and answer checks. Results can be copied and shared.
struct AILabView: View {
    @Environment(AIModelManager.self) private var aiModel

    @State private var status = "Not loaded"
    @State private var busy = false
    @State private var lines: [String] = []
    @State private var liveText = ""
    @State private var customInput = "Good morning. Myself Priya, I am having three years experience in Java."

    var body: some View {
        List {
            Section {
                LabeledContent("Engine", value: LlamaEngine.isAvailable ? "llama.cpp (Metal)" : "Not available here")
                LabeledContent("Model", value: aiModel.isReady ? aiModel.model.displayName : "Not downloaded")
                LabeledContent("Status", value: status)
                LabeledContent("App memory now", value: Int64(MemoryUsage.footprintBytes()).formattedBytes)
                LabeledContent("Memory left before iOS closes the app", value: Int64(MemoryUsage.availableBytes()).formattedBytes)
            } footer: {
                if !LlamaEngine.isAvailable {
                    Text("The AI engine runs on a real iPhone only (not in the Simulator).")
                } else if !aiModel.isReady {
                    Text("Download the model first: Settings → AI tutor → Download.")
                }
            }

            Section {
                Button("1. Load the model", systemImage: "cpu") { Task { await loadModel() } }
                Button("2. Role-play test (HR interviewer)", systemImage: "person.wave.2") { Task { await rolePlayTest() } }
                Button("3. Answer-check test", systemImage: "checkmark.bubble") { Task { await checkTest(customInput) } }
                Button("Unload the model", systemImage: "eject", role: .destructive) {
                    Task {
                        await LlamaEngine.shared.unload()
                        status = "Unloaded"
                        log("Unloaded. App memory: \(Int64(MemoryUsage.footprintBytes()).formattedBytes)")
                    }
                }
            } header: {
                Text("Run the tests in order")
            }
            .disabled(busy || !LlamaEngine.isAvailable || !aiModel.isReady)

            Section("Try your own sentence") {
                TextField("Type an English sentence", text: $customInput, axis: .vertical)
                    .lineLimit(2...5)
                Button("Check this sentence", systemImage: "text.badge.checkmark") { Task { await checkTest(customInput) } }
                    .disabled(busy || !LlamaEngine.isAvailable || !aiModel.isReady || customInput.isEmpty)
            }

            if !liveText.isEmpty {
                Section("Live output") {
                    Text(liveText).font(.callout.monospaced())
                }
            }

            if !lines.isEmpty {
                Section {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                } header: {
                    HStack {
                        Text("Results")
                        Spacer()
                        ShareLink(item: lines.joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
                    }
                } footer: {
                    Text("Tap the share button to send these results.")
                }
            }
        }
        .navigationTitle("AI test lab")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if busy { ProgressView().controlSize(.large) } }
    }

    private func log(_ line: String) { lines.append(line) }

    private func loadModel() async {
        busy = true
        defer { busy = false }
        status = "Loading…"
        let before = MemoryUsage.footprintBytes()
        do {
            let seconds = try await LlamaEngine.shared.load(modelPath: aiModel.modelFileURL.path, contextSize: 4096)
            let after = MemoryUsage.footprintBytes()
            status = "Loaded"
            log(String(format: "Load: %.1f s · app memory %@ → %@ · left %@", seconds,
                       Int64(before).formattedBytes, Int64(after).formattedBytes,
                       Int64(MemoryUsage.availableBytes()).formattedBytes))
        } catch {
            status = "Failed"
            log("Load failed: \(error.localizedDescription)")
        }
    }

    private func rolePlayTest() async {
        busy = true
        defer { busy = false }
        let system = "Role-play for English practice. YOU are an HR interviewer at an IT company in Chennai. The user is a Tamil speaker improving their English (B1 level), applying for a Java developer job. Stay in your role. Reply ONLY in clear, natural, professional English, in at most 2 short sentences. End with one question."
        var messages = [ChatMessage(role: .system, content: system)]
        for turn in ["Good morning sir. Myself Priya, I am having three years experience in Java.",
                     "I am working in Infosys since 2021. I handled one banking project."] {
            messages.append(ChatMessage(role: .user, content: turn))
            let reply = await run(prompt: GemmaPrompt.format(messages), options: GenerationOptions(maxTokens: 120, temperature: 0.7), label: "Role-play")
            messages.append(ChatMessage(role: .assistant, content: reply))
        }
    }

    private func checkTest(_ answer: String) async {
        busy = true
        defer { busy = false }
        let prompt = GemmaPrompt.format([
            ChatMessage(role: .system, content: TutorPrompts.answerCheckSystem),
            ChatMessage(role: .user, content: answer),
        ])
        let json = await run(prompt: prompt, options: GenerationOptions(maxTokens: 500, temperature: 0, grammar: TutorPrompts.answerCheckGrammar), label: "Check")
        if let check = TutorPrompts.parseAnswerCheck(json, answer: answer) {
            log("Better: \(check.better)")
            for mistake in check.mistakes { log("  ✗ \(mistake.wrong) → \(mistake.right) (\(mistake.why))") }
            if check.mistakes.isEmpty { log("  ✓ No mistakes found") }
        } else {
            log("Couldn't read the answer check.")
        }
    }

    /// Runs one generation, streaming into the live box, and logs speed and memory.
    private func run(prompt: String, options: GenerationOptions, label: String) async -> String {
        liveText = ""
        do {
            let result = try await LlamaEngine.shared.generate(prompt: prompt, options: options) { piece in
                Task { @MainActor in liveText += piece }
            }
            let s = result.stats
            log(String(format: "%@: %d tokens at %.1f tok/s · first token %.1f s · prompt %d (reused %d) · memory %@",
                       label, s.generatedTokens, s.tokensPerSecond, s.firstTokenSeconds, s.promptTokens, s.reusedTokens,
                       Int64(MemoryUsage.footprintBytes()).formattedBytes))
            if options.grammar == nil { log("  → \(result.text)") }
            return result.text
        } catch {
            log("\(label) failed: \(error.localizedDescription)")
            return ""
        }
    }
}

#Preview {
    NavigationStack { AILabView() }
        .environment(AIModelManager.shared)
}
