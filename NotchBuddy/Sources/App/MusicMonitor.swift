import AppKit

// MARK: - MusicMonitor
// Now Playing for Spotify and Apple Music.
// Track changes arrive as distributed notifications the players broadcast themselves, so
// there is no polling: zero work while nothing changes. AppleScript is only used to read
// the exact position/artwork after a change and to send play/pause/skip.

@MainActor
final class MusicMonitor {
    static let shared = MusicMonitor()

    private var started = false
    private var artworkKey = ""
    private let launchDate = Date()
    private var announcedKey = ""

    private struct Broadcast: Sendable {
        let player: NowPlaying.Player
        let state: String
        let title: String
        let artist: String
        let album: String
        let durationMs: Double
        let position: Double?
        let trackKey: String
    }

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        let center = DistributedNotificationCenter.default()
        let sources: [(String, NowPlaying.Player)] = [
            ("com.spotify.client.PlaybackStateChanged", .spotify),
            ("com.apple.Music.playerInfo", .music),
        ]
        for (name, player) in sources {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { note in
                let info = note.userInfo ?? [:]
                func num(_ key: String) -> Double? {
                    (info[key] as? NSNumber)?.doubleValue ?? (info[key] as? String).flatMap(Double.init)
                }
                let title = info["Name"] as? String ?? ""
                let id = (info["Track ID"] as? String) ?? num("PersistentID").map { String(Int64($0)) } ?? title
                let b = Broadcast(
                    player: player,
                    state: info["Player State"] as? String ?? "",
                    title: title,
                    artist: info["Artist"] as? String ?? "",
                    album: info["Album"] as? String ?? "",
                    durationMs: num("Duration") ?? num("Total Time") ?? 0,
                    position: num("Playback Position"),
                    trackKey: "\(player.rawValue):\(id)")
                Task { @MainActor in MusicMonitor.shared.handle(b) }
            }
        }

        // Player quit → nothing is playing any more
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in
            let bundleId = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in
                if let np = AppState.shared.nowPlaying, np.player.bundleId == bundleId {
                    MusicMonitor.shared.publish(nil)
                }
            }
        }

        // Pick up whatever is already playing at launch
        refresh()
    }

    // MARK: - Controls

    func playPause() {
        guard var np = AppState.shared.nowPlaying else { return }
        send("playpause", to: np.player)
        // Optimistic flip so the button answers instantly; the broadcast confirms it.
        np.position = np.position(at: Date())
        np.positionDate = Date()
        np.isPlaying.toggle()
        publish(np)
    }

    /// Jumps to a position in the current track (seconds).
    func seek(to seconds: TimeInterval) {
        guard var np = AppState.shared.nowPlaying else { return }
        let target = max(0, np.duration > 0 ? min(seconds, np.duration - 1) : seconds)
        send("set player position to \(Int(target))", to: np.player)
        np.position = target
        np.positionDate = Date()
        publish(np)
    }

    func next()     { if let p = AppState.shared.nowPlaying?.player { send("next track", to: p) } }
    func previous() { if let p = AppState.shared.nowPlaying?.player { send("previous track", to: p) } }

    func openPlayer(_ player: NowPlaying.Player? = nil) {
        let target = player ?? AppState.shared.nowPlaying?.player
            ?? NowPlaying.Player.allCases.first(where: \.isRunning)
            ?? NowPlaying.Player.allCases.first(where: \.isInstalled)
        guard let target, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    private func send(_ command: String, to player: NowPlaying.Player) {
        guard player.isRunning else { return }
        AppleScriptRunner.run("with timeout of 5 seconds\ntell application id \"\(player.bundleId)\" to \(command)\nend timeout") { outcome in
            if outcome.denied { AppState.shared.musicAutomationDenied = true }
            else if outcome.output != nil { AppState.shared.musicAutomationDenied = false }
        }
    }

    // MARK: - Broadcast handling

    private func handle(_ b: Broadcast) {
        guard AppState.shared.activeIntegrations.contains("integration_music") else { return }
        let current = AppState.shared.nowPlaying

        if b.state == "Stopped" || b.title.isEmpty {
            if current?.player == b.player { publish(nil) }
            return
        }
        // A paused player must not steal the card from the one that is actually playing.
        let playing = b.state == "Playing"
        if !playing, let current, current.player != b.player, current.isPlaying { return }

        let sameTrack = current?.trackKey == b.trackKey
        let position = b.position ?? (sameTrack ? current!.position(at: Date()) : 0)
        var np = NowPlaying(
            player: b.player, title: b.title, artist: b.artist, album: b.album,
            isPlaying: playing, duration: b.durationMs / 1000,
            position: position, positionDate: Date(), trackKey: b.trackKey)
        if sameTrack { np.artwork = current?.artwork }   // assigned after init so the palette follows
        publish(np)

        // Exact position + artwork (needs Automation consent; the card works without it)
        query(b.player)
    }

    /// Asks the running players directly — used at launch and when the card appears.
    func refresh() {
        guard AppState.shared.activeIntegrations.contains("integration_music") else { return }
        if let current = AppState.shared.nowPlaying?.player, current.isRunning {
            query(current)
        } else {
            for player in NowPlaying.Player.allCases where player.isRunning { query(player) }
        }
    }

    // MARK: - AppleScript state query

    private func query(_ player: NowPlaying.Player) {
        guard player.isRunning else { return }
        let script: String
        switch player {
        case .spotify:
            script = """
            with timeout of 6 seconds
                tell application id "com.spotify.client"
                    if player state is stopped then return "stopped"
                    set d to character id 31
                    set pstate to "paused"
                    if player state is playing then set pstate to "playing"
                    set t to current track
                    set art to ""
                    try
                        set art to artwork url of t
                    end try
                    return pstate & d & (name of t) & d & (artist of t) & d & (album of t) & d & ((duration of t) as text) & d & (player position as text) & d & art & d & (id of t)
                end tell
            end timeout
            """
        case .music:
            script = """
            with timeout of 6 seconds
                set artData to missing value
                tell application id "com.apple.Music"
                    if player state is stopped then return "stopped"
                    set d to character id 31
                    set pstate to "paused"
                    if player state is playing then set pstate to "playing"
                    set t to current track
                    set tid to name of t
                    try
                        set tid to (database ID of t) as text
                    end try
                    set meta to pstate & d & (name of t) & d & (artist of t) & d & (album of t) & d & (((duration of t) * 1000) as text) & d & (player position as text)
                    if tid is not \(AppleScriptRunner.quoted(Self.keyId(artworkKey, for: .music))) then
                        try
                            set artData to raw data of artwork 1 of t
                        end try
                    end if
                end tell
                set art to ""
                if artData is not missing value then
                    try
                        set fp to open for access POSIX file \(AppleScriptRunner.quoted(Self.artworkFile.path)) with write permission
                        set eof fp to 0
                        write artData to fp
                        close access fp
                        set art to "file"
                    end try
                end if
                return meta & d & art & d & tid
            end timeout
            """
        }
        AppleScriptRunner.run(script) { outcome in
            MusicMonitor.shared.applyQuery(outcome, player: player)
        }
    }

    private func applyQuery(_ outcome: AppleScriptRunner.Outcome, player: NowPlaying.Player) {
        let app = AppState.shared
        if outcome.denied { app.musicAutomationDenied = true }
        guard let output = outcome.output else { return }
        app.musicAutomationDenied = false

        if output == "stopped" {
            if app.nowPlaying?.player == player { publish(nil) }
            return
        }
        let f = output.components(separatedBy: "\u{1F}")
        guard f.count >= 8 else { return }
        // AppleScript prints numbers with the system locale ("12,5")
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

        let playing = f[0] == "playing"
        let current = app.nowPlaying
        if !playing, let current, current.player != player, current.isPlaying { return }

        let key = "\(player.rawValue):\(f[7])"
        var np = NowPlaying(
            player: player, title: f[1], artist: f[2], album: f[3],
            isPlaying: playing, duration: number(f[4]) / 1000,
            position: number(f[5]), positionDate: Date(), trackKey: key)
        if artworkKey == key { np.artwork = current?.artwork }

        if artworkKey != key {
            artworkKey = key
            switch player {
            case .music:
                if f[6] == "file" { np.artwork = NSImage(contentsOf: Self.artworkFile) }
            case .spotify:
                loadSpotifyArtwork(f[6], key: key)
            }
        }
        publish(np)
    }

    /// Spotify hands out a CDN URL for the cover; only its own hosts are accepted.
    private func loadSpotifyArtwork(_ urlString: String, key: String) {
        guard let url = URL(string: urlString), url.scheme == "https",
              let host = url.host, host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com") else { return }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 10)) { data, _, _ in
            guard let data else { return }
            Task { @MainActor in
                guard var np = AppState.shared.nowPlaying, np.trackKey == key,
                      let image = NSImage(data: data) else { return }
                np.artwork = image
                MusicMonitor.shared.publish(np)
            }
        }.resume()
    }

    // MARK: - Publish

    private func publish(_ np: NowPlaying?) {
        let app = AppState.shared
        guard app.nowPlaying != np else { return }
        let previous = app.nowPlaying
        app.nowPlaying = np
        if np == nil { artworkKey = "" }

        if previous?.isPlaying != np?.isPlaying {
            IslandWindowController.shared?.liveActivityChanged()
        }
        // New track while the island is folded: announce it, once its cover has had time to load
        if let np, np.isPlaying, np.trackKey != announcedKey, Date().timeIntervalSince(launchDate) > 9 {
            announcedKey = np.trackKey
            let key = np.trackKey
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { MusicMonitor.shared.announce(key) }
        } else if let np, announcedKey.isEmpty {
            announcedKey = np.trackKey   // whatever was already playing at launch is not news
        }
        if let idx = app.tasks.firstIndex(where: { $0.id == "integration_music" }) {
            app.tasks[idx].steps = np.map { [$0.title] } ?? []
        }
    }

    private func announce(_ key: String) {
        let app = AppState.shared
        guard app.announceTracks, app.activeIntegrations.contains("integration_music"),
              let np = app.nowPlaying, np.trackKey == key, np.isPlaying else { return }
        IslandWindowController.shared?.showToast(IslandToast(
            artwork: np.artwork, symbol: "music.note", title: np.title,
            subtitle: np.artist.isEmpty ? np.album : np.artist,
            palette: np.palette, accent: "#EC4899", focusId: "integration_music", showsEqualizer: true))
        appendAppLog("nb.log", "Track banner")
    }

    // MARK: - Helpers

    private static func keyId(_ key: String, for player: NowPlaying.Player) -> String {
        let prefix = "\(player.rawValue):"
        return key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : ""
    }

    private static let artworkFile: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fr.louisraille.NotchBuddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("now-playing-artwork")
    }()
}
