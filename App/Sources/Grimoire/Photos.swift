import AppKit
import GrimoireAppKit
import GrimoireCore
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    /// Copies a file into Attachments (once per content) and returns the attachment for a record.
    func storeAttachment(_ url: URL) -> Attachment? {
        do {
            return try AttachmentFiles.store(url, in: Store.attachments)
        } catch {
            show("Couldn’t add \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Photos of notebook pages become photo-first records in a volume, one per photo, pages counted on.
    @discardableResult
    func indexPages(volumeId: ULID, photos: [URL], firstPage: String, pagesPerPhoto: Int = 1,
                    writtenOn: Date? = nil, tags: [TagPath] = []) throws -> [Entry] {
        flushEdits()
        guard let volume = volume(volumeId) else { return [] }
        let stored = photos.compactMap(storeAttachment)
        let indexer = PageIndexer(volume: volume, firstPage: firstPage, pagesPerPhoto: pagesPerPhoto,
                                  writtenOn: writtenOn.map { ZonedDate($0, timeZone: TimeZone.current.identifier) },
                                  tags: tags, location: settings.home)
        let entries = try indexer.entries(for: stored)
        for e in entries { repository.save(e) }
        show("Indexed \(entries.count) page\(entries.count == 1 ? "" : "s") in \(volume.name)")
        return entries
    }

    /// The page after the last one indexed in a volume, as a starting point.
    func nextPage(in volumeId: ULID) -> String {
        let pagination = volume(volumeId)?.pagination ?? .page
        let last = records(in: volumeId).compactMap { r -> String? in
            let parts = r.page.split(whereSeparator: { "-–—".contains($0) })
            return parts.last.map(String.init)
        }.last
        guard let last, let next = PageNumbering.labels(from: last, count: 2, pagination: pagination)?.last else {
            return pagination == .folio ? "1r" : "1"
        }
        return next
    }

    /// Lets the person pick image files.
    static func chooseImages(multiple: Bool = true) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.message = multiple ? "Choose photos, in page order." : "Choose a photo."
        return panel.runModal() == .OK ? panel.urls : []
    }
}

/// A photo from Attachments, loaded off the main thread. Click opens it in Preview.
struct AttachmentThumbnail: View {
    let attachment: Attachment
    var size: CGFloat = 96
    @State private var image: NSImage?

    private var url: URL { Store.attachments.appending(path: attachment.path) }

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: Space.sm))
        }
        .buttonStyle(.plain)
        .help(attachment.originalName ?? attachment.path)
        .task(id: attachment.path) {
            let path = url.path
            image = await Task.detached { NSImage(contentsOfFile: path) }.value
        }
    }
}

/// The photos and files on an entry: thumbnails, Add Photos…, and drop images here.
struct AttachmentsSection: View {
    @Environment(AppModel.self) private var model
    @Binding var attachments: [Attachment]
    @State private var dropping = false

    private var photos: [Attachment] { attachments.filter { $0.kind == .image } }
    private var others: [Attachment] { attachments.filter { $0.kind != .image } }

    var body: some View {
        Section {
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Space.sm) {
                        ForEach(photos, id: \.path) { p in
                            AttachmentThumbnail(attachment: p)
                                .contextMenu { Button("Remove Photo", role: .destructive) { attachments.removeAll { $0 == p } } }
                        }
                    }
                }
            }
            ForEach(others, id: \.path) { a in AttachmentRow(attachment: a) }
            Button("Add Photos…", systemImage: "photo.badge.plus") { add(AppModel.chooseImages()) }
        } header: {
            Text("Photos and files")
        } footer: {
            Text(dropping ? "Drop to add." : "Drop photos here. Right-click a photo to remove it.")
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return true
        } isTargeted: { dropping = $0 }
    }

    private func add(_ urls: [URL]) {
        for url in urls {
            guard let a = model.storeAttachment(url), !attachments.contains(a) else { continue }
            attachments.append(a)
        }
    }
}

/// The photo of the notebook page a record is written on.
struct PagePhotoRow: View {
    @Environment(AppModel.self) private var model
    @Binding var photo: Attachment?

    var body: some View {
        LabeledContent("Page photo") {
            HStack(spacing: Space.sm) {
                if let photo {
                    AttachmentThumbnail(attachment: photo, size: 64)
                    Button("Remove") { self.photo = nil }.controlSize(.small)
                } else {
                    Button("Choose…") { photo = AppModel.chooseImages(multiple: false).first.flatMap(model.storeAttachment) }
                        .controlSize(.small)
                }
            }
        }
    }
}

/// Index Page Photos: a stack of notebook page photos become records in one volume.
struct IndexPagesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let volumeId: ULID?
    @State private var volume: ULID?
    @State private var photos: [URL] = []
    @State private var firstPage = ""
    @State private var spreads = false
    @State private var knowDate = false
    @State private var written = Date.now
    @State private var tags: [TagPath] = []
    @State private var error: String?

    private var labels: [String]? {
        guard let v = volume.flatMap(model.volume) else { return nil }
        return PageNumbering.labels(from: firstPage, count: photos.count, pagination: v.pagination, pagesPerPhoto: spreads ? 2 : 1)
    }

    var body: some View {
        Form {
            Section("Index Page Photos") {
                Picker("Volume", selection: $volume) {
                    Text("Choose…").tag(ULID?.none)
                    ForEach(model.data.volumes) { v in Text(v.name).tag(ULID?.some(v.id)) }
                }
                LabeledContent("Photos") {
                    HStack {
                        Text(photos.isEmpty ? "None" : "\(photos.count) chosen").foregroundStyle(.secondary)
                        Button("Choose…") { photos = AppModel.chooseImages().sorted { $0.lastPathComponent < $1.lastPathComponent } }
                    }
                }
                TextField("First page", text: $firstPage, prompt: Text("40, or 12r"))
                Toggle("Each photo shows two pages", isOn: $spreads)
                Toggle("I know when these were written", isOn: $knowDate)
                if knowDate { DatePicker("Written", selection: $written, displayedComponents: .date) }
                LabeledContent("Tags") { TagField(tags: $tags) }
            }
            Section {
                if let labels, !labels.isEmpty {
                    Text("Pages \(labels.first!) to \(labels.last!), in file-name order.").foregroundStyle(.secondary)
                } else if !photos.isEmpty && volume != nil {
                    Text("Use a number like 40, or 12r for folios.").foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            } footer: {
                Text("Each photo becomes a record marked physical only, so you can transcribe it later.")
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 480)
        .noInitialFocus()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Index") {
                    guard let volume else { return }
                    do {
                        try model.indexPages(volumeId: volume, photos: photos, firstPage: firstPage, pagesPerPhoto: spreads ? 2 : 1,
                                             writtenOn: knowDate ? written : nil, tags: tags)
                        dismiss()
                    } catch {
                        self.error = String(describing: error)
                    }
                }
                .disabled(volume == nil || photos.isEmpty || labels == nil)
            }
        }
        .onAppear {
            volume = volumeId ?? model.data.volumes.last?.id
            if let volume { firstPage = model.nextPage(in: volume) }
        }
        .onChange(of: volume) { _, v in if let v { firstPage = model.nextPage(in: v) } }
    }
}

/// Page photos in a volume as a grid, in page order.
struct VolumePhotoGrid: View {
    @Environment(AppModel.self) private var model
    let volumeId: ULID

    var body: some View {
        let pages = model.data.entries
            .filter { $0.status == .filed && $0.physicalRef?.volumeId == volumeId && $0.physicalRef?.photo != nil }
            .sorted { (($0.physicalRef?.pageRange?.lowerBound ?? .max), $0.id) < (($1.physicalRef?.pageRange?.lowerBound ?? .max), $1.id) }
        if !pages.isEmpty {
            Section("Page photos") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Space.sm)], spacing: Space.sm) {
                    ForEach(pages) { e in
                        VStack(spacing: Space.xs) {
                            AttachmentThumbnail(attachment: e.physicalRef!.photo!)
                            Button("p. \(e.physicalRef!.page)") { model.reveal(e.id) }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }
}
