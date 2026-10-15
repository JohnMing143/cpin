import Foundation
import Combine
import CryptoKit

public enum ClipKind: String, Codable { case text, link, code, image }

public struct ClipItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let kind: ClipKind
    public let text: String?
    public let imageFileName: String?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let createdAt: Date
    public let fingerprint: String
    public var sourceName: String
    public var sourceBundleIdentifier: String?
    public var lastCopiedAt: Date
    public var isPinned: Bool
}

public enum ClipClassifier {
    public static func classify(_ text: String) -> ClipKind {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains(where: { $0.isWhitespace }),
           let url = URLComponents(string: value),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           let host = url.host, !host.isEmpty { return .link }
        if value.contains("\n") {
            let markers = ["func ", "function ", "const ", "let ", "var ", "import ", "def ", "class ", "return ", "#include", "SELECT ", "<!DOCTYPE", "<html", "#!/", "```"]
            if markers.contains(where: value.contains) || (value.contains("{") && value.contains("}")) {
                return .code
            }
        }
        return .text
    }
}

public enum ClipboardHistoryError: Error, LocalizedError {
    case textTooLarge, imageTooLarge, invalidImage, invalidManifest, invalidLimit, unsafeStorage
    public var errorDescription: String? {
        switch self {
        case .invalidLimit: return "历史上限不能为负数。"
        case .unsafeStorage: return "存储路径包含不安全的符号链接或非普通文件。"
        case .textTooLarge: return "文本超过 1 MiB 上限。"
        case .imageTooLarge: return "图片超过 16 MiB 上限。"
        case .invalidImage: return "图片格式或尺寸无效。"
        case .invalidManifest: return "历史文件已损坏，原文件已保留。"
        }
    }
}

public final class ClipboardHistory: ObservableObject {
    @Published public private(set) var items: [ClipItem]
    @Published public private(set) var storageBytes: Int64 = 0
    public private(set) var limit: Int
    public let directory: URL
    private var manifestURL: URL { directory.appendingPathComponent("history.json") }
    private var imagesURL: URL { directory.appendingPathComponent("images", isDirectory: true) }

    public init(directory: URL, limit: Int = 100) throws {
        guard limit >= 0 else { throw ClipboardHistoryError.invalidLimit }
        self.directory = directory
        self.limit = limit
        self.items = []
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try validateStorageDirectory(directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try validateRegularFile(manifestURL)
            let loaded = try JSONDecoder().decode([ClipItem].self, from: Data(contentsOf: manifestURL))
            guard Set(loaded.map(\.id)).count == loaded.count,
                  Set(loaded.map(\.fingerprint)).count == loaded.count,
                  loaded.allSatisfy(Self.isValid) else { throw ClipboardHistoryError.invalidManifest }
            items = loaded
        }
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        try validateStorageDirectory(imagesURL)
        let trimmed = bounded(items, limit: self.limit)
        if trimmed != items { try commit(trimmed) }
        try refreshStorageUsage()
    }

    @discardableResult
    public func addText(_ text: String, sourceName: String, sourceBundleIdentifier: String? = nil, at: Date = Date()) throws -> ClipItem? {
        guard text.utf8.count <= 1_048_576 else { throw ClipboardHistoryError.textTooLarge }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try add(kind: ClipClassifier.classify(text), text: text, imageData: nil, width: nil, height: nil,
                       sourceName: sourceName, bundle: sourceBundleIdentifier, at: at,
                       fingerprint: Self.digest(Data(text.utf8), prefix: "text:"))
    }

    @discardableResult
    public func addImage(_ data: Data, width: Int, height: Int, sourceName: String, sourceBundleIdentifier: String? = nil, at: Date = Date()) throws -> ClipItem {
        guard data.count <= 16_777_216 else { throw ClipboardHistoryError.imageTooLarge }
        guard width > 0, height > 0, data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw ClipboardHistoryError.invalidImage }
        return try add(kind: .image, text: nil, imageData: data, width: width, height: height,
                       sourceName: sourceName, bundle: sourceBundleIdentifier, at: at,
                       fingerprint: Self.digest(data, prefix: "image:"))
    }

    public func togglePin(_ id: UUID) throws {
        var next = items
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].isPinned.toggle()
        try commit(bounded(next, limit: limit))
    }

    public func remove(_ id: UUID) throws { try commit(items.filter { $0.id != id }) }
    public func clearUnpinned() throws { try commit(items.filter(\.isPinned)) }
    public func clearAll() throws { try commit([], clearOrphans: true) }

    public func refreshStorageUsage() throws { storageBytes = try measuredStorageUsage() }

    public func setLimit(_ limit: Int) throws {
        guard limit >= 0 else { throw ClipboardHistoryError.invalidLimit }
        let value = limit
        try commit(bounded(items, limit: value))
        self.limit = value
    }

    public func imageURL(for item: ClipItem) -> URL? {
        guard let name = item.imageFileName, Self.safeFileName(name) else { return nil }
        return imagesURL.appendingPathComponent(name)
    }

    private func add(kind: ClipKind, text: String?, imageData: Data?, width: Int?, height: Int?, sourceName: String, bundle: String?, at: Date, fingerprint: String) throws -> ClipItem {
        var next = items
        let existing = next.firstIndex { $0.fingerprint == fingerprint }
        var item: ClipItem
        if let existing {
            item = next.remove(at: existing)
            item.sourceName = sourceName
            item.sourceBundleIdentifier = bundle
            item.lastCopiedAt = at
        } else {
            let id = UUID()
            item = ClipItem(id: id, kind: kind, text: text, imageFileName: imageData == nil ? nil : "\(id.uuidString).png",
                            pixelWidth: width, pixelHeight: height, createdAt: at, fingerprint: fingerprint,
                            sourceName: sourceName, sourceBundleIdentifier: bundle, lastCopiedAt: at, isPinned: false)
        }
        next.insert(item, at: 0)
        next = bounded(next, limit: limit)
        var writtenURL: URL?
        if existing == nil, let imageData, let url = imageURL(for: item), next.contains(where: { $0.id == item.id }) {
            try validateStorageDirectory(directory)
            try validateStorageDirectory(imagesURL)
            try imageData.write(to: url, options: .atomic)
            writtenURL = url
        }
        do { try commit(next) }
        catch {
            if let writtenURL, !items.contains(where: { $0.id == item.id }) { try? FileManager.default.removeItem(at: writtenURL) }
            throw error
        }
        return item
    }

    private func bounded(_ values: [ClipItem], limit: Int) -> [ClipItem] {
        if limit == 0 { return values }
        var count = 0
        return values.filter { item in
            if item.isPinned { return true }
            count += 1
            return count <= limit
        }
    }

    // The manifest is the commit point. Cleanup errors are reported after publishing the
    // committed list and remaining disk usage; clearAll can safely retry orphan cleanup.
    private func commit(_ next: [ClipItem], clearOrphans: Bool = false) throws {
        try validateStorageDirectory(directory)
        let managed = try managedImageFiles()
        if FileManager.default.fileExists(atPath: manifestURL.path) { try validateRegularFile(manifestURL) }
        let retained = Set(next.compactMap(\.imageFileName))
        let previous = Set(items.compactMap(\.imageFileName))
        let removed = managed.filter { !retained.contains($0.lastPathComponent) && (clearOrphans || previous.contains($0.lastPathComponent)) }
        let data = try JSONEncoder().encode(next)
        try data.write(to: manifestURL, options: .atomic)
        var cleanupError: Error?
        for url in removed {
            do { try FileManager.default.removeItem(at: url) }
            catch { if cleanupError == nil { cleanupError = error } }
        }
        var usage: Int64?
        do { usage = try measuredStorageUsage() }
        catch { if cleanupError == nil { cleanupError = error } }
        items = next
        if let usage { storageBytes = usage }
        if let cleanupError { throw cleanupError }
    }

    private func validateStorageDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else { throw ClipboardHistoryError.unsafeStorage }
    }

    private func validateRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw ClipboardHistoryError.unsafeStorage }
    }

    private func managedImageFiles() throws -> [URL] {
        try validateStorageDirectory(directory)
        try validateStorageDirectory(imagesURL)
        return try FileManager.default.contentsOfDirectory(at: imagesURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]).filter { url in
                guard Self.safeFileName(url.lastPathComponent) else { return false }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values.isRegularFile == true && values.isSymbolicLink != true
            }
    }

    private func measuredStorageUsage() throws -> Int64 {
        var files = try managedImageFiles()
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try validateRegularFile(manifestURL)
            files.append(manifestURL)
        }
        return try files.reduce(Int64(0)) { total, url in
            let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
            return total + Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
    }

    private static func safeFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".png") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }

    private static func isValid(_ item: ClipItem) -> Bool {
        if item.kind == .image {
            return item.text == nil && item.imageFileName.map(safeFileName) == true
                && (item.pixelWidth ?? 0) > 0 && (item.pixelHeight ?? 0) > 0
        }
        return item.imageFileName == nil && item.text.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 1_048_576 } == true
    }

    private static func digest(_ data: Data, prefix: String) -> String {
        prefix + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
