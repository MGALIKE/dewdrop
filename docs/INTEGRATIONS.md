# Dewdrop — integrations

How the island talks to the things it shows. For third-party agents and their own pills, see [AGENTS.md](AGENTS.md).

## 1. Claude Code

```
claude (any terminal, VS Code, Cursor…)
  └─ hook "command" ─► ~/.claude/coucou/nb-hook  (shell wrapper → nb-hook.py)
                         └─ Unix socket ─► Dewdrop.app
                         ◄─ decision (PermissionRequest only)
```

- **Socket:** `~/Library/Application Support/NotchBuddy/nb.sock`, folder `0700`, socket `0600`, connections from the same user only (`getpeereid`), 1 MiB and 5 s per message, 32 concurrent connections.
- **The relay** reads the hook's JSON on stdin, adds the terminal's context (`TERM_PROGRAM`, `ITERM_SESSION_ID`, `TERM_SESSION_ID`, the host app's bundle identifier, the tty found by walking up the parent processes, `cwd`) and forwards it. **If the app does not answer, the relay exits 0 without writing anything** — Claude Code carries on as if no hook existed. The app can be closed, crashed or slow; a session is never blocked.
- **Installing the hooks** (Settings → Claude Code → Install hooks): read `~/.claude/settings.json` (create it if missing), copy it to `settings.json.bak-YYYYMMDD-HHMM`, merge Dewdrop's entries without touching anyone else's, show the diff, write only after you confirm. "Remove hooks" takes out only Dewdrop's entries. Gemini CLI and Antigravity have the same flow for their own settings files.

### Events

| Hook | In the island |
|---|---|
| `SessionStart` | the session's pill appears (named after its folder), `idle` |
| `UserPromptSubmit` | `thinking`; the start of the prompt in the ticker |
| `PreToolUse` | `working`; tool and target in the ticker ("Edit Invoice.swift", "Bash npm test") |
| `PostToolUse` / `PostToolUseFailure` | ticker updated; a failure stays `working` |
| `PermissionRequest` | the `approval` view, see below |
| `Notification` | a usage limit → `ratelimit`; waiting for input → `question` |
| `Stop` | `finished` for 5.2 s, with the last useful line of the reply as summary |
| `StopFailure` | `error` |
| `SubagentStart` / `SubagentStop` | a "sub-agent" step in the ticker |
| `SessionEnd` | the pill goes away |

Events carrying `coucou_origin: "notch"` come from the island's own chat sessions and do not drive the Claude Code pill.

### Approving from the notch

On `PermissionRequest` the relay waits for the app's decision and writes the hook's decision JSON (`hookSpecificOutput.decision.behavior` = `allow` or `deny`) to stdout. The decision is only ever **your click** on Allow or Deny (or Y / N while the view is open). No answer before the timeout, or the app closed → the relay writes nothing and the terminal asks as usual; if you answer there, the island drops its card at the session's next event. The hook's timeout in `settings.json` is set long enough for you to get to the notch.

### Jumping to the terminal

Click a session and the island brings its window to the front:

| What the hook captured | Action |
|---|---|
| Terminal + tty | AppleScript: select the tab whose tty matches, activate |
| iTerm + `ITERM_SESSION_ID` | AppleScript: select the session, activate |
| VS Code, Cursor, Windsurf | reopen the project folder, which focuses its window |
| Ghostty, Warp, WezTerm, kitty… | activate the app |
| a finished session | resume it (`claude --resume`) in a new terminal |

macOS asks for the Automation permission the first time, per app.

### Sessions and usage

The Claude Code card lists recent sessions from `~/.claude/sessions` and `~/.claude/projects` (title, folder, when, whether a `claude` process still owns it), and your 5-hour and 7-day usage as two gauges. The usage comes with every chat reply when the chat runs through the CLI, from the Claude desktop app's own log when it is open, or from a one-line request to the cheapest model when you tap the meter — never on a timer.

## 2. Chat

Two backends, picked in Settings:

- **Claude Code CLI** (default when `claude` is on your PATH): `claude -p --output-format stream-json`, so the chat uses your subscription and no key is stored. The island's own sessions are tagged so the hooks do not show them as work. A short system prompt asks for answers that fit the notch.
- **Anthropic API**: `POST /v1/messages` with your key from the Keychain, the model chosen in Settings (the list comes from `/v1/models` on your account; a fallback list and a free-text field cover the rest) and the server-side web search tool. API errors are shown as their message, not raw JSON.

While waiting: `searching`, with a shimmering line. The answer opens the `result` view (`finished`, `proud`, `finish`). "Open" only follows `http`/`https` links; anything else stays disabled.

## 3. Files dropped on the notch

Native drag and drop (`fileURL`). The files are copied into `~/Library/Application Support/NotchBuddy/inbox/` (that is the `uploading` phase) and go on the Shelf. From `choose`: **ask a question about it** (PDFs as a `document` block, images as `image`, text and code up to 200 KB as text — the CLI backend gets the path), **send by email**, or **open the shelf**.

## 4. Attaching a window

Drop Dew on another app's window: the window under the pointer is found with `CGWindowListCopyWindowInfo`, a halo is drawn around it, and its screenshot (ScreenCaptureKit) plus — for Safari, Chrome, Arc and Brave — the active tab's URL and title go into the prompt as context. Screen Recording and Automation permissions are asked the first time; without them the chat continues without the capture or the URL and says so.

## 5. Mail

The `mail` view sends through Mail.app with AppleScript, **only on your click on Send**: a new outgoing message with the recipient, subject (prefilled with the file name), optional line of text and the attachment. Success → a `note` ("Mail sent to …", `wink`, `send`); failure → `error` with the reason.

## 6. Live activities

| Pill | Where the data comes from | Cost when the pill is on |
|---|---|---|
| **Music** | the players' distributed notifications (Music, Spotify) — no polling; artwork and seeking through AppleScript | nothing between track changes |
| **Timer** | the app's own countdowns (`TimerEngine`), persisted in `UserDefaults` | one tick a second while a card shows it |
| **System** | `host_statistics`, memory, battery and thermal state; charger and battery-level changes come from IOKit notifications | a sample every 10 s folded, every 2 s while the card is open |
| **Shelf** | the files you dropped | — |
| **Clipboard** | the pasteboard's change counter, compared once a second; concealed and transient types are skipped, text only, 20 KB max | one integer compare a second |
| **Notes** | your own notes, in `UserDefaults` | — |
| **Weather** | Open-Meteo for your location, every 30 minutes | — |
| **Keep awake** | an IOKit power assertion while on | — |

## 7. Services (optional pills)

Each is a small poller with its key in the Keychain and a pill that appears only when configured. Intervals: n8n every 15 s, Stripe and Vercel every 30 s, Resend every 60 s, GitHub, Notion and Cal.com every 5 minutes. They pause when the pill is off.

- **n8n** — recent executions from the public API (`/api/v1/executions`, `/api/v1/workflows`); a running execution is `working`, a new failure an `error` card with the failing node, a success a brief `finished` on the pill. "Open in n8n" opens the execution in your browser.
- **Stripe** — balance and recent charges; a new payment slides in and the balance counts up.
- **GitHub** — your repositories, most recently pushed first, with their latest activity.
- **Vercel** — deployments and their state.
- **Resend** — the latest emails sent through your account and their delivery state.
- **Notion** — recently edited pages.
- **Cal.com** — upcoming bookings.

## 8. Permissions macOS will ask for

| Permission | Why | When |
|---|---|---|
| Automation → Mail | sending mail | first send |
| Automation → Terminal / iTerm / Music / Spotify / browser | jumping to a tab, controlling playback, reading the active URL | first use |
| Screen Recording | the window you attach | first attach |
| Accessibility | the front window's title for context | first attach |

Nothing else. The pointer is polled, not captured; keys stay in the Keychain; there is no telemetry.
