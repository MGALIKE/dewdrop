import AppKit

// MARK: - TerminalJumper
// Brings the window that hosts the current Claude Code session to the front.
// nb-hook reports TERM_PROGRAM, the hosting app's bundle id, ITERM_SESSION_ID and the tty,
// which is enough to select the exact tab in Terminal and iTerm, and the right project
// window in VS Code-family editors. Other terminals are simply activated.

@MainActor
enum TerminalJumper {
    private static let knownTerminals = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "dev.warp.Warp-Stable", "com.github.wez.wezterm",
        "org.alacritty", "co.zeit.hyper",
    ]

    static func jump(to task: AgentTask?) {
        #if !APPSTORE
        let program = (task?.termProgram ?? "").lowercased()
        let bundleId = task?.termBundleId ?? ""
        let tty = sanitizedTTY(task?.termTTY)

        switch program {
        case "apple_terminal":
            if let tty { selectTerminalTab(tty: tty); return }
        case "iterm.app":
            let sessionId = sanitizedITermId(task?.termSessionId)
            if sessionId != nil || tty != nil { selectITermSession(id: sessionId, tty: tty); return }
        default:
            break
        }

        // VS Code, Cursor, Windsurf…: re-opening the project folder focuses its window.
        let isEditor = program == "vscode" || bundleId.lowercased().contains("vscode")
        if isEditor, !bundleId.isEmpty, let cwd = task?.sessionCwd, !cwd.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: appURL,
                                    configuration: .init(), completionHandler: nil)
            return
        }

        if !bundleId.isEmpty, activate(bundleId: bundleId) { return }

        // No session seen yet: any running terminal, else launch Terminal.
        for id in knownTerminals where activate(bundleId: id) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        #endif
    }

    /// Brings the tab attached to this tty forward, wherever it lives (Terminal first, then iTerm).
    static func focus(tty raw: String) {
        #if !APPSTORE
        guard let tty = sanitizedTTY(raw) else { return }
        let iTermRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.googlecode.iterm2" }
        let terminalRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Terminal" }
        if terminalRunning || !iTermRunning { selectTerminalTab(tty: tty) }
        else { selectITermSession(id: nil, tty: tty) }
        #endif
    }

    /// Reopens a finished Claude Code session: new terminal window, in its folder, `claude --resume`.
    static func resume(sessionId: String, cwd: String) {
        #if !APPSTORE
        guard sessionId.range(of: #"^[0-9a-fA-F-]{36}$"#, options: .regularExpression) != nil else { return }
        var command = "claude --resume \(sessionId)"
        if !cwd.isEmpty, FileManager.default.fileExists(atPath: cwd) {
            // Single-quote the path for the shell; an embedded quote becomes '\''
            command = "cd '\(cwd.replacingOccurrences(of: "'", with: "'\\''"))' && " + command
        }
        let useITerm = !NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Terminal" }
            && NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.googlecode.iterm2" }
        let script = useITerm
            ? """
              tell application id "com.googlecode.iterm2"
                  activate
                  set w to (create window with default profile)
                  tell current session of w to write text \(AppleScriptRunner.quoted(command))
              end tell
              """
            : """
              tell application id "com.apple.Terminal"
                  activate
                  do script \(AppleScriptRunner.quoted(command))
              end tell
              """
        AppleScriptRunner.run(script)
        #endif
    }

    /// Short label for buttons: "Terminal", "iTerm", "VS Code"…
    static func hostName(for task: AgentTask?) -> String {
        if let id = task?.termBundleId, !id.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return "terminal"
    }

    @discardableResult
    private static func activate(bundleId: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId })
        else { return false }
        if app.isHidden { app.unhide() }
        app.activate(options: [.activateAllWindows])
        return true
    }

    // MARK: - Exact tab selection

    private static func selectTerminalTab(tty: String) {
        let script = """
        with timeout of 6 seconds
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is \(AppleScriptRunner.quoted(tty)) then
                            if miniaturized of w then set miniaturized of w to false
                            set selected of t to true
                            set frontmost of w to true
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
                activate
                return "missing"
            end tell
        end timeout
        """
        AppleScriptRunner.run(script) { outcome in
            if outcome.output == nil { activate(bundleId: "com.apple.Terminal") }
        }
    }

    private static func selectITermSession(id: String?, tty: String?) {
        let script = """
        with timeout of 6 seconds
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (id of s is \(AppleScriptRunner.quoted(id ?? "-"))) or (tty of s is \(AppleScriptRunner.quoted(tty ?? "-"))) then
                                tell w to select
                                tell t to select
                                tell s to select
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
                activate
                return "missing"
            end tell
        end timeout
        """
        AppleScriptRunner.run(script) { outcome in
            if outcome.output == nil { activate(bundleId: "com.googlecode.iterm2") }
        }
    }

    // MARK: - Input hygiene (values arrive over the hook socket)

    private static func sanitizedTTY(_ raw: String?) -> String? {
        guard let raw, raw.range(of: #"^/dev/ttys?\d{1,4}$"#, options: .regularExpression) != nil else { return nil }
        return raw
    }

    /// ITERM_SESSION_ID looks like "w0t1p0:UUID" — AppleScript wants the UUID part.
    private static func sanitizedITermId(_ raw: String?) -> String? {
        guard let raw, let uuid = raw.split(separator: ":").last.map(String.init),
              uuid.range(of: #"^[0-9A-Fa-f-]{8,40}$"#, options: .regularExpression) != nil else { return nil }
        return uuid
    }
}
