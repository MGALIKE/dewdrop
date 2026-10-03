# Dewdrop — how it behaves

What the island does, when, and why. Measurements are in macOS points. Where a number matters, the file that holds it is named; the code wins over this page.

## 1. The window

- A borderless `NSPanel` (`.borderless, .nonactivatingPanel`), transparent, above the menu bar, on every Space and over full-screen apps. It never takes focus except while a text field of the island is active.
- **Clicks pass through.** The transparent area never swallows a click: the panel toggles `ignoresMouseEvents` depending on whether the pointer is inside the island's shape (plus 6 pt). The pointer is polled, not captured, and no permission is needed — see [ENERGY.md §6](ENERGY.md) for how little that polling costs when the mouse is still.
- The notch is detected from `NSScreen.safeAreaInsets` and the auxiliary top areas; the island hugs it. On a Mac without a notch (desktop, external display, lid closed) a small black bar sits at the top centre of the main screen instead, capped at the menu bar's height, and the hover zone does not spill below the bar. Open views keep their 640 pt width everywhere.
- Shape: black, square top corners (it melts into the screen edge), rounded bottom corners, two small concave "ears" at the top so the outline flows into the bezel. Once open, the body is Liquid Glass with a slowly drifting mesh of the current state's colour behind it.

## 2. Modes

| Mode | Width | Height | Dew | Pills |
|---|---|---|---|---|
| `hidden` | the notch | the notch | — | — |
| `peek` | notch + 64 | the notch | small, beside the notch | — |
| `compact` | notch + 104 | the notch | small, follows the pointer with its eyes | a 2×2 grid of tiny Dews in the right ear |
| `expanded` | 640 | per view, 150–240 | large, in the view's card | pills or a column, per view |

The state machine behind it (`IslandStateMachine.swift`) has four states — `hidden`, `petit` (compact), `home` (open), `coucou` (the launch greeting) — and the delays live in it: open → compact after 15 s without activity, compact → hidden after 60 s when nothing is running.

## 3. Rules

1. **Nothing running, nobody near** → `hidden`.
2. **Pointer on the notch** → the island opens on the overview (or `empty` when there is no session). Pointer gone during the peek → back to hidden.
3. **Something running** → `compact`: thin, Dew visible, eyes on the pointer anywhere on the screen.
4. **Hover in compact** → open after a short delay; a click on Dew opens at once.
5. **Auto-close**: an open island folds after `autoCloseInterval` (10, 15 or 30 s in Settings; 15 by default) without activity on it. During the last seconds a thin line at the bottom centre counts down. A click anywhere else, or Escape, folds it immediately. Pinned views (approvals, uploads) don't auto-close.
6. **Away** (no pointer movement for `absenceInterval`, 3 min by default) → `hidden` even with sessions running; the first movement brings `compact` back.
7. **Alerts** (permission request, question, error) open the island on their view by themselves, even when you are away, and keep it open until answered.
8. **Finished**: the island shows the `finished` view for 5.2 s, then lets go.
9. Several alerts: a queue, one at a time, in order of arrival.
10. **Focus**: the large Dew is the focused task — the latest alert, else the first one working, else the pill you clicked. Everything else is a mini Dew.

## 4. Motion

- Opening: a spring (`response 0.5, damping 0.72`) with a slight overshoot, about 0.5 s; closing: a 0.34 s ease without overshoot. Width, height, corner radius and Dew's size and position move together; the content is laid out once at its final size and revealed by the island's shape (so the spring gets every frame).
- Mini Dews travel from the grid to the pills to the column without disappearing (one shared element), 35 ms apart.
- Dew blinks when the island opens. Sounds `open` / `close`.
- Two tiers of ambient motion ([ENERGY.md §5](ENERGY.md)): with the pointer on the island, Dew breathes and dances, the pill Dews bob, the colour drifts and the current task's text shimmers; with the pointer away — or parked on the island for five seconds — all of that rests, and only what carries information keeps moving (badge dots, equalizer bars, pulsing session dots, which are Core Animation layers).

## 5. Views (open island, 640 wide)

A 34 pt header (home, chat and "+" on the left; weather, settings and sound on the right), then the view. Cards have a 20 pt radius. In views other than the overview the mini Dews line up in a column on the right.

| View | What's in it |
|---|---|
| `overview` | left: the focused task's card — Dew, name, state, the last actions or (for Claude Code) the usage gauges and recent sessions; right: the pills of everything else |
| `empty` | "Nothing running" and a way to ask Claude |
| `approval` | agent, what Claude Code wants to run, the command, **Deny / Allow** (N / Y) |
| `question` | a question from the agent and how to answer it |
| `error` | the tool, the error, retry / open |
| `finished` | the summary, open the terminal, OK |
| `confused` | Dew is dizzy after three slaps |
| `upload` → `uploading` → `choose` | drop zone → Dew as a glass box swallowing the file, then a small drop riding the progress bar → "file is ready": ask a question, send by email, open the shelf |
| `mail` | To, Subject, optional message, Send |
| `prompt` → `searching` → `result` | the chat: context chip + field; Dew searches; the answer with Open / Copy / Close |
| `note` | a one-line confirmation that closes itself |
| `settings` | sound, auto-close, which backend answers the chat, link to the full Settings window |
| `greeting` | the launch hello (4.6 s) |
| `toast` | a narrow Dynamic-Island banner under the notch: track change, timer, charger, volume/brightness, "Claude finished" |

Cards for the live activities (Music, Timer, System, Shelf, Clipboard, Notes, Weather) take the left card's place when their pill is focused.

## 6. Dew

Dew is a bead of the island's own glass: a circle with two tangents meeting at a rounded tip (`BotEngine.dropPath`). In the open island the body is a real `glassEffect` between two canvases — hands and liquid underneath, light, eyes, badge and props on top — and the liquid inside takes the colour of the state. Beside the notch and in the pills, Dew is drawn entirely in canvas. Eyes are projected on a sphere (yaw, pitch, roll) and clipped by the silhouette, which is what makes the roll-through animations work; they follow the pointer with a little lag, blink every 2–5 s, double-blink now and then.

### States

| State | Colour | Eyes | Badge | Also |
|---|---|---|---|---|
| `idle` | clear | pills | — | breathes |
| `working` | blue `#3B9EFF` | pills | pulsing "•••" | wears a laptop |
| `thinking` | violet `#8B5CF6` | pills | "•••" | looks up and away |
| `searching` | indigo `#6366F1` | pills | "•••" | eyes sweep; magnifier |
| `approval` | amber `#F5A524` | wide | "!" | small hops |
| `question` | cyan `#22D3EE` | pills | "?" | head tilted |
| `error` | red `#F4505E` | flat | red dot | shakes; bandage |
| `finished` | green `#34D399` | happy arcs | green dot | full roll and sparkles |
| `ratelimit` | orange `#FB923C` | tired | orange dot | sweat drops |
| `sleeping` | grey | closed | — | slow breathing, rising "z" |
| `dizzy` | pink `#F472B6` | spirals | — | double roll |

### Emotes

`love` (hearts, after the pointer rests on Dew for 1.9 s), `surprised` (when picked up), `proud` (a result arrived), `wink` (mail sent, window attached), `yawn` (just before sleeping), `happy` (a decision, a swallowed file), `annoyed` (a slap).

### Props

Put on by the moment, not by hand (`AppState.botProps`): laptop while working, magnifier while searching, bandage on error, headphones while music plays, party hat when a timer rings, mug while keep-awake is on, nightcap from 23:00 to 6:00, sunglasses in bright light or clear daytime weather, umbrella (and rain) when it rains, scarf (and snow) when it snows or is cold.

## 7. Touching Dew

- **Hover** (open island): blink, eyes grow, sound `hover`. Still for 1.9 s → `love`.
- **Click** in compact → opens. **Click** in the open island → a slap: squash, `annoyed` for 0.8 s, sounds `slap` + `annoyed`. **Three clicks within 1.7 s** → `dizzy` for 3.3 s and the `confused` view.
- **Drag Dew** (more than a few points): a floating Dew follows the pointer (`surprised`, `pop`). Dropped on another app's window → that window is attached as context and the prompt opens (`attach`, `wink`). Dropped elsewhere → Dew springs back.
- **Drag a file** onto the notch → `upload`: Dew morphs into a glass box and looks at the file. Drop → the file is pulled in (`gulp`), progress (`tick`), `approve`, then `choose`.

## 8. Sounds

28 short WAVs (48 kHz stereo) through preloaded `AVAudioPlayer`s, generated by `design/sounds/make.py`. Switchable in the header and in Settings; the volume slider is deliberately quiet.

| Moment | Sound |
|---|---|
| hello at launch | `greet` (and `peek`) |
| open / close | `open` / `close` |
| hover Dew / small UI click | `hover` / `blip` |
| slap / annoyed / dizzy | `slap` / `annoyed` / `dizzy` |
| working / thinking / searching | `work` / `think` / `search` |
| permission / question / error / rate limit | `approval` / `question` / `error` / `rate` |
| finished | `finish` |
| decision confirmed, upload done | `approve` |
| file swallowed / progress | `gulp` / `tick` |
| send (prompt, mail) / window attached | `send` / `attach` |
| emotes | `love`, `pop`, `proud`, `wink`, `yawn`, `sleep` |

Silent updates (the task ticker, pills changing state without an alert) make no sound.

## 9. Menu bar and Settings

A small template glyph of Dew in the menu bar: Open Dewdrop, Settings…, Quit.

Settings: Claude Code hooks (install / remove, with the backup-merge-diff-confirm flow), the chat backend (Claude Code CLI on your subscription, or an Anthropic API key in the Keychain and a model picked from your account), the live activities and integrations you want as pills (and their keys), sound and volume, auto-close, launch at startup, the show-island shortcut.
