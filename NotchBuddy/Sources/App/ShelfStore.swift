import AppKit

// MARK: - ShelfStore
// A place to park files: drop them on the notch, drag them back out when needed.
// Only the file locations are remembered — nothing is copied or moved.

@MainActor
final class ShelfStore {
    static let shared = ShelfStore()
    static let capacity = 12

    private let storeKey = "shelfPaths"
    private var app: AppState { AppState.shared }

    private init() {}

    func start() {
        let paths = UserDefaults.standard.stringArray(forKey: storeKey) ?? []
        app.shelf = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { ShelfItem(url: URL(fileURLWithPath: $0)) }
    }

    func add(_ urls: [URL]) {
        guard app.activeIntegrations.contains("integration_shelf") else { return }
        var items = app.shelf
        for url in urls where url.isFileURL {
            items.removeAll { $0.url.path == url.path }
            items.insert(ShelfItem(url: url), at: 0)
        }
        app.shelf = Array(items.prefix(Self.capacity))
        save()
    }

    func remove(_ item: ShelfItem) {
        app.shelf.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        app.shelf = []
        save()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func save() {
        UserDefaults.standard.set(app.shelf.map(\.url.path), forKey: storeKey)
    }
}
