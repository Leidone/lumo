import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Shelf: a place to park files, text and links for a moment and drag them out later.
@MainActor
final class ShelfStore: ObservableObject {
    struct Item: Identifiable, Codable, Equatable {
        enum Kind: String, Codable {
            case file, text, link
        }

        let id: UUID
        let kind: Kind
        let value: String

        var url: URL? {
            switch kind {
            case .file: return URL(fileURLWithPath: value)
            case .link: return URL(string: value)
            case .text: return nil
            }
        }

        var title: String {
            switch kind {
            case .file: return (value as NSString).lastPathComponent
            case .link: return URL(string: value)?.host ?? value
            case .text: return value.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? value
            }
        }

        /// What dragging the item out of the shelf hands to the drop target.
        var provider: NSItemProvider {
            switch kind {
            case .file: return NSItemProvider(contentsOf: URL(fileURLWithPath: value)) ?? NSItemProvider(object: value as NSString)
            case .link: return URL(string: value).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider(object: value as NSString)
            case .text: return NSItemProvider(object: value as NSString)
            }
        }
    }

    private static let key = "shelf.items"
    private static let maxItems = 40
    static let dropTypes: [UTType] = [.fileURL, .url, .plainText]

    @Published private(set) var items: [Item] = []
    private let store: UserDefaults

    init(store: UserDefaults) {
        self.store = store
        let saved = store.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
        // Files moved or deleted since last time quietly fall off the shelf.
        items = saved.filter { $0.kind != .file || FileManager.default.fileExists(atPath: $0.value) }
    }

    func add(_ kind: Item.Kind, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !items.contains(where: { $0.kind == kind && $0.value == trimmed }) else { return }
        items = Array(([Item(id: UUID(), kind: kind, value: trimmed)] + items).prefix(Self.maxItems))
        save()
    }

    func remove(_ item: Item) {
        items = items.filter { $0.id != item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Accepts whatever was dropped onto a shelf area.
    func accept(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in self?.add(.file, url.path) }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url else { return }
                    Task { @MainActor in self?.add(.link, url.absoluteString) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                accepted = true
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] text, _ in
                    guard let text = text as? String else { return }
                    let kind: Item.Kind = URL(string: text)?.scheme?.hasPrefix("http") == true ? .link : .text
                    Task { @MainActor in self?.add(kind, text) }
                }
            }
        }
        return accepted
    }

    func open(_ item: Item) {
        switch item.kind {
        case .file, .link: item.url.map { NSWorkspace.shared.open($0) }
        case .text: copy(item)
        }
    }

    func copy(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .file: pasteboard.writeObjects([URL(fileURLWithPath: item.value) as NSURL])
        case .link, .text: pasteboard.setString(item.value, forType: .string)
        }
    }

    /// AirDrop if available, otherwise the regular Share menu from the given view.
    func airDrop(_ items: [Item]) {
        let objects = items.map(Self.shareObject)
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: objects) else { return }
        service.perform(withItems: objects)
    }

    func share(_ items: [Item], from view: NSView) {
        NSSharingServicePicker(items: items.map(Self.shareObject)).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private static func shareObject(_ item: Item) -> Any {
        switch item.kind {
        case .file: return URL(fileURLWithPath: item.value)
        case .link: return URL(string: item.value) ?? item.value
        case .text: return item.value
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { store.set(data, forKey: Self.key) }
    }
}
