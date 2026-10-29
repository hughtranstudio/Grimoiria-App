import Foundation

/// The file operations ingest needs, so the logic can run against a fake in tests and
/// against FileManager (plus iCloud download requests) on the Mac.
public protocol IngestFileSystem: Sendable {
    func list(_ dir: URL) throws -> [String]
    func size(_ file: URL) -> Int?
    func read(_ file: URL) throws -> Data
    func write(_ data: Data, to file: URL) throws
    func move(_ from: URL, to: URL) throws
    func makeDirectory(_ dir: URL) throws
    func exists(_ file: URL) -> Bool
    /// Ask iCloud to download a placeholder. No-op off macOS.
    func requestDownload(_ file: URL)
}

public struct LocalFileSystem: IngestFileSystem {
    public init() {}
    public func list(_ dir: URL) throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() }
    public func size(_ file: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue
    }
    public func read(_ file: URL) throws -> Data { try Data(contentsOf: file) }
    public func write(_ data: Data, to file: URL) throws { try data.write(to: file, options: .atomic) }
    public func move(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
        try fm.moveItem(at: from, to: to)
    }
    public func makeDirectory(_ dir: URL) throws { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    public func exists(_ file: URL) -> Bool { FileManager.default.fileExists(atPath: file.path) }
    public func requestDownload(_ file: URL) {
        #if os(macOS) || os(iOS)
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        #endif
    }
}

/// Turns audio into text. On the Mac this wraps WhisperKit / whisper.cpp locally.
public protocol Transcriber: Sendable {
    func transcribe(_ audio: URL) async throws -> String
}

/// A transcriber that knows when each piece was said, for session recordings.
public protocol SegmentingTranscriber: Transcriber {
    func segments(_ audio: URL) async throws -> [TranscriptSegment]
}

public extension Transcriber {
    /// Timed segments when the transcriber has them; otherwise the text, with any "[mm:ss]" stamps read.
    func timedSegments(_ audio: URL) async throws -> [TranscriptSegment] {
        if let s = self as? SegmentingTranscriber { return try await s.segments(audio) }
        return TimedTranscript.parse(try await transcribe(audio))
    }
}

/// For tests and the Linux CLI: reads `<audio basename>.txt` beside the audio if present.
public struct SidecarTextTranscriber: Transcriber {
    public init() {}
    public func transcribe(_ audio: URL) async throws -> String {
        let txt = audio.deletingPathExtension().appendingPathExtension("txt")
        guard let data = try? Data(contentsOf: txt), let s = String(data: data, encoding: .utf8) else {
            throw IngestError.transcription("no transcriber configured and no \(txt.lastPathComponent) beside the audio")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
