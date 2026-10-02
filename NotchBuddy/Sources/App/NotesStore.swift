import Foundation

// MARK: - NotesStore
// Quick notes for the Notes pill: a line you jot down in the notch so it isn't lost.
// Kept in the app's preferences on this Mac; nothing is sent anywhere.

@MainActor
final class NotesStore {
    static let shared = NotesStore()

    private let storeKey = "skillNotes"
    private static let capacity = 40
    private var app: AppState { AppState.shared }

    private init() {}

    func start() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode([NoteItem].self, from: data) {
            app.notes = saved
        }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var notes = app.notes
        notes.insert(NoteItem(text: String(trimmed.prefix(2_000)), date: Date()), at: 0)
        app.notes = Array(notes.prefix(Self.capacity))
        save()
        SoundEngine.shared.play("pop")
        NotificationCenter.default.post(name: .botReact, object: BotReaction.scribble)
    }

    func toggle(_ id: UUID) {
        guard let i = app.notes.firstIndex(where: { $0.id == id }) else { return }
        app.notes[i].done.toggle()
        save()
        if app.notes[i].done {
            SoundEngine.shared.play("blip")
            NotificationCenter.default.post(name: .botReact, object: BotReaction.cheer)
        }
    }

    func remove(_ id: UUID) {
        app.notes.removeAll { $0.id == id }
        save()
    }

    func clearDone() {
        app.notes.removeAll(where: \.done)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(app.notes) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
