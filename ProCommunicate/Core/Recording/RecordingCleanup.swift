import Foundation
import SwiftData

/// Keeps your recordings from filling the phone: call and drill audio older than a set number of days
/// is deleted, except recordings you starred and the clip saved with each mistake (so you can still
/// hear how you said it). Transcripts, reports and numbers are always kept.
enum RecordingCleanup {
    /// Days to keep call audio; 0 keeps it forever.
    static let keepDaysKey = "storage.keepAudioDays"
    static let defaultKeepDays = 60

    static var keepDays: Int {
        UserDefaults.standard.object(forKey: keepDaysKey) == nil ? defaultKeepDays : UserDefaults.standard.integer(forKey: keepDaysKey)
    }

    struct Result: Equatable {
        var files = 0
        var bytes: Int64 = 0
    }

    /// Deletes audio older than `keepDays` that isn't protected. Returns what was freed.
    @MainActor @discardableResult
    static func run(in context: ModelContext, keepDays: Int = RecordingCleanup.keepDays,
                    directory: URL = RecordingStorage.directory, now: Date = .now) -> Result {
        guard keepDays > 0 else { return Result() }
        let recordings = (try? context.fetch(FetchDescriptor<Recording>())) ?? []
        let mistakes = (try? context.fetch(FetchDescriptor<MistakeRecord>())) ?? []
        var protected = Set(recordings.filter(\.starred).map(\.fileName))
        protected.formUnion(mistakes.compactMap(\.lastClipFile))

        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        var result = Result()
        for file in files where !protected.contains(file.lastPathComponent) {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  let date = values.creationDate ?? values.contentModificationDate, date < cutoff else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil {
                result.files += 1
                result.bytes += Int64(values.fileSize ?? 0)
            }
        }
        // Forget saved recordings whose audio is gone (not starred ones).
        for recording in recordings where !recording.starred && !FileManager.default.fileExists(atPath: directory.appending(path: recording.fileName).path) {
            context.delete(recording)
        }
        try? context.save()
        return result
    }

    /// Total size of the files in a folder (or one file).
    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        var total: Int64 = 0
        let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
        while let file = enumerator?.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}
