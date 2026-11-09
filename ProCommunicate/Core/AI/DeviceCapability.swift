import CryptoKit
import Foundation

/// Checks whether this iPhone can run the AI tutor and has room for the model.
enum DeviceCapability {
    /// 6 GB phones (such as the iPhone 15) report a little under 6 GB; 4 GB phones are too small.
    static let minimumMemoryBytes: UInt64 = 5_000_000_000
    /// Extra free space to keep after the download, so the phone doesn't run out.
    static let storageMarginBytes: Int64 = 1_000_000_000

    static func supportsAITutor(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Bool {
        physicalMemory >= minimumMemoryBytes
    }

    static func availableStorageBytes() -> Int64? {
        let values = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func hasRoom(forDownloadOf bytes: Int64, available: Int64) -> Bool {
        available >= bytes + storageMarginBytes
    }
}

enum FileHasher {
    /// SHA-256 of a file, read in chunks so a 3 GB model doesn't need 3 GB of memory.
    static func sha256Hex(of url: URL, chunkSize: Int = 8 * 1024 * 1024) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: chunkSize) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension Int64 {
    /// "3.11 GB", "512 MB"…
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
