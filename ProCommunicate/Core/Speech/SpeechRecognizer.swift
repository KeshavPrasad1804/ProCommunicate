import Foundation
import Observation
import WhisperKit

/// A transcript with word timings (seconds from the start of the clip).
struct Transcript: Sendable, Equatable {
    struct Word: Sendable, Equatable {
        let text: String
        let start: Double
        let end: Double
    }

    let text: String
    let words: [Word]
}

/// Downloads and stores the Whisper speech model (Core ML, runs on the Neural Engine).
@MainActor @Observable
final class SpeechModelManager {
    static let shared = SpeechModelManager()

    /// English-only small Whisper, quantized (~217 MB): more accurate on Indian-accented English
    /// than "base", still light enough to run next to Gemma.
    static let variant = "openai_whisper-small.en_217MB"
    static let approximateBytes: Int64 = 217_000_000

    enum State: Equatable {
        case notDownloaded
        case downloading(fraction: Double)
        case ready
        case failed(String)
    }

    private(set) var state: State = .notDownloaded
    private static let folderKey = "speechModelFolder"

    var isReady: Bool { state == .ready }

    /// Where WhisperKit put the model files.
    var modelFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: Self.folderKey) else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    init() {
        state = modelFolder != nil ? .ready : .notDownloaded
    }

    static var downloadBase: URL {
        let url = URL.applicationSupportDirectory.appending(path: "SpeechModels", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? ModelStorage.excludeFromBackup(url)
        return url
    }

    func download() {
        if case .downloading = state { return }
        state = .downloading(fraction: 0)
        Task {
            do {
                let folder = try await WhisperKit.download(variant: Self.variant, downloadBase: Self.downloadBase) { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        if case .downloading = SpeechModelManager.shared.state {
                            SpeechModelManager.shared.state = .downloading(fraction: fraction)
                        }
                    }
                }
                UserDefaults.standard.set(folder.path, forKey: Self.folderKey)
                state = .ready
            } catch {
                state = .failed("The speech model download stopped: \(error.localizedDescription)")
            }
        }
    }

    func delete() {
        Task { await SpeechRecognizer.shared.unload() }
        try? FileManager.default.removeItem(at: Self.downloadBase)
        UserDefaults.standard.removeObject(forKey: Self.folderKey)
        state = .notDownloaded
    }
}

/// Turns recorded speech (16 kHz mono) into text with word timings, on the device.
actor SpeechRecognizer {
    static let shared = SpeechRecognizer()

    private var whisper: WhisperKit?
    private var loadedFolder: URL?

    func load(folder: URL) async throws {
        if loadedFolder == folder, whisper != nil { return }
        let config = WhisperKitConfig(modelFolder: folder.path, verbose: false, logLevel: .error,
                                      prewarm: true, load: true, download: false)
        whisper = try await WhisperKit(config)
        loadedFolder = folder
    }

    func unload() {
        whisper = nil
        loadedFolder = nil
    }

    var isLoaded: Bool { whisper != nil }

    /// Transcribes English speech. Whisper keeps the words as said, including grammar mistakes,
    /// which is what the corrections need (to be confirmed on Tamil-accented speech: PLAN.md test 1).
    func transcribe(_ samples: [Float]) async throws -> Transcript {
        guard let whisper else { throw LlamaError.notLoaded }
        guard samples.count > 16_000 / 4 else { return Transcript(text: "", words: []) }
        let options = DecodingOptions(language: "en", temperature: 0, usePrefillPrompt: true,
                                      skipSpecialTokens: true, wordTimestamps: true)
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        var words: [Transcript.Word] = []
        var text = ""
        for result in results {
            text += result.text
            for segment in result.segments {
                for word in segment.words ?? [] {
                    words.append(Transcript.Word(text: word.word.trimmingCharacters(in: .whitespaces),
                                                 start: Double(word.start), end: Double(word.end)))
                }
            }
        }
        return Transcript(text: Self.clean(text), words: words)
    }

    /// Removes Whisper's bracketed non-speech tags like "[BLANK_AUDIO]" or "(coughs)".
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
