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
    nonisolated static let variant = "openai_whisper-small.en_217MB"
    static let approximateBytes: Int64 = 217_000_000

    enum State: Equatable {
        case notDownloaded
        case downloading(fraction: Double)
        case ready
        case failed(String)
    }

    private(set) var state: State = .notDownloaded
    /// True while speech recognition is being loaded. The first load after installing or updating
    /// the app takes about 2–3 minutes (iOS prepares the model for this iPhone's Neural Engine);
    /// after that it takes a few seconds.
    var isWarmingUp = false
    /// Path of the model folder *relative to* `downloadBase`. (An absolute path breaks after app
    /// updates, because iOS can move the app's data folder; the files themselves are kept.)
    private static let relativeFolderKey = "speechModelRelativeFolder"

    var isReady: Bool { state == .ready }

    /// Where the model files are, if they're all there.
    var modelFolder: URL? {
        Self.resolveFolder(base: Self.downloadBase, storedRelative: UserDefaults.standard.string(forKey: Self.relativeFolderKey))
    }

    /// The folders a WhisperKit model needs.
    nonisolated static let requiredParts = ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]

    /// Finds a complete model: first the saved relative path, then where WhisperKit downloads to.
    nonisolated static func resolveFolder(base: URL, storedRelative: String?) -> URL? {
        var candidates: [URL] = []
        if let storedRelative, !storedRelative.isEmpty { candidates.append(base.appending(path: storedRelative, directoryHint: .isDirectory)) }
        candidates.append(base.appending(path: "models/argmaxinc/whisperkit-coreml/\(variant)", directoryHint: .isDirectory))
        return candidates.first { folder in
            requiredParts.allSatisfy { FileManager.default.fileExists(atPath: folder.appending(path: $0).path(percentEncoded: false)) }
        }
    }

    nonisolated static func relativePath(of folder: URL, base: URL) -> String? {
        let full = folder.standardizedFileURL.path(percentEncoded: false)
        let root = base.standardizedFileURL.path(percentEncoded: false)
        guard full.hasPrefix(root) else { return nil }
        return String(full.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
                if let relative = Self.relativePath(of: folder, base: Self.downloadBase) {
                    UserDefaults.standard.set(relative, forKey: Self.relativeFolderKey)
                }
                state = modelFolder != nil ? .ready : .failed("The speech model download looks incomplete. Please try again.")
            } catch {
                state = .failed("The speech model download stopped: \(error.localizedDescription)")
            }
        }
    }

    func delete() {
        Task { await SpeechRecognizer.shared.unload() }
        try? FileManager.default.removeItem(at: Self.downloadBase)
        UserDefaults.standard.removeObject(forKey: Self.relativeFolderKey)
        UserDefaults.standard.removeObject(forKey: "speechModelFolder")   // old absolute-path key
        state = .notDownloaded
    }
}

/// Turns recorded speech (16 kHz mono) into text with word timings, on the device.
actor SpeechRecognizer {
    static let shared = SpeechRecognizer()

    private var whisper: WhisperKit?
    private var loadedFolder: URL?
    /// True while a load is running; others wait for it instead of loading a second copy.
    private var isLoading = false
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func load(folder: URL) async throws {
        if loadedFolder == folder, whisper != nil { return }
        if isLoading {
            try await withCheckedThrowingContinuation { waiters.append($0) }
            return
        }
        isLoading = true
        do {
            let config = WhisperKitConfig(modelFolder: folder.path(percentEncoded: false), verbose: false, logLevel: .error,
                                          prewarm: true, load: true, download: false)
            whisper = try await WhisperKit(config)
            loadedFolder = folder
            isLoading = false
            waiters.forEach { $0.resume() }
            waiters = []
        } catch {
            isLoading = false
            waiters.forEach { $0.resume(throwing: error) }
            waiters = []
            throw error
        }
    }

    func unload() {
        guard !isLoading else { return }   // don't drop a model that's still loading
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

/// Whether voice input can be used right now, and if not, why.
enum SpeechReadiness: Equatable {
    case preparing
    case ready
    case needsDownload
    case micDenied
    case failed(String)

    /// Checks the model and microphone, and loads speech recognition (fast if it's already loaded).
    @MainActor
    static func prepare() async -> SpeechReadiness {
        guard let folder = SpeechModelManager.shared.modelFolder else { return .needsDownload }
        guard await AudioRecorder.requestPermission() else { return .micDenied }
        do {
            try await SpeechRecognizer.shared.load(folder: folder)
            return .ready
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Loads speech recognition quietly after launch, so voice screens are ready straight away.
    @MainActor
    static func preloadInBackground() {
        guard let folder = SpeechModelManager.shared.modelFolder else { return }
        Task(priority: .utility) {
            try? await Task.sleep(for: .seconds(3))
            SpeechModelManager.shared.isWarmingUp = true
            defer { SpeechModelManager.shared.isWarmingUp = false }
            let start = Date()
            let status: String
            do {
                try await SpeechRecognizer.shared.load(folder: folder)
                status = "ready in \(String(format: "%.1f", Date().timeIntervalSince(start))) s at \(Date())"
            } catch {
                status = "failed after \(String(format: "%.1f", Date().timeIntervalSince(start))) s: \(error)"
            }
            // A small diagnostics file (Library/Caches/speech-status.txt) to check loading on a device.
            try? status.write(to: URL.cachesDirectory.appending(path: "speech-status.txt"), atomically: true, encoding: .utf8)
        }
    }
}
