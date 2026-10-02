# Energy

Dewdrop sits on screen all day. This page is the account of what it costs, how that is measured, what was found along the way, and the rules the code follows so it stays that way.

## The number

The user's yardstick is **Activity Monitor → Energy → Energy Impact**. On an Apple-silicon Mac that column tracks CPU time closely, so the working metric is the app's CPU % of one core from `top`:

```sh
top -l 4 -s 5 -pid $(pgrep -x Coucou) -stats pid,cpu,csw,power
```

Three to four 5-second samples, with the pointer away from the island, and the frame log (below) read alongside each one so a stray hover is not mistaken for a regression. WindowServer is sampled too: glass is composited there, and that cost does not show in the app's own row.

## Where it stands

| Situation | CPU | Render passes / s | Wake-ups |
|---|---|---|---|
| Folded, nobody touching the Mac | ~1 % | ~2 (a blink now and then) | ~1 pointer check, 1 heartbeat, 1 clipboard check, system stats every 10 s |
| Folded, pointer moving elsewhere | ~1 % | ~2 | 20 pointer checks/s |
| Open, idle, pointer away | 1–2 % | 3–5 (breathing) | 10 pointer checks/s |
| Open while Claude works, pointer away | 3–4 % | ~8 (badge dots at 6 fps + blinks) | " |
| Pointer on the open island, moving | 10–13 % | 30 | 60 pointer checks/s |
| Pointer parked on the open island (5 s) | ~3 % | 3–5 | 10/s |
| WindowServer, island open | +10 % | | glass composition, not in the app's row |

The same situations at the start of this fork: folded 12–15 %, open with the pointer away about 50 %, open with the pointer on it about 50 %. After the first pass (frame-rate tiers): folded 1–2 %, open 3–6 %, lively 20 %. After Dew and the second pass: the table above.

## What was found

### 1. Sixteen views alive at once
Every island view (overview, prompt, approval, settings…) stayed in the SwiftUI tree at opacity 0, and one of them ticked a 120 Hz timeline forever. **Fix:** only the visible view is in the tree.

### 2. A canvas that never slept
The character was drawn by `TimelineView(.animation)` at the display's rate whether or not anything changed. **Fix:** the canvas is event-driven. It draws while the engine reports motion (`isAnimating`: a tween, a look, particles, a slosh) and stops 100 ms after it settles. A slow heartbeat asks `wantsWake` whether something is due (a blink, a glance at the pointer), and state changes wake it directly.

### 3. Each render pass costs the same, whatever changed
Measured with `-debugBounce 1` and `sample`: a render pass of the island's `NSHostingView` costs 2.5–5 ms of main-thread time — graph update, display list, Core Animation commit — almost independently of how much is drawn. The Canvas drawing itself is a small fraction. So the lever is the **number of passes**, never the complexity of a frame. Everything below follows from this.

### 4. `TimelineView` keeps the display link running between entries
This was the surprise of the second pass. The badge's three dots ticked at 6 fps through `TimelineView(.beat(6))`, and the window made **226 render passes a second** (`pass=1131` per 5 s in the frame log) while the character drew 8 frames. With a timeline entry pending, SwiftUI keeps the window's display link alive and runs a (mostly empty, still ~1 ms) pass on every screen refresh. Open island while Claude works: 15 % CPU.

**Fix:** no `TimelineView` for anything that repeats. `Beat(perSecond, paused:) { tick in … }` ([LiquidGlass.swift](../NotchBuddy/Sources/App/LiquidGlass.swift)) is driven by **one shared `DispatchSourceTimer`** on one clock grid; every `Beat` due at a tick is moved in the same run-loop turn, so however many there are, the island makes one pass. Result: 41 passes per 5 s, 3–4 % CPU. The remaining `TimelineView(.animation)` uses are short sequences that end (the greeting, the file drop, confetti).

### 5. Frame-rate tiers
Dew runs at 30 fps in the open island and 20 beside the folded notch while something moves, 6 fps for a ticking badge, 0 otherwise. The pill characters run at 15 fps and only while the pointer is on the island. Breathing, dancing, colour drift and text shimmer belong to the **lively** tier: pointer on the island, or a short boost after it opens or Dew reacts. A pointer that rests on the island for five seconds drops the tier again. Things that must move all day (equalizer bars, pulsing dots) are `CALayer`s with `CAAnimation`s in [LayerAnimations.swift](../NotchBuddy/Sources/App/LayerAnimations.swift): the render server animates them and the app makes no passes at all.

### 6. Polling a pointer that isn't moving
Hover detection polled `NSEvent.mouseLocation` 20 times a second forever (60 near the notch). **Fix:** when the island is folded and the pointer has not moved for two seconds, polling stops; a global mouse-moved monitor (free until the mouse moves) restarts it, with one look a second as a safety net. Over the open island a resting pointer is polled at 10 Hz instead of 60. The heartbeat relaxes from 5 Hz to 1 Hz at the same time.

A detail worth knowing: a global `NSEvent` monitor does not see events aimed at the app itself, and an accessory app launched by hand with `open` is the *active* app until the user clicks elsewhere. The safety poll runs at 4 Hz in that case.

### 7. Monitors that woke the app for everyone's clicks and keys
The click-away and Escape monitors were global and permanent, so every click and key press on the Mac woke the app. They now exist only while the island is open. The show-island shortcut monitor exists only while that setting is on (off by default).

### 8. Things that looked cheap and weren't
- Nesting an `NSHostingView` inside the island's SwiftUI tree (tried for a Core Animation dance): every inner frame re-laid-out the outer tree and tripled the cost.
- A conic gradient in the glass rim was rasterised on the CPU every pass.
- Resizing the character's canvas on every frame of the opening spring: now a fixed size with `scaleEffect`.
- Content laid out at every frame of the opening: now laid out once at final size and revealed by the island's shape.

## Rules the code follows

1. Only the visible island view is in the tree.
2. Nothing redraws unless something changed. Ambient motion is paused by default and runs in the lively tier.
3. Repeating motion goes through `Beat`, never `TimelineView`, never `.repeatForever`, never an implicit animation retriggered by a timer.
4. All-day motion is a `CALayer`.
5. No `NSHostingView` inside the island tree.
6. Pollers run only while their pill is on, and slowly; what can be a system notification (music, power, thermal) is one.
7. A change is judged by `pass=` in the frame log and by `top`, before and after, in the same situation.

## Tooling

Debug builds only.

- `-debugFrames 1` — every five seconds, one line in `~/Library/Logs/NotchBuddy/nb.log`:
  `FRAMES/5s heartbeat=5 mochi(tween:open)=10 mochi-trickle=29 pass=41 poll=50 wake=1` — render passes of the island's hosting view (`pass`), character frames and why (`mochi(reason)`, `mochi-trickle`), pill-character frames (`mini`), pointer polls (`poll`, `poll-sleep`), heartbeats.
- `-debugBounce 1` — opens and closes the island on a loop and logs `PERF open frames=… median=… max=…` for each opening (about 100 frames in the 0.9 s spring is the baseline).
- `-debugLively 1` — the lively tier without a pointer; `-debugView`, `-debugState`, `-debugFocus` put the island in a given situation so measurements are repeatable.
- `sample <pid> 10` and a call-tree reduced to the main thread shows where a pass goes when the number of passes is already right.
