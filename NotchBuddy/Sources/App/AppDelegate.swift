import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?

    override init() {
        super.init()
        Migration.settingsIfNeeded()   // before AppState reads a single default
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE — prevents crash when nb-hook closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupIsland()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClaudeCodeCLI.shared.stop()   // don't leave a headless claude running
        KeepAwake.shared.releaseAll()
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Dewdrop")
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = "Dewdrop"
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Dewdrop", action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openIsland() {
        islandController?.expand(to: .overview)
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettings() {
        // The island floats above every window; fold it away so it can't cover Settings.
        if AppState.shared.mode == .expanded { islandController?.collapse() }

        if let w = settingsWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Settings — Dewdrop"
        let host = NSHostingView(rootView: SettingsView())
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = NSSize(width: 420, height: 320)
        win.isReleasedWhenClosed = false
        placeBelowIsland(win)
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Centres the window horizontally and keeps its title bar clear of the island panel
    /// (320 pt tall at the top of the notch screen), shrinking it to fit if needed.
    private func placeBelowIsland(_ win: NSWindow) {
        let screen = IslandWindowController.notchScreen() ?? NSScreen.main ?? win.screen
        guard let screen else { win.center(); return }
        let visible = screen.visibleFrame
        let islandBottom = screen.frame.maxY - 320 - 12   // island panel height + margin
        let top = min(visible.maxY, islandBottom)
        var frame = win.frame
        frame.size.height = min(frame.height, max(top - visible.minY - 12, win.minSize.height))
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = max(visible.minY + 12, top - frame.height)
        win.setFrame(frame, display: true)
    }

    // MARK: - Island setup

    private func setupIsland() {
        islandController = IslandWindowController()
        IslandWindowController.shared = islandController
        islandController?.showWindow(nil)
        islandController?.fsm.launch()
        HookServer.shared.start()
        N8nPoller.shared.start()
        VercelPoller.shared.start()
        ResendPoller.shared.start()
        GithubPoller.shared.start()
        StripePoller.shared.start()
        CalcomPoller.shared.start()
        NotionPoller.shared.start()
        MusicMonitor.shared.start()
        SystemMonitor.shared.start()
        TimerEngine.shared.start()
        ShelfStore.shared.start()
        ClipboardMonitor.shared.start()
        KeepAwake.shared.start()
        ClaudeHub.shared.start()
        NotesStore.shared.start()
        HUDMonitor.shared.start()
        WeatherMonitor.shared.start()
        #if DEBUG
        runDebugArguments()
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openFullSettings, object: nil)
    }

    #if DEBUG
    /// Development only — opens a given card or sends a chat message at launch so the UI can be
    /// checked without driving the mouse: `open Coucou.app --args -debugFocus integration_music`
    /// or `-debugChat "question"`. Not compiled into Release builds.
    private func runDebugArguments() {
        let ud = UserDefaults.standard
        let focus = ud.string(forKey: "debugFocus")
        let chat = ud.string(forKey: "debugChat")
        let timer = ud.integer(forKey: "debugTimer")
        let toast = ud.bool(forKey: "debugToast")
        let longTitle = ud.string(forKey: "debugTitle")
        let samples = ud.bool(forKey: "debugSamples")
        let awake = ud.bool(forKey: "debugAwake")
        let upload = ud.bool(forKey: "debugUpload")
        let props = ud.string(forKey: "debugProps")     // "headphones,mug,nightcap,party" or "none"
        let confetti = ud.bool(forKey: "debugConfetti")
        let power = ud.string(forKey: "debugPower")     // "charge" or "low"
        let hud = ud.string(forKey: "debugHUD")         // "volume", "mute" or "brightness"
        let claude = ud.string(forKey: "debugClaude")   // "finished" or "needs"
        let weather = ud.string(forKey: "debugWeather") // "rain", "sun", "snow" (sample data, opens the card)
        let bot = ud.string(forKey: "debugState")       // working, searching, error…
        let lively = ud.bool(forKey: "debugLively")     // animations as if the pointer were on the island
        let views = ud.string(forKey: "debugView")      // "overview,prompt,settings": opens the first, then steps through the rest
        if ud.bool(forKey: "debugBounce") {
            SoundEngine.shared.enabled = false
            if samples { Self.sampleSessions(AppState.shared) }
            if let props { AppState.shared.propsOverride = Self.props(named: props) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { PerfProbe.shared.bounce() }
            return
        }
        guard focus != nil || chat != nil || timer > 0 || toast || longTitle != nil || samples || awake
                || upload || props != nil || confetti || power != nil || hud != nil || claude != nil
                || weather != nil || bot != nil || views != nil || lively else { return }
        if let bot, let forced = BotState(rawValue: bot) { AppState.shared.stateOverride = forced }
        if let props { AppState.shared.propsOverride = Self.props(named: props) }
        SoundEngine.shared.enabled = false   // visual checks only — stay quiet
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { [weak self] in
            let state = AppState.shared
            if let focus {
                state.setFocus(focus)
                self?.islandController?.expand(to: .overview)
            }
            if let chat {
                self?.islandController?.expand(to: .prompt)
                state.chatHistory.append(ChatMessage(role: .user, content: chat))
                Task { await ClaudeService.shared.chat(query: chat, context: nil, state: state) }
            }
            if let views {
                for (i, name) in views.split(separator: ",").enumerated() {
                    guard let view = IslandView(rawValue: String(name)) else { continue }
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 4) {
                        self?.islandController?.expand(to: view)
                        AppState.shared.isPinned = true
                    }
                }
            }
            if lively { IslandMotion.shared.pointer(onIsland: true) }
            if timer > 0 { TimerEngine.shared.debugStart(seconds: timer) }
            if awake { KeepAwake.shared.set(true) }
            if confetti { self?.debugConfetti(rounds: 8) }
            if samples {
                Self.sampleSessions(state)
                state.notes = [NoteItem(text: "Ask the team about the notch API", date: Date().addingTimeInterval(-200)),
                               NoteItem(text: "Buy oat milk", date: Date().addingTimeInterval(-4000), done: true),
                               NoteItem(text: "Idea: Dew wears a scarf when it snows", date: Date().addingTimeInterval(-90000))]
            }
            if let weather {
                let codes = ["rain": 63, "sun": 0, "snow": 73, "storm": 95, "cloud": 3]
                let code = codes[weather] ?? 0
                let now = Date()
                state.weather = WeatherInfo(
                    city: "Istanbul", temp: weather == "snow" ? -1 : 21, code: code, isDay: true, high: 24, low: 15,
                    hours: (1...4).map { .init(date: now.addingTimeInterval(Double($0) * 3600), temp: 21 - Double($0),
                                               code: $0 < 3 ? code : 2, isDay: $0 < 3) },
                    fetched: now, isCold: weather == "snow")
                state.showWeather = true
                self?.islandController?.expand(to: .overview)
            }
            if let hud {
                self?.debugBanner(retries: 12) {
                    HUDMonitor.shared.show(hud == "brightness" ? .brightness : .volume,
                                           level: hud == "brightness" ? 0.92 : 0.62, muted: hud == "mute")
                    // Hold it for the capture
                    IslandWindowController.shared?.showToast(AppState.shared.toast!, duration: 30)
                }
                return
            }
            if let claude {
                self?.debugBanner(retries: 12) {
                    let finished = claude == "finished"
                    IslandWindowController.shared?.showToast(IslandToast(
                        symbol: finished ? "checkmark" : "hand.raised.fill", title: "dewdrop",
                        subtitle: finished ? "All four features are in and build cleanly." : "Claude needs your permission to use Bash",
                        accent: finished ? "#34D399" : "#F5A524", focusId: "integration_claude",
                        action: .jump(taskId: "integration_claude")), duration: 30)
                }
                return
            }
            if let power {
                self?.debugPower(low: power == "low", retries: 12)
                return
            }
            if upload {
                // The drop zone as it looks while a file hovers over the notch
                UploadSequenceEngine.shared.enterZone(x: 320, y: 90)
                self?.islandController?.expand(to: .upload)
                // With "-debugDrop 1": also play what follows a drop (animation only, nothing is sent)
                if ud.bool(forKey: "debugDrop") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        state.view = .uploading
                        UploadSequenceEngine.shared.performDrop(uploadDuration: 2.4)
                    }
                }
            }
            if let longTitle {
                // After the card's own refresh has landed
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { state.nowPlaying?.title = longTitle }
            }
            if samples {
                // Sample content for the shelf and clipboard cards (nothing touches the real clipboard)
                let app = Bundle.main.bundleURL
                state.shelf = [app, app.appendingPathComponent("Contents/Info.plist"),
                               URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")].map { ShelfItem(url: $0) }
                state.clips = ["https://liquidglassdesign.com", "let island = DynamicIsland()", "Remember the milk"]
                    .map { ClipItem(text: $0, date: Date().addingTimeInterval(-Double.random(in: 30...4000))) }
            }
            if toast {
                self?.debugToast(title: longTitle, retries: 12)
                return
            }
            state.isPinned = true
        }
    }

    /// Sample Claude Code sessions for screenshots, so no real project name shows.
    private static func sampleSessions(_ state: AppState) {
        // Sample Claude Code sessions (so screenshots show no real project names)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        state.claudeSessions = [
            ClaudeSession(id: "sample-1", title: "Add dark mode to the settings window", cwd: home + "/Code/notch-app",
                          modified: Date(), livePid: ProcessInfo.processInfo.processIdentifier, busy: true),
            ClaudeSession(id: "sample-2", title: "Fix the flaky upload test", cwd: home + "/Code/api",
                          modified: Date().addingTimeInterval(-14 * 60)),
            ClaudeSession(id: "sample-3", title: "Write the release notes", cwd: home + "/Code/docs",
                          modified: Date().addingTimeInterval(-49 * 60)),
        ]
        ClaudeHub.shared.frozen = true
    }

    private static func props(named props: String) -> BotProps {
        var set: BotProps = []
        if props.contains("headphones") { set.insert(.headphones) }
        if props.contains("mug") { set.insert(.mug) }
        if props.contains("nightcap") { set.insert(.nightcap) }
        if props.contains("party") { set.insert(.partyHat) }
        if props.contains("sunglasses") { set.insert(.sunglasses) }
        if props.contains("umbrella") { set.formUnion([.umbrella, .rainfall]) }
        if props.contains("scarf") { set.formUnion([.scarf, .snowfall]) }
        if props.contains("laptop") { set.insert(.laptop) }
        if props.contains("magnifier") { set.insert(.magnifier) }
        if props.contains("bandage") { set.insert(.bandage) }
        if props.contains("pencil") { set.insert(.pencil) }
        return set
    }

    /// Runs `show` once the island is folded (the greeting holds it open for a while after launch).
    private func debugBanner(retries: Int, show: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let state = AppState.shared
            if state.mode == .expanded && state.view != .toast {
                if retries > 0 { self?.debugBanner(retries: retries - 1, show: show) }
                return
            }
            show()
        }
    }

    /// Confetti and the party reaction every few seconds, so a still capture catches them in flight.
    private func debugConfetti(rounds: Int) {
        guard rounds > 0 else { return }
        AppState.shared.celebrate()
        NotificationCenter.default.post(name: .botReact, object: BotReaction.party)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in self?.debugConfetti(rounds: rounds - 1) }
    }

    /// Shows a sample power banner once the island is folded.
    private func debugPower(low: Bool, retries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let state = AppState.shared
            if state.mode == .expanded && state.view != .toast {
                if retries > 0 { self?.debugPower(low: low, retries: retries - 1) }
                return
            }
            SystemMonitor.shared.announcePower(level: low ? 0.2 : 0.64, charging: !low, minutes: low ? 38 : 72)
        }
    }

    /// Shows a sample banner once the island is folded (retries while the greeting is still open).
    private func debugToast(title: String?, retries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let state = AppState.shared
            if state.mode == .expanded && state.view != .toast {
                if retries > 0 { self?.debugToast(title: title, retries: retries - 1) }
                return
            }
            let np = state.nowPlaying
            self?.islandController?.showToast(IslandToast(
                artwork: np?.artwork, symbol: "music.note",
                title: title ?? np?.title ?? "Sample track", subtitle: np?.artist ?? "Sample artist",
                palette: np?.palette ?? [], accent: "#EC4899", focusId: "integration_music",
                showsEqualizer: true), duration: 40)
            appendAppLog("nb.log", "debug toast shown")
        }
    }
    #endif
}
