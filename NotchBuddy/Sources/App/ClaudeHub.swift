import AppKit

// MARK: - ClaudeHub
// Everything about Claude in one place:
//  • plan usage (5-hour and weekly limits), from what Claude itself reports locally
//  • recent Claude Code sessions, read from ~/.claude/projects, reopened in the terminal
//  • shortcuts into the Claude desktop app for regular chats

@MainActor
final class ClaudeHub {
    static let shared = ClaudeHub()

    private var app: AppState { AppState.shared }
    private static let queue = DispatchQueue(label: "fr.louisraille.NotchBuddy.claudehub", qos: .utility)
    private var scanning = false

    private init() {}

    func start() {
        loadUsageFromDesktopApp()
        refreshSessions()
    }

    // MARK: - Usage

    /// Called whenever Claude Code reports its limits (every notch chat reply carries them).
    func report(_ usage: ClaudeUsage) {
        if let current = app.claudeUsage, current.asOf > usage.asOf { return }
        app.claudeUsage = usage
    }

    /// The Claude desktop app logs the same percentages while it is open.
    func loadUsageFromDesktopApp() {
        Self.queue.async {
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let last = (json["samples"] as? [[String: Any]])?.last,
                  let t = last["t"] as? Double,
                  let u = last["u"] as? [String: Any],
                  let fh = (u["fh"] as? NSNumber)?.doubleValue,
                  let sd = (u["sd"] as? NSNumber)?.doubleValue else { return }
            let usage = ClaudeUsage(fiveHour: fh / 100, sevenDay: sd / 100, asOf: Date(timeIntervalSince1970: t / 1000))
            Task { @MainActor in ClaudeHub.shared.report(usage) }
        }
    }

    /// Asks Claude Code for fresh numbers. This sends one tiny request (the cheapest model,
    /// nothing saved), so it only ever runs when the user taps the meter.
    func refreshUsageNow() {
        guard !app.claudeUsageRefreshing, let binary = ClaudeCodeCLI.binaryURL else { return }
        app.claudeUsageRefreshing = true
        Self.queue.async {
            let p = Process()
            p.executableURL = binary
            p.arguments = ["-p", "--model", "haiku", "--output-format", "stream-json", "--verbose",
                           "--no-session-persistence"]
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            var env = ProcessInfo.processInfo.environment
            env["COUCOU_NOTCH"] = "1"
            p.environment = env
            let stdin = Pipe(), stdout = Pipe()
            p.standardInput = stdin
            p.standardOutput = stdout
            p.standardError = Pipe()

            var usage: ClaudeUsage?
            if (try? p.run()) != nil {
                stdin.fileHandleForWriting.write(Data("Reply with the single word: ok".utf8))
                try? stdin.fileHandleForWriting.close()
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    if let u = ClaudeCodeCLI.usage(fromStreamLine: String(line)) { usage = u }
                }
            }
            let result = usage
            Task { @MainActor in
                AppState.shared.claudeUsageRefreshing = false
                if let result { ClaudeHub.shared.report(result) }
            }
        }
    }

    // MARK: - Sessions

    func refreshSessions() {
        guard !scanning else { return }
        scanning = true
        Self.queue.async {
            let sessions = Self.scanSessions()
            Task { @MainActor in
                ClaudeHub.shared.scanning = false
                if AppState.shared.claudeSessions != sessions { AppState.shared.claudeSessions = sessions }
            }
        }
    }

    /// Jumps to the session's terminal tab if it is still running, otherwise resumes it in a new one.
    func open(_ session: ClaudeSession) {
        SoundEngine.shared.play("blip")
        if let pid = session.livePid {
            Self.queue.async {
                let tty = Self.tty(of: pid)
                Task { @MainActor in
                    if let tty { TerminalJumper.focus(tty: tty) }
                    else { TerminalJumper.resume(sessionId: session.id, cwd: session.cwd) }
                }
            }
        } else {
            TerminalJumper.resume(sessionId: session.id, cwd: session.cwd)
        }
    }

    // MARK: - Regular chats (Claude desktop app / claude.ai)
    // Those conversations live on Anthropic's servers; nothing on disk lists them, so the notch
    // offers the two useful doors: the app with its chat list, and a new chat.

    private static let desktopBundleId = "com.anthropic.claudefordesktop"

    private var desktopAppURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.desktopBundleId)
            ?? (FileManager.default.fileExists(atPath: "/Applications/Claude.app")
                ? URL(fileURLWithPath: "/Applications/Claude.app") : nil)
    }

    func openChats() {
        if let appURL = desktopAppURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
        } else if let url = URL(string: "https://claude.ai/recents") {
            NSWorkspace.shared.open(url)
        }
    }

    func newChat() {
        let link = desktopAppURL != nil ? "claude://claude.ai/new" : "https://claude.ai/new"
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Scanning (background)

    private nonisolated static func scanSessions() -> [ClaudeSession] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let projects = home.appendingPathComponent(".claude/projects")
        guard let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return [] }

        var files: [(url: URL, modified: Date)] = []
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            else { continue }
            for file in entries where file.pathExtension == "jsonl" {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                files.append((file, date ?? .distantPast))
            }
        }
        files.sort { $0.modified > $1.modified }

        let live = liveSessions(home: home)
        var result: [ClaudeSession] = []
        let recent = files.prefix(40)
        for file in recent {
            guard result.count < 12 else { break }
            // Transcripts are big; only re-read the ones that changed since the last scan
            let key = file.url.path
            let parsed: ClaudeSession?
            if let hit = parseCache[key], hit.modified == file.modified {
                parsed = hit.session
            } else {
                parsed = parse(file.url, modified: file.modified, live: live)
                parseCache[key] = (file.modified, parsed)
            }
            guard var session = parsed else { continue }
            session.livePid = live[session.id]?.pid
            session.busy = live[session.id]?.busy ?? false
            result.append(session)
        }
        let keep = Set(recent.map(\.url.path))
        parseCache = parseCache.filter { keep.contains($0.key) }
        return result
    }

    /// Parsed transcripts by path, valid while the file is unchanged. Only touched on `queue`.
    nonisolated(unsafe) private static var parseCache: [String: (modified: Date, session: ClaudeSession?)] = [:]

    /// Reads only the start and the end of a transcript — they can be tens of megabytes.
    private nonisolated static func parse(_ url: URL, modified: Date,
                                          live: [String: (pid: Int32, busy: Bool)]) -> ClaudeSession? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)
        let head = String(decoding: (try? handle.read(upToCount: 96_000)) ?? Data(), as: UTF8.self)
        var tail = ""
        if size > 96_000 {
            try? handle.seek(toOffset: size - min(size, 160_000))
            tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        }

        var cwd = "", entrypoint = "", firstPrompt = "", title = "", lastPrompt = ""
        func scan(_ text: String, isHead: Bool) {
            for line in text.split(separator: "\n") {
                // Cheap pre-filter before paying for JSON parsing
                let wanted = line.contains("\"ai-title\"") || line.contains("\"custom-title\"")
                    || line.contains("\"last-prompt\"")
                    || (isHead && (cwd.isEmpty || firstPrompt.isEmpty) && line.contains("\"type\":\"user\""))
                guard wanted, let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                switch json["type"] as? String {
                case "custom-title": if let t = json["customTitle"] as? String, !t.isEmpty { title = t }
                case "ai-title":     if let t = json["aiTitle"] as? String, !t.isEmpty { title = t }
                case "last-prompt":  if let t = json["lastPrompt"] as? String { lastPrompt = t }
                case "user":
                    if cwd.isEmpty { cwd = json["cwd"] as? String ?? "" }
                    if entrypoint.isEmpty { entrypoint = json["entrypoint"] as? String ?? "" }
                    guard firstPrompt.isEmpty, json["isMeta"] as? Bool != true,
                          let message = json["message"] as? [String: Any] else { continue }
                    var text = message["content"] as? String ?? ""
                    if text.isEmpty, let blocks = message["content"] as? [[String: Any]] {
                        text = blocks.first { $0["type"] as? String == "text" }?["text"] as? String ?? ""
                    }
                    if !text.isEmpty && !text.hasPrefix("<") { firstPrompt = text }
                default: break
                }
            }
        }
        scan(head, isHead: true)
        if !tail.isEmpty { scan(tail, isHead: false) }

        // Headless runs (the notch chat, scripts) are not conversations to come back to
        guard entrypoint != "sdk-cli" else { return nil }
        let raw = [title, firstPrompt, lastPrompt].first { !$0.isEmpty } ?? ""
        let clean = raw.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !clean.isEmpty else { return nil }

        let id = url.deletingPathExtension().lastPathComponent
        return ClaudeSession(id: id, title: String(clean.prefix(80)), cwd: cwd, modified: modified,
                             livePid: live[id]?.pid, busy: live[id]?.busy ?? false)
    }

    /// Claude Code keeps one small JSON file per running process in ~/.claude/sessions.
    private nonisolated static func liveSessions(home: URL) -> [String: (pid: Int32, busy: Bool)] {
        let dir = home.appendingPathComponent(".claude/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [:] }
        var result: [String: (pid: Int32, busy: Bool)] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = (json["pid"] as? NSNumber)?.int32Value,
                  let id = json["sessionId"] as? String,
                  kill(pid, 0) == 0 else { continue }
            result[id] = (pid, json["status"] as? String == "busy")
        }
        return result
    }

    private nonisolated static func tty(of pid: Int32) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "tty=", "-p", String(pid)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "??" ? nil : "/dev/" + name
    }
}
