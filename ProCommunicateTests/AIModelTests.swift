import Foundation
import Testing
@testable import ProCommunicate

@Suite("AI model download")
struct AIModelTests {
    let model = AIModelCatalog.tutor

    @Test func downloadIsPinnedToAnExactCommitOverHTTPS() {
        #expect(model.downloadURL.scheme == "https")
        #expect(model.downloadURL.host() == "huggingface.co")
        #expect(model.downloadURL.path().contains("/resolve/0314792d7f1f7e229411f620751375812bb9faf2/"))
        #expect(model.downloadURL.lastPathComponent == model.fileName)
    }

    @Test func checksumAndSizeMatchTheTestedFile() {
        #expect(model.sha256.count == 64)
        #expect(model.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(model.sizeBytes == 3_106_738_272)
    }

    @Test(arguments: [
        (UInt64(5_900_000_000), true),   // 6 GB iPhone (e.g. iPhone 15)
        (UInt64(7_900_000_000), true),   // 8 GB iPhone
        (UInt64(3_900_000_000), false),  // 4 GB iPhone
    ])
    func aiTutorNeedsSixGigabytePhones(memory: UInt64, supported: Bool) {
        #expect(DeviceCapability.supportsAITutor(physicalMemory: memory) == supported)
    }

    @Test func needsRoomForModelPlusMargin() {
        let size = model.sizeBytes
        #expect(DeviceCapability.hasRoom(forDownloadOf: size, available: size + DeviceCapability.storageMarginBytes))
        #expect(!DeviceCapability.hasRoom(forDownloadOf: size, available: size + DeviceCapability.storageMarginBytes - 1))
        #expect(DeviceCapability.hasRoom(forDownloadOf: size, available: 15_700_000_000)) // your iPhone today
    }

    @Test func sha256OfAKnownFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "hash-test-\(UUID().uuidString).txt")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(try FileHasher.sha256Hex(of: url) == expected)
        // Same result when read one byte at a time, as with a large file read in chunks.
        #expect(try FileHasher.sha256Hex(of: url, chunkSize: 1) == expected)
    }

    @Test func progressFraction() {
        #expect(AIModelState.downloading(received: 0, total: 100).fraction == 0)
        #expect(AIModelState.downloading(received: 50, total: 100).fraction == 0.5)
        #expect(AIModelState.paused(received: 100, total: 100).fraction == 1)
        #expect(AIModelState.downloading(received: 10, total: 0).fraction == 0)
        #expect(AIModelState.ready.fraction == nil)
    }

    @Test func modelFilesLiveInApplicationSupport() {
        let file = ModelStorage.fileURL(for: model)
        #expect(file.path(percentEncoded: false).contains("Application Support/Models/"))
        #expect(ModelStorage.stagingURL(for: model) != file)
        #expect(ModelStorage.resumeDataURL(for: model) != file)
    }
}
