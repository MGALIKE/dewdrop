# Dewdrop — third-party agent integration

(The hook relay, its socket and the payload fields keep the names they had in Coucou — `nb-hook`, `coucou_agent`, `coucou_origin` — so agents written for either app work with both.)

Any tool that can write to a Unix domain socket can send events to Dewdrop and have its own pill next to Claude Code.

## The `coucou_agent` field

Add the optional field `coucou_agent` to any hook JSON payload. Dewdrop creates a pill labelled with the agent name and routes all of that agent's events to it.

**Validation:** the name must match `^[a-z0-9-]{1,24}$` (lowercase letters, digits and hyphens, 1–24 characters). An absent or invalid name routes the event to the Claude Code pill instead.

## Hook command

Configure your tool to call the Dewdrop relay with `--agent <your-name>` after the hook executable:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "type": "command", "command": "/path/to/nb-hook --agent my-tool" }
    ]
  }
}
```

The shell wrapper passes `"$@"` to the Python relay, which extracts the agent name and injects it into the payload before forwarding to Dewdrop.

## Payload format

The relay adds `coucou_agent` to the JSON it forwards. You can also add it yourself if you talk to the socket directly:

```json
{
  "hook_event_name": "UserPromptSubmit",
  "session_id": "my-session-1",
  "coucou_agent": "my-tool",
  "prompt": "Running task…"
}
```

Send newline-terminated JSON to the socket: `~/Library/Application Support/NotchBuddy/nb.sock` (same user only; 1 MiB and 5 s per message).

## Supported events

All standard Claude Code hook events are supported, **except `PermissionRequest`**:
approval cards are not yet implemented for third-party agents (only Claude Code gets
one). A `PermissionRequest` from an external agent is answered immediately with no
decision, so the relay writes nothing and the agent re-asks in its terminal.
Approval cards for other agents are on the list.

The pill lifecycle:

| Event | Effect |
|---|---|
| `SessionStart` | Creates the pill (if absent), sets state to idle |
| `UserPromptSubmit` | State → thinking; prompt shown in ticker |
| `PreToolUse` | State → working; tool label shown in ticker |
| `PostToolUse` / `PostToolUseFailure` | State → working |
| `Notification` | Rate-limit or question state if applicable |
| `Stop` | State → finished for 5 s, then pill removed |
| `StopFailure` | State → error |
| `SessionEnd` | Pill removed |
| `SubagentStart` / `SubagentStop` | Step added to ticker |

## Real-world examples

### Gemini CLI

Dewdrop supports Gemini CLI out of the box via **Settings → Gemini CLI → Install hooks**.
The installer writes to `~/.gemini/settings.json` and uses `--agent gemini` so
Gemini sessions get their own pill. The relay translates Gemini event names to canonical
Dewdrop events automatically.

| Gemini CLI event | Canonical event |
|---|---|
| `BeforeTool` | `PreToolUse` |
| `AfterTool` | `PostToolUse` |
| `BeforeAgent` | `UserPromptSubmit` |
| `AfterAgent` | `Stop` |

`AfterModel` is not installed — it fires on every response chunk and would flood the island.

### Antigravity — `agy`

Dewdrop supports Antigravity out of the box via **Settings → Antigravity → Install hooks**.
The installer writes to `~/.gemini/config/hooks.json` (timeouts in seconds) and uses
`--agent antigravity`. The relay translates `toolCall.name` / `conversationId` to the
island's `tool_name` / `session_id`.

| Antigravity event | Canonical event |
|---|---|
| `PreInvocation` | `UserPromptSubmit` |
| `PreToolUse` | `PreToolUse` |
| `PostToolUse` | `PostToolUse` |
| `PostInvocation` | `PostToolUse` |
| `Stop` | `Stop` |

### Any other tool

Follow the generic pattern: call `nb-hook --agent <your-name> <EventName>` and let the relay
forward the event.

## Quick test

With Dewdrop running:

```sh
echo '{"hook_event_name":"UserPromptSubmit","session_id":"t1","prompt":"hello","coucou_agent":"demo"}' \
  | /bin/sh ~/Library/Application\ Support/NotchBuddy/nb-hook --agent demo
```

A "demo" pill should appear in the island.
