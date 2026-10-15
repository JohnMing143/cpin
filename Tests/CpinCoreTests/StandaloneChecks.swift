#if STANDALONE_CHECKS
import Foundation

func XCTAssertTrue(_ value: @autoclosure () throws -> Bool) { let result = try! value(); precondition(result) }
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool) { let result = try! value(); precondition(!result) }
func XCTAssertEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T) { let a = try! left(); let b = try! right(); precondition(a == b) }
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?) { let result = try! value(); precondition(result == nil) }
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw CheckError.nilValue }; return value }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T) { do { _ = try value(); preconditionFailure("Expected error") } catch {} }
enum CheckError: Error { case nilValue }


final class ClipboardHistoryTests {
    private var directory: URL!
    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testPersistenceAndDuplicatePreservesIdentityAndPin() throws {
        let history = try ClipboardHistory(directory: directory)
        let original = try XCTUnwrap(history.addText("hello", sourceName: "One", at: Date(timeIntervalSince1970: 1)))
        try history.togglePin(original.id)
        try history.addText("second", sourceName: "One")
        let again = try XCTUnwrap(history.addText("hello", sourceName: "Two", sourceBundleIdentifier: "test.app", at: Date(timeIntervalSince1970: 3)))
        XCTAssertEqual(again.id, original.id)
        XCTAssertEqual(again.createdAt, original.createdAt)
        XCTAssertTrue(again.isPinned)
        XCTAssertEqual(again.sourceName, "Two")
        XCTAssertEqual(again.lastCopiedAt, Date(timeIntervalSince1970: 3))
        XCTAssertEqual(history.items.first, again)
        XCTAssertEqual(history.items.count, 2)
        XCTAssertEqual(try ClipboardHistory(directory: directory).items, history.items)
    }

    func testLimitExemptsPinsAndClearPreservesThem() throws {
        let history = try ClipboardHistory(directory: directory, limit: 1)
        let pinned = try XCTUnwrap(history.addText("pinned", sourceName: "Test"))
        try history.togglePin(pinned.id)
        try history.addText("old", sourceName: "Test")
        try history.addText("new", sourceName: "Test")
        XCTAssertEqual(history.items.map(\.text), ["new", "pinned"])
        try history.clearUnpinned()
        XCTAssertEqual(history.items.map(\.id), [pinned.id])
        try history.setLimit(0)
        try history.togglePin(pinned.id)
        XCTAssertEqual(history.items.count, 1)
        try history.clearAll()
        XCTAssertTrue(history.items.isEmpty)
    }

    func testImageDeduplicationAndDeletion() throws {
        let history = try ClipboardHistory(directory: directory)
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1cAAAAASUVORK5CYII=")!
        let first = try history.addImage(data, width: 1, height: 1, sourceName: "Test")
        let second = try history.addImage(data, width: 1, height: 1, sourceName: "Other")
        XCTAssertEqual(first.id, second.id)
        let url = try XCTUnwrap(history.imageURL(for: first))
        XCTAssertEqual(try Data(contentsOf: url), data)
        try history.remove(first.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testClassification() {
        XCTAssertEqual(ClipClassifier.classify("https://example.com/path?q=1"), .link)
        XCTAssertEqual(ClipClassifier.classify("https://example.com extra"), .text)
        XCTAssertEqual(ClipClassifier.classify("https://"), .text)
        XCTAssertEqual(ClipClassifier.classify("ftp://example.com"), .text)
        XCTAssertEqual(ClipClassifier.classify("func greet() {\n  print(\"hello\")\n}"), .code)
        XCTAssertEqual(ClipClassifier.classify("ordinary\nparagraph"), .text)
    }

    func testEvictionRemovesImageFile() throws {
        let history = try ClipboardHistory(directory: directory, limit: 1)
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1cAAAAASUVORK5CYII=")!
        let item = try history.addImage(data, width: 1, height: 1, sourceName: "Test")
        let url = try XCTUnwrap(history.imageURL(for: item))
        try history.addText("replacement", sourceName: "Test")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(history.items.count, 1)
    }

    func testBlankAndSizeLimits() throws {
        let history = try ClipboardHistory(directory: directory)
        XCTAssertNil(try history.addText(" \n\t", sourceName: "Test"))
        XCTAssertThrowsError(try history.addText(String(repeating: "a", count: 1_048_577), sourceName: "Test"))
        XCTAssertThrowsError(try history.addImage(Data(repeating: 0, count: 16_777_217), width: 1, height: 1, sourceName: "Test"))
        XCTAssertTrue(history.items.isEmpty)
    }

    func testCorruptManifestIsPreserved() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try ClipboardHistory(directory: directory))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testTraversalInManifestRejected() throws {
        let history = try ClipboardHistory(directory: directory)
        try history.addText("text", sourceName: "Test")
        let url = directory.appendingPathComponent("history.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        json[0]["kind"] = "image"
        json[0].removeValue(forKey: "text")
        json[0]["imageFileName"] = "../../outside.png"
        json[0]["pixelWidth"] = 1
        json[0]["pixelHeight"] = 1
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        XCTAssertThrowsError(try ClipboardHistory(directory: directory))
    }

    func testFailedWriteDoesNotChangeMemoryOrLimit() throws {
        let history = try ClipboardHistory(directory: directory)
        try history.addText("retained", sourceName: "Test")
        let before = history.items
        let manifest = directory.appendingPathComponent("history.json")
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        XCTAssertThrowsError(try history.addText("failed", sourceName: "Test"))
        XCTAssertThrowsError(try history.setLimit(0))
        XCTAssertEqual(history.items, before)
        XCTAssertEqual(history.limit, 100)
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1cAAAAASUVORK5CYII=")!
        XCTAssertThrowsError(try history.addImage(data, width: 1, height: 1, sourceName: "Test"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("images").path).isEmpty)
    }
    func testCustomUnlimitedAndInvalidLimits() throws {
        let history = try ClipboardHistory(directory: directory, limit: 0)
        for index in 0..<145 { try history.addText("item \(index)", sourceName: "Test") }
        XCTAssertEqual(history.items.count, 145)
        try history.setLimit(137)
        XCTAssertEqual(history.items.count, 137)
        XCTAssertEqual(history.limit, 137)
        let before = history.items
        XCTAssertThrowsError(try history.setLimit(-1))
        XCTAssertEqual(history.limit, 137)
        XCTAssertEqual(history.items, before)
        XCTAssertThrowsError(try ClipboardHistory(directory: directory, limit: -1))
        try history.setLimit(0)
        for index in 145..<150 { try history.addText("item \(index)", sourceName: "Test") }
        XCTAssertEqual(history.items.count, 142)
    }

    func testStorageUsageAndClearAll() throws {
        let history = try ClipboardHistory(directory: directory)
        XCTAssertEqual(history.storageBytes, 0)
        let text = try XCTUnwrap(history.addText("pinned", sourceName: "Test"))
        try history.togglePin(text.id)
        let baseline = history.storageBytes
        XCTAssertTrue(baseline > 0)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10]) + Data(repeating: 7, count: 65_536)
        let item = try history.addImage(png, width: 1, height: 1, sourceName: "Test")
        XCTAssertTrue(history.storageBytes > baseline)
        let withImage = history.storageBytes
        try history.remove(item.id)
        XCTAssertTrue(history.storageBytes < withImage)
        let images = directory.appendingPathComponent("images")
        let orphan = images.appendingPathComponent("\(UUID().uuidString).png")
        let unknown = images.appendingPathComponent("user-notes.png")
        let symlink = images.appendingPathComponent("\(UUID().uuidString).png")
        try png.write(to: orphan)
        try png.write(to: unknown)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: unknown)
        try history.refreshStorageUsage()
        let withOrphan = history.storageBytes
        XCTAssertTrue(withOrphan > baseline)
        try history.clearAll()
        XCTAssertTrue(history.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path), unknown.path)
        XCTAssertTrue(history.storageBytes < withOrphan)
        XCTAssertEqual(try ClipboardHistory(directory: directory).items, [])
        let after = history.storageBytes
        try history.clearAll()
        XCTAssertEqual(history.storageBytes, after)
    }

    func testRefreshFailurePreservesUsage() throws {
        let history = try ClipboardHistory(directory: directory)
        try history.addText("keep", sourceName: "Test")
        let before = history.storageBytes
        let images = directory.appendingPathComponent("images")
        try FileManager.default.removeItem(at: images)
        try Data("not a directory".utf8).write(to: images)
        XCTAssertThrowsError(try history.refreshStorageUsage())
        XCTAssertEqual(history.storageBytes, before)
        XCTAssertThrowsError(try history.clearAll())
        XCTAssertEqual(history.items.count, 1)
    }

    func testCleanupFailureIsReportedAndRetryable() throws {
        let history = try ClipboardHistory(directory: directory)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10]) + Data(repeating: 9, count: 65_536)
        let image = try history.addImage(png, width: 1, height: 1, sourceName: "Test")
        let url = try XCTUnwrap(history.imageURL(for: image))
        let images = directory.appendingPathComponent("images")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: images.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: images.path) }
        XCTAssertThrowsError(try history.clearAll())
        XCTAssertTrue(history.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let remaining = history.storageBytes
        XCTAssertTrue(remaining > 0)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: images.path)
        try history.clearAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(history.storageBytes < remaining)
    }

}

@main struct StandaloneChecks {
    static func main() throws {
        let suite = ClipboardHistoryTests()
        let checks: [(String, () throws -> Void)] = [
            ("persistence and duplicate identity", suite.testPersistenceAndDuplicatePreservesIdentityAndPin),
            ("limits and pins", suite.testLimitExemptsPinsAndClearPreservesThem),
            ("image deduplication and removal", suite.testImageDeduplicationAndDeletion),
            ("classification", suite.testClassification),
            ("image eviction", suite.testEvictionRemovesImageFile),
            ("blank and oversized input", suite.testBlankAndSizeLimits),
            ("corrupt manifest preservation", suite.testCorruptManifestIsPreserved),
            ("unsafe image path rejection", suite.testTraversalInManifestRejected),
            ("write rollback", suite.testFailedWriteDoesNotChangeMemoryOrLimit),
            ("custom, unlimited and invalid limits", suite.testCustomUnlimitedAndInvalidLimits),
            ("storage usage and full cleanup", suite.testStorageUsageAndClearAll),
            ("refresh failure preserves usage", suite.testRefreshFailurePreservesUsage),
            ("cleanup failure and retry", suite.testCleanupFailureIsReportedAndRetryable)
        ]
        for (name, check) in checks {
            try suite.setUpWithError()
            do { try check(); try suite.tearDownWithError() }
            catch { try? suite.tearDownWithError(); throw error }
            print("PASS: \(name)")
        }
        print("All \(checks.count) core checks passed.")
    }
}
#endif
