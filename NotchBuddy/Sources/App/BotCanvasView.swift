import SwiftUI
import Combine

/// Mochi's canvas. It is redrawn only while something on Mochi changes: a `Heartbeat` asks the
/// engine a few times a second whether anything is due, and the timeline runs until it settles.
/// The motions that never stop (the dance to music, breathing, the impatient bounce) only play
/// while the pointer is on the island; redrawing for them all day is what the island used to cost.
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    var displayScale: CGFloat = 1     // how much the canvas is scaled on screen

    // One engine per view instance (main bot)
    @StateObject private var engine = BotEngine()
    @ObservedObject private var motion = IslandMotion.shared

    /// Something is changing and the canvas is being redrawn at full rate.
    @State private var awake = true

    /// The "…" badge of a working state is drawn from the clock: in the open island it gets a
    /// slow trickle of frames instead of none, so it still reads as busy. (Beside the folded
    /// notch its dots are a pixel wide, and that state can last for hours.)
    private var simmers: Bool {
        guard state.mode == .expanded else { return false }
        if case .dots = BotStates[state.effectiveState]?.badge { return true }
        return false
    }

    /// Something that never settles is playing: a dance, breathing, rain on the umbrella, typing
    /// on the laptop. Only while lively (see `feed`); otherwise those hold still.
    private var dances: Bool {
        guard motion.lively else { return false }
        let cfg = BotStates[state.effectiveState]
        return state.botMood != .none || cfg?.bounces == true || cfg?.breathes == true
            || !state.botProps.isDisjoint(with: [.laptop, .magnifier, .pencil, .rainfall, .snowfall])
    }

    var body: some View {
        // What Dew may spend. While something moves: 30 fps in the open island (the same beat as
        // the pill characters and the text shimmer, so one redraw serves them all), 20 for the
        // tiny Dew in the folded notch. While nothing moves: no frames at all, or a trickle for a
        // ticking badge in the open island.
        // (Every redraw of the island costs about 4 ms whatever changed: at 60 fps with the
        // pointer on it the island took a quarter of a core, at 30 it takes half that.)
        let folded = state.mode != .expanded
        let running = awake || dances
        let rate: Double = running ? (folded ? 20 : 30) : 6
        Beat(rate, paused: state.mode == .hidden || !(running || simmers)) { timeline in
            let _ = step(timeline.date)
            ZStack {
                // In the open island the body is real glass; the canvas draws the light in it
                if #available(macOS 26.0, *), glass {
                    // Under the glass: what it bends (the liquid inside, the hands behind)
                    Canvas { context, size in
                        _ = timeline.date
                        engine.drawHandsBehind(context: context, size: size)
                        engine.drawUnderGlass(context: context, size: size)
                    }
                    GeometryReader { geo in DewGlass(pose: engine.pose(in: geo.size)) }
                }
                Canvas { context, size in
                    _ = timeline.date            // redraw on every tick
                    if !engine.glassUnder { engine.drawHandsBehind(context: context, size: size) }
                    engine.draw(context: context, size: size)
                    engine.drawProps(context: context, size: size)
                    engine.drawHandsAndExtras(context: context, size: size)
                }
            }
        }
        .onReceive(Heartbeat.shared) { _ in
            #if DEBUG
            FrameLog.hit("heartbeat")
            #endif
            guard !awake, state.mode != .hidden else { return }
            feed()
            if engine.wantsWake(lookX: engine.lookX, lookY: engine.lookY) { wake() }
        }
        .onChange(of: state.effectiveState) { _, newState in
            engine.setState(newState)
            wake()
        }
        .onChange(of: state.botProps) { _, _ in wake() }
        .onChange(of: state.botMood) { _, _ in wake() }
        .onChange(of: state.botEyeHint) { _, _ in wake() }
        .onChange(of: state.focusId) { _, _ in wake() }
        .onChange(of: state.nowPlaying?.trackKey) { _, _ in wake() }
        .onChange(of: state.fileDragOver) { _, _ in wake() }
        .onChange(of: state.view) { _, newView in
            wake()
            // Morph up when upload view is active
            if state.mode == .expanded && newView == .upload {
                engine.anim("morph", keys: [TweenKey(target: 1, duration: 550, ease: Ease.inOut)])
            } else if newView != .upload && newView != .uploading && engine.morph > 0.01 {
                // Any other view (not mid-gulp): morph back
                engine.anim("morph", keys: [TweenKey(target: 0, duration: 550, ease: Ease.inOut)])
            }
        }
        .onChange(of: state.mode) { _, newMode in
            wake()
            // Hard-reset morph when island collapses
            if newMode != .expanded {
                engine.tweens.removeValue(forKey: "morph")
                engine.locks.remove("morph")
                engine.morph = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { notif in
            if let emote = notif.object as? BotEmote {
                engine.triggerEmote(emote)
                motion.boost()
                wake()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in
            engine.slap()
            motion.boost()
            wake()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botReact)) { notif in
            if let reaction = notif.object as? BotReaction { engine.react(reaction); motion.boost(3.5); wake() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { _ in
            engine.blink()
            wake()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botSetTgEs)) { notif in
            if let v = notif.object as? CGFloat {
                engine.tgEs = v
                wake()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGulp)) { _ in
            engine.gulp()
            motion.boost()
            wake()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botMorphTo)) { notif in
            if let target = notif.object as? CGFloat {
                let dur: CGFloat = target > 0.5 ? 550 : 650
                engine.anim("morph", keys: [TweenKey(target: target, duration: dur, ease: Ease.inOut)])
                wake()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            engine.greet()
            motion.boost(4)
            wake()
        }
        .onAppear {
            engine.setState(state.effectiveState, force: true)
        }
    }

    /// Real glass under the canvas: only where Dew is large enough for it to show.
    private var glass: Bool {
        state.mode == .expanded && state.view != .uploading && !DewDebug.noGlass
    }

    /// One tick: hand the engine its inputs, move it forward and note whether it has settled.
    private func step(_ date: Date) {
        guard date != engine.lastTick else { return }
        engine.lastTick = date
        feed()
        engine.advance(stepsPerSecond: 60)
        let now = CACurrentMediaTime()
        if engine.isAnimating { engine.lastMotion = now }
        #if DEBUG
        FrameLog.hit(awake ? "mochi(" + engine.animatingReason + ")" : "mochi-trickle")
        #endif
        let settled = now - engine.lastMotion > 0.1
        if settled == awake { DispatchQueue.main.async { awake = !settled } }
    }

    /// Start redrawing: something just changed.
    private func wake() {
        #if DEBUG
        FrameLog.hit("wake")
        #endif
        engine.lastMotion = CACurrentMediaTime()
        if !awake { awake = true }
    }

    /// Hands the engine what it reacts to (the pointer, the state, what Mochi wears).
    private func feed() {
        // Folded, Mochi's eyes are a pixel or two: they only follow a pointer that comes close,
        // rather than waking up for every movement anywhere on the screen.
        let follows = state.mode == .expanded || motion.pointerNear
        engine.lookX = follows ? lookX(state: state) : 0
        engine.lookY = follows ? lookY(state: state) : 0
        engine.particleOverhang = particleOverhang
        engine.displayScale = displayScale
        if #available(macOS 26.0, *) { engine.glassUnder = glass } else { engine.glassUnder = false }
        // Widen slot when file is hovering over the mailbox (morph > 0.5)
        // Open mouth (hover=0.20R) when file dragged over box; close when not
        if engine.morph > 0.3 {
            engine.slotHTarget = state.fileDragOver ? 0.20 : 0
        } else {
            engine.slotHTarget = 0
            if engine.morph < 0.05 { engine.slotH = 0; engine.slotHVel = 0 }
        }
        // Integration pills have a fixed brand color → use it as bodyColor.
        // Claude Code tasks use state-based gradient (working=blue, thinking=purple, etc.).
        if state.focusId == "integration_music", let tint = state.nowPlaying?.mochiTint {
            engine.bodyColor = tint
        } else {
            engine.bodyColor = (state.focusTask?.isIntegration == true)
                ? cgColorFromHex(state.focusTask!.color)
                : nil
        }
        engine.mood = state.botMood
        engine.props = state.botProps
        engine.hintEye = state.botEyeHint
        engine.anticsEnabled = true
        // The endless motions (dance, breathing, bounce) wait for the pointer; music notes and
        // other ambient particles come less often when nobody is pointing at the island, and
        // hardly ever beside the folded notch, where they are specks.
        engine.externalMotion = !motion.lively
        engine.ambientInterval = motion.lively ? 1.3 : state.mode == .expanded ? 3.5 : 9
    }

    private func lookX(state: AppState) -> CGFloat {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let (botCx, _, _, _) = botPosition(mode: state.mode, view: state.view,
                                            islandW: islandW, islandH: islandH,
                                            uploadProgress: state.uploadProgress)
        // Island is centered on screen; bot is at botCx within island coords
        let botScreenX = screen.frame.midX - islandW / 2 + botCx
        return tanh((state.mousePosition.x - botScreenX) / 260)
    }

    private func lookY(state: AppState) -> CGFloat {
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let actualH: CGFloat = (state.mode == .expanded && state.view == .prompt)
            ? min(300, 240 + CGFloat(state.chatHistory.count) * 40)
            : islandH
        let (_, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                             islandW: islandW, islandH: actualH,
                                             uploadProgress: state.uploadProgress)
        // Island top = screen top → bot screen Y = botCy from island top
        return -tanh((state.mousePosition.y - botCy) / 200)
    }
}

/// Mini bot canvas (for agent pills/column). They only come alive while the pointer is on the
/// island: six of them glancing around on their own kept the island redrawing all the time.
struct MiniBotCanvasView: View {
    let task: AgentTask
    let folded: Bool          // the 12pt ones beside the folded notch
    @StateObject private var engine: BotEngine
    @ObservedObject private var motion = IslandMotion.shared

    init(task: AgentTask, folded: Bool = false) {
        self.task = task
        self.folded = folded
        _engine = StateObject(wrappedValue: {
            let e = BotEngine()
            e.isMini = true
            e.bodyColor = cgColorFromHex(task.color)
            return e
        }())
    }

    var body: some View {
        // 30 fps while lively. Otherwise still, except a working one in the open island, which
        // keeps a trickle of frames for its pulsing badge. They also wait for the island to
        // finish opening.
        let simmers = !folded && task.state != .idle
        Beat(motion.lively ? 15 : 4, paused: motion.opening || !(motion.lively || simmers)) { timeline in
            Canvas { context, size in
                _ = timeline.date            // redraw on every tick
                engine.mood = AppState.shared.miniMood(for: task.id)
                // Same pace at any frame rate (tuned for one 0.05 step per frame at 30 fps)
                engine.advance(stepsPerSecond: 30)
                #if DEBUG
                FrameLog.hit("mini")
                #endif
                engine.draw(context: context, size: size)
            }
        }
        .onChange(of: task.state) { _, newState in
            engine.setState(newState)
        }
        .onAppear {
            engine.setState(task.state, force: true)
            if let emote = task.emote {
                engine.setPermanentEmote(emote)
            }
            // Direct eye override takes priority (e.g. .wide eyes for Research)
            if let eye = task.miniEye {
                engine.permanentEye = eye
                engine.eyeOverride = eye
                engine.eyeOverrideUntil = .greatestFiniteMagnitude
            }
        }
    }
}

/// One slow shared tick. The sleeping canvas uses it to ask its engine whether anything is due
/// (a blink, a glance at the pointer). Five a second while the pointer is moving or the island is
/// open; one a second, loosely timed, while nobody is touching the Mac.
@MainActor
enum Heartbeat {
    static let shared = PassthroughSubject<Date, Never>()
    private static var timer: Timer?
    private static var interval: Double = 0

    static func setRelaxed(_ relaxed: Bool) {
        let wanted = relaxed ? 1.0 : 0.2
        guard wanted != interval else { return }
        interval = wanted
        timer?.invalidate()
        let t = Timer(timeInterval: wanted, repeats: true) { _ in
            MainActor.assumeIsolated { shared.send(Date()) }
        }
        t.tolerance = wanted / 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// MARK: - CGColor from hex string

func cgColorFromHex(_ hex: String) -> CGColor? {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard let val = UInt64(h, radix: 16) else { return nil }
    let r = CGFloat((val >> 16) & 0xFF) / 255
    let g = CGFloat((val >> 8)  & 0xFF) / 255
    let b = CGFloat( val        & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}

extension CGColor {
    static func from(_ hex: String) -> CGColor {
        cgColorFromHex(hex) ?? CGColor(gray: 0.5, alpha: 1)
    }
}

/// `-debugDewGlass 0` draws Dew without the real glass underneath, to compare.
enum DewDebug {
    static let noGlass = UserDefaults.standard.string(forKey: "debugDewGlass") == "0"
}
