import AppKit

// MARK: - ClaudeCodeCLI
// Chat from the notch through the Claude Code CLI the user is already logged into:
// no API key, same account, same tools. Each message runs `claude -p` headless and the
// reply streams back line by line (stream-json). Follow-ups resume the same session.
//
// Anything that needs permission (edits, shell commands…) still goes through Coucou's
// PermissionRequest hook, so nothing runs without an explicit click in the notch.

@MainActor
final class ClaudeCodeCLI {
    static let shared = ClaudeCodeCLI()

    private var process: Process?
    private var sessionId: String?
    private var runToken = 0
    private var streamingId: UUID?
    private var gotResult = false

    private init() {}

    // MARK: - Availability

    static let binaryURL: URL? = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }()

    var isAvailable: Bool { Self.binaryURL != nil }

    /// Folder the chat works in: the last Claude Code session's project, else home.
    var workingDirectory: URL {
        if let cwd = AppState.shared.tasks.first(where: { $0.id == "integration_claude" })?.sessionCwd,
           !cwd.isEmpty, FileManager.default.fileExists(atPath: cwd) {
            return URL(fileURLWithPath: cwd)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Commands

    func newChat() {
        stop()
        sessionId = nil
    }

    /// Interrupts the running reply (keeps the session so the next message continues it).
    func stop() {
        runToken += 1
        process?.terminate()
        process = nil
        settle()
    }

    func send(query: String, context: PromptContext?, state: AppState) {
        guard let binary = Self.binaryURL else { return }
        stop()
        runToken += 1
        let token = runToken
        streamingId = nil
        gotResult = false
        state.chatBusy = true
        state.chatStatus = nil
        state.stateOverride = .thinking

        var prompt = query
        if sessionId == nil, let context {
            switch context {
            case .window(let app, let title, let url):
                prompt = "Context — the user is looking at \(app), window \"\(title)\"\(url.map { ", URL \($0)" } ?? "").\n\n\(query)"
            case .file(let name, let fileURL):
                prompt = "The user attached the file \(fileURL?.path ?? name). Read it if needed.\n\n\(query)"
            }
        }

        let p = Process()
        p.executableURL = binary
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                    "--permission-mode", "default", "--append-system-prompt", Self.notchPrompt]
        if let sessionId { args += ["--resume", sessionId] }
        p.arguments = args
        p.currentDirectoryURL = workingDirectory

        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["COUCOU_NOTCH"] = "1"   // nb-hook tags these events so they don't drive the Claude Code pill
        p.environment = env

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        let lines = LineBuffer()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let events = lines.append(data).compactMap(Self.parse).flatMap { $0 }
            guard !events.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ClaudeCodeCLI.shared.apply(events, token: token) }
            }
        }
        let errors = LineBuffer()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            _ = errors.append(data)
        }
        p.terminationHandler = { proc in
            let status = proc.terminationStatus
            // Let the last stdout chunk land first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated {
                    ClaudeCodeCLI.shared.finished(status: status, stderr: errors.text, token: token)
                }
            }
        }

        do {
            try p.run()
            process = p
            stdin.fileHandleForWriting.write(Data(prompt.utf8))
            try? stdin.fileHandleForWriting.close()
        } catch {
            fail("Couldn't start Claude Code: \(error.localizedDescription)")
        }
    }

    // MARK: - Stream handling

    private enum Event: Sendable {
        case session(String)
        case textStart
        case text(String)
        case tool(String)
        case result(text: String, sessionId: String?, isError: Bool)
        case usage(ClaudeUsage)
    }

    /// Plan limits as reported in the stream (`rate_limit_event`), if this line carries them.
    nonisolated static func usage(fromStreamLine line: String) -> ClaudeUsage? {
        guard line.contains("rate_limit_event"), let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["rate_limit_info"] as? [String: Any],
              let windows = info["unifiedWindows"] as? [String: Any],
              let five = windows["five_hour"] as? [String: Any],
              let fiveUsed = (five["utilization"] as? NSNumber)?.doubleValue else { return nil }
        let seven = windows["seven_day"] as? [String: Any]
        let resets = (five["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return ClaudeUsage(fiveHour: fiveUsed, sevenDay: (seven?["utilization"] as? NSNumber)?.doubleValue ?? 0,
                           fiveHourResets: resets, asOf: Date())
    }

    private nonisolated static func parse(_ line: String) -> [Event]? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return nil }
        switch type {
        case "rate_limit_event":
            return usage(fromStreamLine: line).map { [.usage($0)] }
        case "system":
            guard json["subtype"] as? String == "init", let id = json["session_id"] as? String else { return nil }
            return [.session(id)]
        case "stream_event":
            guard let event = json["event"] as? [String: Any], let kind = event["type"] as? String else { return nil }
            if kind == "content_block_start",
               (event["content_block"] as? [String: Any])?["type"] as? String == "text" {
                return [.textStart]
            }
            if kind == "content_block_delta", let delta = event["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta", let text = delta["text"] as? String {
                return [.text(text)]
            }
            return nil
        case "assistant":
            let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            let tools = content.filter { $0["type"] as? String == "tool_use" }.map { block in
                Event.tool(toolLabel(name: block["name"] as? String ?? "Tool",
                                     input: block["input"] as? [String: Any] ?? [:]))
            }
            return tools.isEmpty ? nil : tools
        case "result":
            return [.result(text: json["result"] as? String ?? "",
                            sessionId: json["session_id"] as? String,
                            isError: json["is_error"] as? Bool ?? false)]
        default:
            return nil
        }
    }

    /// "Reading AppState.swift", "Running git status"… shown under the reply while tools run.
    private nonisolated static func toolLabel(name: String, input: [String: Any]) -> String {
        func file(_ key: String) -> String? {
            (input[key] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        }
        switch name {
        case "Read":             return "Reading \(file("file_path") ?? "a file")"
        case "Write":            return "Writing \(file("file_path") ?? "a file")"
        case "Edit", "MultiEdit": return "Editing \(file("file_path") ?? "a file")"
        case "Bash":             return "Running \(String((input["command"] as? String ?? "a command").prefix(48)))"
        case "Glob", "Grep":     return "Searching \(input["pattern"] as? String ?? "the project")"
        case "WebSearch":        return "Searching the web"
        case "WebFetch":         return "Fetching a page"
        case "Task", "Agent":    return "Delegating to a subagent"
        default:                 return name
        }
    }

    private func apply(_ events: [Event], token: Int) {
        guard token == runToken else { return }
        let state = AppState.shared
        for event in events {
            switch event {
            case .session(let id):
                sessionId = id
            case .usage(let usage):
                ClaudeHub.shared.report(usage)
            case .textStart:
                // A new text block after tool calls: keep it visually apart from the previous one
                if let i = streamingIndex(in: state), !state.chatHistory[i].content.isEmpty {
                    state.chatHistory[i].content += "\n\n"
                }
            case .text(let chunk):
                state.chatStatus = nil
                if let i = streamingIndex(in: state) {
                    state.chatHistory[i].content += chunk
                } else {
                    let message = ChatMessage(role: .assistant, content: chunk)
                    streamingId = message.id
                    state.chatHistory.append(message)
                }
            case .tool(let label):
                state.chatStatus = label
                if state.pendingApproval == nil { state.stateOverride = .working }
            case .result(let text, let id, let isError):
                gotResult = true
                if let id { sessionId = id }
                if let i = streamingIndex(in: state) {
                    let trimmed = state.chatHistory[i].content.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.chatHistory[i].content = trimmed.isEmpty ? text : trimmed
                } else if !text.isEmpty {
                    state.chatHistory.append(ChatMessage(role: .assistant, content: text))
                }
                process = nil
                settle()
                if isError {
                    state.stateOverride = .error
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        if AppState.shared.stateOverride == .error { AppState.shared.stateOverride = nil }
                    }
                } else {
                    NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                    // Answer landed while the island was folded: a sound and a peek
                    if state.mode != .expanded {
                        SoundEngine.shared.play("finish")
                        NotificationCenter.default.post(name: .hookReveal, object: nil)
                    }
                }
            }
        }
    }

    private func streamingIndex(in state: AppState) -> Int? {
        guard let streamingId else { return nil }
        return state.chatHistory.lastIndex { $0.id == streamingId }
    }

    private func finished(status: Int32, stderr: String, token: Int) {
        guard token == runToken, !gotResult else { return }
        process = nil
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        appendAppLog("nb.log", "claude -p exited \(status): \(detail.prefix(200))")
        if detail.localizedCaseInsensitiveContains("login") || detail.localizedCaseInsensitiveContains("api key") {
            fail("Claude Code isn't signed in. Run `claude` in a terminal once, then try again.")
        } else {
            fail(detail.isEmpty ? "Claude Code stopped unexpectedly (exit \(status))." : String(detail.prefix(240)))
        }
    }

    private func fail(_ message: String) {
        let state = AppState.shared
        settle()
        state.chatHistory.append(ChatMessage(role: .assistant, content: message))
        state.stateOverride = .error
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if AppState.shared.stateOverride == .error { AppState.shared.stateOverride = nil }
        }
    }

    private func settle() {
        let state = AppState.shared
        state.chatBusy = false
        state.chatStatus = nil
        if state.stateOverride == .thinking || state.stateOverride == .working { state.stateOverride = nil }
    }

    // MARK: - Prompt

    private static let notchPrompt = """
    You are being used from Dewdrop, a small chat panel in the notch of the user's Mac, kept by Dew, a little glass drop. \
    The panel is narrow and short: answer in a few plain sentences, most important thing first. \
    No headings, tables or long lists; inline `code` and short snippets are fine. \
    Reply in the user's language. If a task is long, do it and then summarise what you did in two or three sentences.
    """
}

/// Splits a byte stream into complete lines. Shared between the pipe's reader thread and main.
private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private var all = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.withLock {
            pending.append(data)
            if all.count < 16_384 { all.append(data) }
            var lines: [String] = []
            while let nl = pending.firstIndex(of: 0x0A) {
                lines.append(String(decoding: pending[pending.startIndex..<nl], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...nl)
            }
            return lines
        }
    }

    var text: String { lock.withLock { String(decoding: all, as: UTF8.self) } }
}
