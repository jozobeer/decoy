import Foundation
import Domain

/// `ClipStore` backed by the local filesystem.
///
/// ## On-disk layout
///
/// ```text
/// <rootURL>/
///   <clip-uuid>/
///     metadata.json     ← Codable header: id, recordedAt, duration, frame timings
///     frames/
///       000.bin         ← raw Frame.data, zero-padded index
///       001.bin
///       ...
///   .staging/           ← write-temp-then-rename area (auto-managed)
///     <clip-uuid>/      ← in-flight clip being staged
/// ```
///
/// Each clip is a self-contained directory. `metadata.json` holds the clip's
/// scalar fields plus an array of `presentationTime` values; the i-th entry
/// corresponds to `frames/<i>.bin` on disk. Splitting frames into their own
/// files lets the bytes round-trip bit-exact without base64 inflation and
/// keeps `metadata.json` cheap to scan.
///
/// ## Atomicity
///
/// Saves are staged under `<rootURL>/.staging/<uuid>/` and atomically swapped
/// into `<rootURL>/<uuid>/` via `FileManager.replaceItem`. Readers therefore
/// observe either the previous clip directory or the new one — never a half-
/// written hybrid. Deletes simply `removeItem` the target directory.
///
/// ## Concurrency
///
/// `FileSystemClipStore` is an `actor`, so concurrent `save` / `delete` calls
/// from different tasks are serialized by Swift's actor isolation.
public actor FileSystemClipStore {
    private let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }
}

// MARK: - ClipStore conformance

extension FileSystemClipStore: ClipStore {
    public func save(_ clip: Clip) async throws {
        try ensureRootExists()
        let stagingRoot = rootURL.appendingPathComponent(".staging", isDirectory: true)
        try ensureDirectoryExists(at: stagingRoot)
        let stagingDir = stagingRoot.appendingPathComponent(clip.id.uuidString, isDirectory: true)
        try removeIfExists(at: stagingDir)
        try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        do {
            try writeClip(clip, into: stagingDir)
            try swapIntoFinalLocation(from: stagingDir, for: clip.id)
        } catch {
            try? fileManager.removeItem(at: stagingDir)
            throw error
        }
    }

    public func all() async throws -> [Clip] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        return try clipDirectories()
            .compactMap(decodedClip(from:))
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    public func clip(id: UUID) async throws -> Clip? {
        let dir = clipDirectory(for: id)
        guard fileManager.fileExists(atPath: dir.path) else { return nil }
        return try decodedClip(from: dir)
    }

    public func delete(id: UUID) async throws {
        let dir = clipDirectory(for: id)
        try removeIfExists(at: dir)
    }
}

// MARK: - Persistence layout

extension FileSystemClipStore {
    private func clipDirectory(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func clipDirectories() throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter(isClipDirectory)
    }

    private func isClipDirectory(_ url: URL) -> Bool {
        guard UUID(uuidString: url.lastPathComponent) != nil else { return false }
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}

// MARK: - Encode

extension FileSystemClipStore {
    private func writeClip(_ clip: Clip, into stagingDir: URL) throws {
        let framesDir = stagingDir.appendingPathComponent("frames", isDirectory: true)
        try fileManager.createDirectory(at: framesDir, withIntermediateDirectories: true)
        try clip.frames.enumerated().forEach { index, frame in
            let file = framesDir.appendingPathComponent(frameFilename(at: index))
            try frame.data.write(to: file, options: .atomic)
        }
        let metadata = ClipMetadata(
            id: clip.id,
            recordedAt: clip.recordedAt,
            duration: clip.duration,
            frames: clip.frames.map { FrameMetadata(presentationTime: $0.presentationTime) }
        )
        let json = try Self.encoder.encode(metadata)
        try json.write(to: stagingDir.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private func swapIntoFinalLocation(from stagingDir: URL, for id: UUID) throws {
        let finalDir = clipDirectory(for: id)
        guard fileManager.fileExists(atPath: finalDir.path) else {
            try fileManager.moveItem(at: stagingDir, to: finalDir)
            return
        }
        // `replaceItem` performs an atomic swap on macOS APFS.
        _ = try fileManager.replaceItemAt(finalDir, withItemAt: stagingDir)
    }
}

// MARK: - Decode

extension FileSystemClipStore {
    private func decodedClip(from clipDir: URL) throws -> Clip? {
        let metadataURL = clipDir.appendingPathComponent("metadata.json")
        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }
        let metadata = try Self.decoder.decode(ClipMetadata.self, from: Data(contentsOf: metadataURL))
        let framesDir = clipDir.appendingPathComponent("frames", isDirectory: true)
        let frames = try metadata.frames.enumerated().map { index, frameMeta in
            let bytes = try Data(contentsOf: framesDir.appendingPathComponent(frameFilename(at: index)))
            return Frame(presentationTime: frameMeta.presentationTime, data: bytes)
        }
        return Clip(
            id: metadata.id,
            recordedAt: metadata.recordedAt,
            frames: frames,
            duration: metadata.duration
        )
    }
}

// MARK: - Filesystem helpers

extension FileSystemClipStore {
    private func ensureRootExists() throws {
        try ensureDirectoryExists(at: rootURL)
    }

    private func ensureDirectoryExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) == false else { return }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func removeIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

// MARK: - Codable header

extension FileSystemClipStore {
    private struct ClipMetadata: Codable, Sendable {
        let id: UUID
        let recordedAt: Date
        let duration: TimeInterval
        let frames: [FrameMetadata]
    }

    private struct FrameMetadata: Codable, Sendable {
        let presentationTime: TimeInterval
    }

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()
}

// MARK: - Naming

private func frameFilename(at index: Int) -> String {
    String(format: "%06d.bin", index)
}
