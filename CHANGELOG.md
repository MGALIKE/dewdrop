# Changelog

## Fork (Dewdrop) — unreleased

- Dew: a new character made of real Liquid Glass, with a liquid inside that takes Claude's state colour; new greeting and file-drop animations; props refitted
- Energy: event-driven character canvas, motion tiers, one shared `Beat` timer instead of `TimelineView` for all repeating motion, pointer polling that stops when the pointer rests, monitors that exist only while the island is open — folded ~1 %, open with the pointer away 1–4 % (was 12–15 % and ~50 %)
- Sessions from any terminal (not only VS Code), with a jump back to the exact tab
- Chat through the Claude Code CLI (uses the subscription; no API key needed)
- Live-activity pills: Music, Timer, System, Shelf, Clipboard, Notes; compact Dynamic-Island banners when folded; Claude hub (usage, recent sessions)
- Liquid Glass styling of the island; weather in the header; keep-awake
- Removed from this fork: the Windows port and the upstream website pages

## Upstream — unreleased (as of the fork point)

- Compact island on screens without a notch (#22) — thanks @Kamasoutra
- Only web links (http/https) open from the notch; other kinds of links from Claude or integrations are ignored (#16) — thanks @Cris1670
- Hook socket limited to your own user account, with size and time limits; logs no longer keep commands, n8n data or full URLs, and stay under 1 MB (#16) — thanks @Cris1670 and @Vignesh-Thangamariappan
- The island always reopens after folding, and Settings opens below it, resizable — thanks @rouderz
- Choose the Claude model for the chat in Settings; the list comes from your Anthropic account, and Claude Sonnet 4.6 stays the default — thanks @rouderz
- Windows build artifacts are now downloadable from a manual CI run — thanks @MysJofR
- Any agent can talk to Mochi: tag a hook payload with `coucou_agent` (e.g. `nb-hook --agent my-agent`) and it gets its own pill in the island (#7, #9) — thanks @lacatu5
- Gemini CLI and Antigravity (agy) hook support on macOS: install from Settings and their sessions show up in the island — thanks @corefusiion
