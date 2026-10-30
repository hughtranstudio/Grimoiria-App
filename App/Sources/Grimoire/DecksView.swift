import GrimoireAppKit
import GrimoireCore
import SwiftUI
import UniformTypeIdentifiers

/// Decks and spreads from the Definitions folder.
struct DeckList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            if let error = model.definitionsError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
            Section(header: Text("Decks").font(Typo.caption)) {
                ForEach(model.library.decks) { d in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(d.name).font(Typo.body)
                        Text(subtitle(d)).font(Typo.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Space.xs)
                    .tag(Selection.deck(d.id))
                }
            }
            Section(header: Text("Spreads").font(Typo.caption)) {
                ForEach(model.library.spreads) { s in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(s.name).font(Typo.body)
                        Text(s.openEnded ? "Any number of cards" : s.positions.map(\.label).joined(separator: " · "))
                            .font(Typo.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.vertical, Space.xs)
                    .selectionDisabled()
                }
            }
            Section(header: Text("Yi Jing").font(Typo.caption)) {
                Text("\(model.library.yijing.hexagrams.count) hexagrams, \(model.library.yijing.trigrams.count) trigrams").font(Typo.body)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Import Deck…", systemImage: "square.and.arrow.down") { model.importDeck() }
                    .help("Add a deck from a JSON file")
            }
            ToolbarItem {
                Button("Show Definitions in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Store.definitions])
                }
                .help("Open the Definitions folder")
            }
        }
    }

    private func subtitle(_ d: DeckDefinition) -> String {
        switch d.status {
        case .complete: "\(d.cards.count) cards"
        case .placeholder: "Placeholder: cards still to come"
        case .template: "Template for your own deck"
        }
    }
}

/// One deck: name, status, and every card with its glyph and attributes. Editable.
struct DeckDetail: View {
    @Environment(AppModel.self) private var model
    let deckId: String
    @State private var deck: DeckDefinition?
    @State private var error: String?
    @State private var newCard = ""

    var body: some View {
        Group {
            if let binding = Binding($deck) { form(binding) } else { ProgressView() }
        }
        .onAppear { deck = model.library.deck(deckId) }
    }

    private var changed: Bool { deck != model.library.deck(deckId) }

    private func form(_ deck: Binding<DeckDefinition>) -> some View {
        Form {
            Section {
                TextField("Name", text: deck.name)
                LabeledContent("Status") { Text(deck.wrappedValue.status.rawValue.capitalized).foregroundStyle(.secondary) }
                Toggle("Reversals allowed", isOn: deck.reversalsAllowed)
                LabeledContent("Aliases") { ListField(items: deck.aliases.optional, prompt: "rws, rider") }
                if let source = deck.wrappedValue.source {
                    Text(source).font(Typo.callout).foregroundStyle(.secondary)
                }
            }
            Section("Cards (\(deck.wrappedValue.cards.count))") {
                if deck.wrappedValue.cards.isEmpty {
                    Text("No cards yet.").foregroundStyle(.secondary)
                }
                ForEach(deck.cards) { $card in
                    DisclosureGroup {
                        TextField("Name", text: $card.name)
                        LabeledContent("Aliases") { ListField(items: $card.aliases.optional, prompt: "other names") }
                        ForEach(deck.wrappedValue.attributes, id: \.self) { key in
                            TextField(key.capitalized, text: Binding(
                                get: { card.attributes[key]?.description ?? "" },
                                set: { card.attributes[key] = $0.isEmpty ? nil : Double($0).map(AttributeValue.number) ?? .string($0) }
                            ))
                        }
                        if !card.significations.isEmpty {
                            ForEach(card.significations.keys.sorted(), id: \.self) { k in
                                LabeledContent(k.capitalized) { Text(card.significations[k]?.description ?? "").foregroundStyle(.secondary) }
                            }
                        }
                    } label: {
                        Text(CardName.text(card))
                    }
                }
                HStack {
                    TextField("New card", text: $newCard, prompt: Text("Card name"))
                    Button("Add Card") {
                        let id = ObsidianExporter.slug(newCard)
                        deck.wrappedValue.cards.append(DeckDefinition.Card(id: id.isEmpty ? "card-\(deck.wrappedValue.cards.count + 1)" : id, name: newCard))
                        newCard = ""
                    }
                    .disabled(newCard.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(deck.wrappedValue.name)
        .toolbar {
            ToolbarItem {
                Button("Revert") { self.deck = model.library.deck(deckId); error = nil }.disabled(!changed)
            }
            ToolbarItem {
                Button("Save Deck") { save(deck.wrappedValue) }
                    .disabled(!changed)
                    .keyboardShortcut("s")
            }
        }
    }

    private func save(_ deck: DeckDefinition) {
        do {
            model.library = try DefinitionsFolder.save(deck, in: model.library, folder: Store.definitions)
            model.definitionsReport = model.library.validate()
            error = nil
            model.show("Saved \(deck.name)")
        } catch {
            self.error = String(describing: error)
        }
    }
}

extension Binding where Value == [String] {
    var optional: Binding<[String]?> {
        Binding<[String]?>(get: { wrappedValue }, set: { wrappedValue = $0 ?? [] })
    }
}

extension AppModel {
    /// Adds a deck from a JSON file, after it passes validation.
    func importDeck() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a deck file (JSON, like the decks in the Definitions folder)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let deck = try JSONDecoder().decode(DeckDefinition.self, from: Data(contentsOf: url))
            library = try DefinitionsFolder.save(deck, in: library, folder: Store.definitions)
            definitionsReport = library.validate()
            page = .decks
            selection = .deck(deck.id)
            show("Imported \(deck.name)")
        } catch {
            let alert = NSAlert()
            alert.messageText = "The deck could not be imported."
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }
}
