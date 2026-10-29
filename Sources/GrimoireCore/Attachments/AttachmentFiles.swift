import Foundation

/// Files kept beside the records: photos of notebook pages, audio, imported originals.
/// They live in the app's attachments folder; records store a path relative to it.
public enum AttachmentFiles {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp"]
    static let audioExtensions: Set<String> = ["m4a", "wav", "mp3", "aac", "ogg", "opus", "caf", "aiff"]

    public static func kind(for url: URL) -> Attachment.Kind {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if audioExtensions.contains(ext) { return .audio }
        return .document
    }

    public static func isImage(_ url: URL) -> Bool { kind(for: url) == .image }

    /// Copies `source` into `folder` under photos/, audio/ or files/, named by content so adding
    /// the same file twice reuses one copy. Returns the attachment to store on a record.
    public static func store(_ source: URL, in folder: URL, fs: IngestFileSystem = LocalFileSystem()) throws -> Attachment {
        let data = try fs.read(source)
        let kind = kind(for: source)
        let sub = switch kind { case .image: "photos"; case .audio: "audio"; case .document: "files" }
        let name = source.lastPathComponent
        let rel = "\(sub)/\(DocumentImporter.fnv1a(data).prefix(8))-\(name)"
        let dest = folder.appendingPathComponent(rel)
        if !fs.exists(dest) {
            try fs.makeDirectory(dest.deletingLastPathComponent())
            try fs.write(data, to: dest)
        }
        return Attachment(kind: kind, path: rel, originalName: name)
    }
}
