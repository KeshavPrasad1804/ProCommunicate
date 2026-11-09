import Foundation
import Observation

enum AIModelState: Equatable, Sendable {
    case notDownloaded
    case downloading(received: Int64, total: Int64)
    case paused(received: Int64, total: Int64)
    case verifying
    case ready
    case failed(message: String)

    /// 0…1 while downloading or paused, otherwise nil.
    var fraction: Double? {
        switch self {
        case .downloading(let received, let total), .paused(let received, let total):
            total > 0 ? min(1, Double(received) / Double(total)) : 0
        default:
            nil
        }
    }

    var isBusy: Bool {
        switch self {
        case .downloading, .verifying: true
        default: false
        }
    }
}

/// Downloads, verifies, stores and deletes the on-device AI model.
/// Uses a background URLSession, so the 3 GB download continues if you leave the app.
@MainActor @Observable
final class AIModelManager {
    static let shared = AIModelManager()

    let model: AIModelInfo
    private(set) var state: AIModelState = .notDownloaded

    /// Off by default: a 3 GB download should wait for Wi-Fi unless you say otherwise.
    var useMobileData: Bool {
        didSet { UserDefaults.standard.set(useMobileData, forKey: Keys.useMobileData) }
    }

    /// Set by the app delegate when iOS wakes the app to finish a background download.
    @ObservationIgnored var backgroundEventsCompletion: (() -> Void)?

    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var task: URLSessionDownloadTask?
    /// True while we are pausing or cancelling, so the resulting "cancelled" error isn't shown as a failure.
    @ObservationIgnored private var stoppingOnPurpose = false

    private enum Keys {
        static let useMobileData = "aiModelUseMobileData"
        static let pausedBytes = "aiModelPausedBytes"
        static func verified(_ id: String) -> String { "aiModelVerified.\(id)" }
    }

    init(model: AIModelInfo = AIModelCatalog.tutor) {
        self.model = model
        self.useMobileData = UserDefaults.standard.bool(forKey: Keys.useMobileData)

        let config = URLSessionConfiguration.background(withIdentifier: "dev.procommunicate.model-download.\(model.id)")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        let delegate = ModelDownloadDelegate(stagingURL: ModelStorage.stagingURL(for: model)) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        restoreState()
    }

    var isReady: Bool { state == .ready }
    var modelFileURL: URL { ModelStorage.fileURL(for: model) }
    var hasResumeData: Bool { FileManager.default.fileExists(atPath: ModelStorage.resumeDataURL(for: model).path) }

    // MARK: Actions

    func startDownload() {
        guard !state.isBusy, state != .ready else { return }
        if hasResumeData {
            resumeDownload()
            return
        }
        if let available = DeviceCapability.availableStorageBytes(),
           !DeviceCapability.hasRoom(forDownloadOf: model.sizeBytes, available: available) {
            let needed = model.sizeBytes + DeviceCapability.storageMarginBytes
            state = .failed(message: "Not enough storage. You need about \(needed.formattedBytes) free; you have \(available.formattedBytes).")
            return
        }
        var request = URLRequest(url: model.downloadURL)
        request.allowsCellularAccess = useMobileData
        guard let task = session?.downloadTask(with: request) else { return }
        task.countOfBytesClientExpectsToReceive = model.sizeBytes
        self.task = task
        stoppingOnPurpose = false
        state = .downloading(received: 0, total: model.sizeBytes)
        task.resume()
    }

    func pauseDownload() {
        guard let task, case .downloading(let received, let total) = state else { return }
        stoppingOnPurpose = true
        self.task = nil
        state = .paused(received: received, total: total)
        UserDefaults.standard.set(received, forKey: Keys.pausedBytes)
        Task {
            let data = await task.cancelByProducingResumeData()
            if let data { try? data.write(to: ModelStorage.resumeDataURL(for: model)) }
            stoppingOnPurpose = false
        }
    }

    func resumeDownload() {
        let resumeURL = ModelStorage.resumeDataURL(for: model)
        guard let data = try? Data(contentsOf: resumeURL), let task = session?.downloadTask(withResumeData: data) else {
            try? FileManager.default.removeItem(at: resumeURL)
            state = .notDownloaded
            startDownload()
            return
        }
        try? FileManager.default.removeItem(at: resumeURL)
        self.task = task
        stoppingOnPurpose = false
        let received = Int64(UserDefaults.standard.integer(forKey: Keys.pausedBytes))
        state = .downloading(received: received, total: model.sizeBytes)
        task.resume()
    }

    func cancelDownload() {
        stoppingOnPurpose = true
        task?.cancel()
        task = nil
        removePartialFiles()
        state = .notDownloaded
    }

    func deleteModel() {
        cancelDownload()
        try? FileManager.default.removeItem(at: modelFileURL)
        UserDefaults.standard.removeObject(forKey: Keys.verified(model.id))
        state = .notDownloaded
    }

    // MARK: Events

    private func handle(_ event: ModelDownloadDelegate.Event) {
        switch event {
        case .progress(let received, let total):
            guard !stoppingOnPurpose, state != .verifying else { return }
            state = .downloading(received: received, total: total > 0 ? total : model.sizeBytes)
        case .finished(let staged):
            task = nil
            Task { await verify(staged: staged) }
        case .failed(let message, let resumeData):
            task = nil
            guard !stoppingOnPurpose else { return }
            if let resumeData {
                try? resumeData.write(to: ModelStorage.resumeDataURL(for: model))
                if case .downloading(let received, _) = state {
                    UserDefaults.standard.set(received, forKey: Keys.pausedBytes)
                }
            }
            state = .failed(message: "The download stopped: \(message)")
        case .allBackgroundEventsFinished:
            backgroundEventsCompletion?()
            backgroundEventsCompletion = nil
        }
    }

    private func verify(staged: URL) async {
        state = .verifying
        let expected = model.sha256
        let hash = await Task.detached(priority: .utility) {
            try? FileHasher.sha256Hex(of: staged)
        }.value
        guard hash == expected else {
            try? FileManager.default.removeItem(at: staged)
            state = .failed(message: "The download was damaged. Please download it again.")
            return
        }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: modelFileURL.path) { try fm.removeItem(at: modelFileURL) }
            try fm.moveItem(at: staged, to: modelFileURL)
            try ModelStorage.excludeFromBackup(modelFileURL)
            UserDefaults.standard.set(expected, forKey: Keys.verified(model.id))
            UserDefaults.standard.removeObject(forKey: Keys.pausedBytes)
            state = .ready
        } catch {
            state = .failed(message: "Couldn't store the model: \(error.localizedDescription)")
        }
    }

    // MARK: Restore after launch

    private func restoreState() {
        let fm = FileManager.default
        if fm.fileExists(atPath: modelFileURL.path),
           UserDefaults.standard.string(forKey: Keys.verified(model.id)) == model.sha256 {
            state = .ready
            return
        }
        let staged = ModelStorage.stagingURL(for: model)
        if fm.fileExists(atPath: staged.path) {
            Task { await verify(staged: staged) }
            return
        }
        if hasResumeData {
            let received = Int64(UserDefaults.standard.integer(forKey: Keys.pausedBytes))
            state = .paused(received: received, total: model.sizeBytes)
        }
        // A download may still be running in the background from an earlier launch.
        Task {
            guard let tasks = await session?.allTasks else { return }
            if let running = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(where: { $0.state == .running }) {
                task = running
                let received = running.countOfBytesReceived
                state = .downloading(received: received, total: model.sizeBytes)
            }
        }
    }

    private func removePartialFiles() {
        try? FileManager.default.removeItem(at: ModelStorage.resumeDataURL(for: model))
        try? FileManager.default.removeItem(at: ModelStorage.stagingURL(for: model))
        UserDefaults.standard.removeObject(forKey: Keys.pausedBytes)
    }
}
