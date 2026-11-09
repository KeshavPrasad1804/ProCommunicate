import Foundation

/// A downloadable on-device model.
struct AIModelInfo: Sendable, Hashable {
    let id: String
    let displayName: String
    let detail: String
    let fileName: String
    /// Pinned to an exact Hugging Face commit so the file can't change underneath us.
    let downloadURL: URL
    let sizeBytes: Int64
    /// SHA-256 of the file, checked after download.
    let sha256: String
}

enum AIModelCatalog {
    /// Gemma 4 E2B, 4-bit Q4_K_M: the model chosen in PLAN.md after the Tamil → English tests.
    /// SHA-256 matches the file tested on the Mac (bench/).
    static let tutor = AIModelInfo(
        id: "gemma-4-e2b-it-q4km",
        displayName: "Gemma 4 E2B",
        detail: "Google · 4-bit (Q4_K_M) · text only",
        fileName: "gemma-4-E2B-it-Q4_K_M.gguf",
        downloadURL: URL(string: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/0314792d7f1f7e229411f620751375812bb9faf2/gemma-4-E2B-it-Q4_K_M.gguf")!,
        sizeBytes: 3_106_738_272,
        sha256: "740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8"
    )
}

/// Where model files live: Application Support/Models, excluded from iCloud backup.
enum ModelStorage {
    static var directory: URL {
        let base = URL.applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func fileURL(for model: AIModelInfo) -> URL {
        directory.appending(path: model.fileName)
    }

    /// The finished download waits here until its checksum is verified.
    static func stagingURL(for model: AIModelInfo) -> URL {
        directory.appending(path: model.fileName + ".download")
    }

    static func resumeDataURL(for model: AIModelInfo) -> URL {
        directory.appending(path: model.fileName + ".resume")
    }

    static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
