import Foundation

// MARK: - AppleScriptRunner
// Runs short AppleScripts through /usr/bin/osascript on a private serial queue, so a slow
// or unresponsive target app can never stall the island. Results come back on the main actor.

enum AppleScriptRunner {
    struct Outcome: Sendable {
        let output: String?     // trimmed stdout, nil on failure
        let denied: Bool        // user refused Automation access for the target app
    }

    private static let queue = DispatchQueue(label: "fr.louisraille.NotchBuddy.applescript", qos: .userInitiated)

    private final class ProcessBox: @unchecked Sendable {
        let process = Process()
    }

    static func run(_ source: String,
                    completion: (@MainActor @Sendable (Outcome) -> Void)? = nil) {
        queue.async {
            let box = ProcessBox()
            let out = Pipe(), err = Pipe()
            box.process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            box.process.arguments = ["-e", source]
            box.process.standardOutput = out
            box.process.standardError = err

            var outcome = Outcome(output: nil, denied: false)
            do {
                try box.process.run()
                // Safety net: the first run may sit behind the Automation consent prompt.
                DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                    if box.process.isRunning { box.process.terminate() }
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                box.process.waitUntilExit()
                let errText = String(data: errData, encoding: .utf8) ?? ""
                if box.process.terminationStatus == 0 {
                    let text = (String(data: outData, encoding: .utf8) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    outcome = Outcome(output: text, denied: false)
                } else {
                    outcome = Outcome(output: nil, denied: errText.contains("-1743"))
                    appendAppLog("nb.log", "AppleScript failed: \(errText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))")
                }
            } catch {
                appendAppLog("nb.log", "AppleScript could not start: \(error.localizedDescription)")
            }

            guard let completion else { return }
            let result = outcome
            Task { @MainActor in completion(result) }
        }
    }

    /// Escapes a Swift string for use inside an AppleScript string literal.
    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
