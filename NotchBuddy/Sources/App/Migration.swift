import AppKit

/// One-time moves from the app's earlier identity (Coucou, `fr.louisraille.NotchBuddy`) to Dewdrop.
///
/// Settings lived in the old preferences domain; they are copied once into this app's domain,
/// before anything reads them. Keychain items keep the service name they always had, so the API
/// keys stay where they are (macOS may ask once to let the renamed app use them). The hooks in
/// `~/.claude/coucou/` talk to a socket whose path has not changed, so they keep working
/// without being reinstalled. Login-item registration is per app and has to be switched on again
/// in Settings.
@MainActor
enum Migration {
    private static let oldDomain = "fr.louisraille.NotchBuddy"
    private static let doneKey = "migratedFromCoucou"

    /// Call before `AppState` is first touched.
    static func settingsIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: doneKey) else { return }
        let mine = Bundle.main.bundleIdentifier.flatMap { ud.persistentDomain(forName: $0) } ?? [:]
        if let old = ud.persistentDomain(forName: oldDomain), !old.isEmpty, mine.isEmpty {
            for (key, value) in old { ud.set(value, forKey: key) }
            appendAppLog("nb.log", "Migration: \(old.count) settings copied from \(oldDomain)")
        }
        ud.set(true, forKey: doneKey)
    }
}
