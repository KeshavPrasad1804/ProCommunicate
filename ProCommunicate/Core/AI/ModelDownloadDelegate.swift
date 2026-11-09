import Foundation
import os

/// Receives URLSession background-download callbacks and forwards them as simple events.
/// Holds no mutable state except a lock-protected timestamp used to throttle progress updates.
final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    enum Event: Sendable {
        case progress(received: Int64, total: Int64)
        case finished(staged: URL)
        case failed(message: String, resumeData: Data?)
        case allBackgroundEventsFinished
    }

    private let stagingURL: URL
    private let onEvent: @Sendable (Event) -> Void
    private let lastProgress = OSAllocatedUnfairLock(initialState: Date.distantPast)

    init(stagingURL: URL, onEvent: @escaping @Sendable (Event) -> Void) {
        self.stagingURL = stagingURL
        self.onEvent = onEvent
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let now = Date()
        let report = lastProgress.withLock { last -> Bool in
            guard now.timeIntervalSince(last) >= 0.25 else { return false }
            last = now
            return true
        }
        if report {
            onEvent(.progress(received: totalBytesWritten, total: totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            onEvent(.failed(message: "The server answered with error \(http.statusCode).", resumeData: nil))
            return
        }
        // The system deletes `location` when this method returns, so move it now.
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: stagingURL.path) { try fm.removeItem(at: stagingURL) }
            try fm.moveItem(at: location, to: stagingURL)
            onEvent(.finished(staged: stagingURL))
        } catch {
            onEvent(.failed(message: "Couldn't save the download: \(error.localizedDescription)", resumeData: nil))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        onEvent(.failed(message: error.localizedDescription, resumeData: resumeData))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        onEvent(.allBackgroundEventsFinished)
    }
}
