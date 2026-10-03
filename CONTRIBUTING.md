# Contributing to Dewdrop

Thanks for wanting to help Dew grow up! 🫶 Issues and pull requests are welcome — bug reports with steps, new live activities, new props for Dew, better sounds, energy wins.

## Getting started

```bash
brew install xcodegen
git clone git@github.com:MGALIKE/dewdrop.git
cd dewdrop/NotchBuddy
xcodegen
open NotchBuddy.xcodeproj      # ⌘R, or:
xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build build SWIFT_OPTIMIZATION_LEVEL=-O
```

- **Never edit `NotchBuddy.xcodeproj` by hand.** Change `project.yml`, run `xcodegen`. New Swift files need an `xcodegen` run too.
- Build an optimised Debug (`SWIFT_OPTIMIZATION_LEVEL=-O`) when you want to look at animations: unoptimised, they stutter. Debug builds accept the `-debug…` launch arguments (see the README) so any view, state or prop can be put on screen without a real session.
- Liquid Glass needs the **macOS 26 SDK** to compile and macOS 26 to show; the app still runs on macOS 15 with Dew drawn in plain canvas, so keep every glass call behind `#available(macOS 26.0, *)`.

## Where things are

| | |
|---|---|
| `NotchBuddy/Sources/App/BotEngine.swift`, `DewBody.swift`, `BotProps.swift` | Dew: pose engine, drawing, props |
| `LiquidGlass.swift` | the island's glass, the motion tiers (`IslandMotion`), the shared `Beat` timer |
| `IslandWindowController.swift`, `IslandStateMachine.swift`, `IslandRootView.swift` | the panel, hover/open/close rules, pointer polling |
| `IslandViewContent.swift`, `HubCards.swift`, `SkillCards.swift`, `DynamicIsland.swift` | views, cards, pills, banners |
| `HookServer.swift`, `ClaudeHub.swift`, `ClaudeCodeCLI.swift`, `ClaudeService.swift` | Claude Code hooks, sessions, chat |
| `*Monitor.swift`, `*Poller.swift`, `TimerEngine.swift` | live activities and integrations |
| `design/icon/icon.swift`, `design/sounds/make.py` | the icon and the sounds are generated — change the script, not the files |
| `docs/DESIGN.md`, `docs/INTEGRATIONS.md`, `docs/AGENTS.md`, `docs/ENERGY.md` | how it behaves, how it talks to agents, what it costs |

## Rules of the house

- Swift 6, SwiftUI + AppKit, strict concurrency, **no third-party dependencies** unless there is really no other way. Dew is drawn in code; no Rive, Lottie or image sprites.
- Secrets go in the Keychain, never on disk or in git.
- No telemetry. No network calls except to services the user configured.
- **Never block Claude Code**: if the app doesn't answer, the hook exits right away.
- **Never write `~/.claude/settings.json`** (or Gemini's) without a dated backup, a merge that leaves other hooks alone, a diff on screen and the user's click.
- Never send an email or answer a permission request without an explicit click.
- Check UI from screenshots, not by driving the user's mouse or keyboard.

## Energy

Dewdrop sits on screen all day, so this is the rule that matters most ([docs/ENERGY.md](docs/ENERGY.md) has the long version):

- Only the visible island view is in the tree.
- Nothing redraws unless something changed. Ambient motion runs only while the pointer is on the island.
- Repeating motion goes through `Beat(perSecond) { tick in … }` — **never** `TimelineView`, `.repeatForever` or an implicit animation retriggered by a timer. Something that must move all day is a `CALayer`.
- No `NSHostingView` inside the island tree.
- Measure before and after, in the same situation: run with `-debugFrames 1` and read `pass=` in `~/Library/Logs/NotchBuddy/nb.log` (render passes per 5 s), alongside `top -l 4 -s 5 -pid $(pgrep -x Dewdrop) -stats pid,cpu`. Targets: about 1 % folded, 1–4 % open with the pointer away.

## Visual changes

Judge the island over both a colourful wallpaper and a white page: it is glass, and glass over white looks nothing like glass over black. For a PR, attach a screenshot or short GIF taken the same way; `-debugSamples 1` fills the island with sample sessions, clips and notes so nothing private ends up in it.

## Sounds

`design/sounds/make.py` writes all 28 WAVs (48 kHz, stereo, 16-bit) from a few synthesis primitives — `plip`, `bubble`, `bell`, `swoosh`, `splash`, `glide`. Keep the durations and peak levels of the sounds you replace (they are tuned against each other; `blip` is a whisper, `finish` the loudest), and run the script rather than editing a file.

## Pull requests

- One topic per PR. Say what changed and why; for anything visual, a picture.
- `xcodegen` must leave the project file as committed; the build must pass with no new warnings; `bash scripts/test-screen-geometry.sh` and `bash scripts/test-safe-links.sh` must pass.
- For anything that redraws, include the `pass=` numbers before and after.
- Be kind. The reviewer is a person and so is Dew.
