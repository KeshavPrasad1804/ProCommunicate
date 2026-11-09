import Foundation
import UIKit

/// Gemma listening to the learner directly (no separate speech model), in two steps, as tested on the Mac
/// (bench/LISTEN_RESULTS.md):
/// 1. Gemma hears the clip and writes down exactly what was said: Tamil/Hindi script, Tanglish/Hinglish or English, mistakes kept.
/// 2. Gemma reads that transcript (text, where it's strongest) and works out what the learner meant and the English to say.
/// Asking for the meaning straight from audio made things up, so the steps stay separate.
enum Listening {
    /// Audio-only Gemma 4 E2B encoder, made by tools/strip_mmproj.py from unsloth's mmproj-F16.gguf (pinned commit).
    static let fileName = "gemma-4-E2B-audio-F16.gguf"
    static var fileURL: URL { ModelStorage.directory.appending(path: fileName) }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    struct Understanding: Sendable, Equatable {
        var transcript: String
        var meaning: String
        var say: String
        var listenSeconds: Double
        var thinkSeconds: Double
    }

    static let transcribeInstruction = """
    Transcribe exactly what the speaker says, word for word, in the language and script they actually use \
    (Tamil script for Tamil, Devanagari for Hindi, Latin letters for English words and for Tanglish or Hinglish). \
    Do not translate and do not correct grammar mistakes. Output only the transcript.
    """

    static func meaningSystem(_ language: NativeLanguage = .current) -> String {
        """
        You are an English tutor for an Indian IT professional whose first language is \(language.name). The learner spoke to you; \
        the user message is an automatic speech transcript, which may contain recognition errors (English words written in \(language.scriptName), \
        or \(language.name) words in English letters). Work out what they most likely meant. Reply in exactly two lines:
        MEANING: what they mean or ask, in English.
        SAY: the natural, professional English sentence they could say at work.
        """
    }

    /// Loads Gemma and its listening part if needed.
    static func ensureLoaded() async throws {
        try await TutorService.ensureLoaded()
        guard isInstalled else { throw LlamaError.audioNotLoaded }
        try await LlamaEngine.shared.loadAudio(path: fileURL.path)
    }

    /// Step 1: exact transcript of a 16 kHz mono clip.
    static func transcribe(_ samples: [Float]) async throws -> (text: String, seconds: Double) {
        try await ensureLoaded()
        let start = Date()
        let result = try await LlamaEngine.shared.listen(samples: samples, instruction: transcribeInstruction,
                                                         options: GenerationOptions(maxTokens: 160, temperature: 0))
        return (result.text, Date().timeIntervalSince(start))
    }

    /// Both steps: what was said, what it means, and the English to say.
    static func understand(_ samples: [Float], language: NativeLanguage = .current) async throws -> Understanding {
        let heard = try await transcribe(samples)
        let start = Date()
        let prompt = GemmaPrompt.format([ChatMessage(role: .system, content: meaningSystem(language)),
                                         ChatMessage(role: .user, content: "Transcript: \(heard.text)")])
        let reply = try await LlamaEngine.shared.generate(prompt: prompt, slot: .utility,
                                                          options: GenerationOptions(maxTokens: 120, temperature: 0)).text
        let parsed = parse(reply)
        return Understanding(transcript: heard.text, meaning: parsed.meaning, say: parsed.say,
                             listenSeconds: heard.seconds, thinkSeconds: Date().timeIntervalSince(start))
    }

    /// Reads the "MEANING: … / SAY: …" reply.
    static func parse(_ reply: String) -> (meaning: String, say: String) {
        var meaning = "", say = ""
        for line in reply.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("MEANING:") {
                meaning = String(trimmed.dropFirst("MEANING:".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.uppercased().hasPrefix("SAY:") {
                say = String(trimmed.dropFirst("SAY:".count)).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            }
        }
        return (meaning, say)
    }
}

/// Runs the listening test on every clip in a folder and writes a report (for the AI test lab, and for
/// unattended runs on a connected iPhone: launch with `-runListenTest YES`, then copy
/// Library/Caches/listen-test.txt off the phone).
enum ListeningBenchmark {
    static var reportURL: URL { URL.cachesDirectory.appending(path: "listen-test.txt") }
    static var clipFolder: URL { URL.documentsDirectory.appending(path: "ListenTest", directoryHint: .isDirectory) }

    @MainActor
    static func run(language: NativeLanguage = .current) async {
        var lines: [String] = []
        func log(_ line: String) {
            lines.append(line)
            try? lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        }
        func memory() -> String {
            "memory \(Int64(MemoryUsage.footprintBytes()).formattedBytes), left \(Int64(MemoryUsage.availableBytes()).formattedBytes)"
        }
        // Keep the screen on: iOS stops GPU work if the phone locks.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        log("Listening test · \(Date.now.formatted()) · \(memory())")
        do {
            let start = Date()
            try await TutorService.ensureLoaded()
            log(String(format: "Gemma loaded in %.1f s · %@", Date().timeIntervalSince(start), memory()))
            let audioStart = Date()
            try await LlamaEngine.shared.loadAudio(path: Listening.fileURL.path)
            log(String(format: "Listening part loaded in %.1f s · %@", Date().timeIntervalSince(audioStart), memory()))
        } catch {
            log("Load failed: \(error.localizedDescription)")
            return
        }
        let clips = ((try? FileManager.default.contentsOfDirectory(at: clipFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["wav", "m4a"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for clip in clips {
            guard let samples = try? AudioFileWriter.readSamples(from: clip), !samples.isEmpty else {
                log("\(clip.lastPathComponent): couldn't read"); continue
            }
            let name = clip.deletingPathExtension().lastPathComponent
            let clipLanguage: NativeLanguage = name.hasPrefix("hi") ? .hindi : (name.hasPrefix("ta") ? .tamil : language)
            do {
                let r = try await Listening.understand(samples, language: clipLanguage)
                log(String(format: "%@ (%.1f s audio): heard in %.1f s, understood in %.1f s · %@", name,
                           Double(samples.count) / VoiceCapture.sampleRate, r.listenSeconds, r.thinkSeconds, memory()))
                log("  heard: \(r.transcript)")
                log("  means: \(r.meaning)")
                log("  say:   \(r.say)")
            } catch {
                log("\(name): \(error.localizedDescription)")
            }
        }
        log("Done · \(memory())")
    }
}
