import SwiftUI

// MARK: - Liquid Glass
// Apple's Liquid Glass (macOS 26+) for the island, with a translucent fallback on macOS 15.
//
// Glass only looks like glass when it has something to bend. Folded, the island is black so it
// reads as the notch. Open, the island itself is a slab of clear glass (`IslandBody`): the
// desktop shows through it, with a slow flow of colour (`IslandBackdrop`) glowing inside.
// Cards, pills and controls are frosted panes floating in it, each with a thin bright rim.

extension View {
    /// Glass in the given shape. `tint` colours it, `interactive` makes it react to presses.
    /// The tint is our own layer on top of the glass rather than `Glass.tint`: the island is a
    /// non-activating panel, and the system drains glass tints in windows that aren't key.
    @ViewBuilder
    func liquidGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false,
                               clear: Bool = false,
                               fallback: Color = Color.white.opacity(0.07)) -> some View {
        if #available(macOS 26.0, *) {
            self.background(tint ?? .clear, in: shape)
                .glassEffect((clear ? Glass.clear : Glass.regular).interactive(interactive), in: shape)
        } else {
            self.background(tint ?? fallback, in: shape)
        }
    }

    /// The bright edge of a pane of glass: light catches the top-left, slips away down the sides
    /// and returns faintly along the bottom, with a breath of colour where it disperses.
    /// One linear-gradient stroke: cheap to draw, and there is one on every pane and pill.
    func glassRim<S: InsettableShape>(_ shape: S, strength: Double = 1, lineWidth: CGFloat = 0.9) -> some View {
        overlay(
            shape.strokeBorder(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.55 * strength), location: 0),
                    .init(color: Color(hex: "#BAE6FD").opacity(0.22 * strength), location: 0.22),
                    .init(color: .white.opacity(0.08 * strength), location: 0.42),
                    .init(color: .white.opacity(0.04 * strength), location: 0.62),
                    .init(color: Color(hex: "#F5D0FE").opacity(0.20 * strength), location: 0.86),
                    .init(color: .white.opacity(0.16 * strength), location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: lineWidth)
            .allowsHitTesting(false))
    }
}

/// Groups neighbouring glass shapes so they blend and morph into each other like droplets.
struct LiquidGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// MARK: - Card surface

/// The pane every island card sits on: frosted glass inside the clear island, a faint veil so
/// white type stays readable over a bright desktop, the state colour rising from below, and a
/// bright rim.
struct LiquidCard: View {
    var wash: Color = .clear          // state colour (approval amber, error red…)

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        ZStack {
            Color.clear
                .liquidGlass(shape, tint: Color.black.opacity(0.10),
                             fallback: Color(hex: "#141518"))

            RadialGradient(
                gradient: Gradient(stops: [.init(color: wash, location: 0), .init(color: .clear, location: 0.7)]),
                center: UnitPoint(x: 0.5, y: 1.3), startRadius: 0, endRadius: 280)
                .clipShape(shape)
                .allowsHitTesting(false)

            // Soft sheen across the top of the pane
            LinearGradient(stops: [.init(color: .white.opacity(0.07), location: 0),
                                   .init(color: .clear, location: 0.38)],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(shape)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .glassRim(shape)
        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Island body

/// The island itself. Folded, it is black so it reads as the notch. Open, it becomes a slab of
/// glass hanging from the top of the screen: the desktop shows through it, blurred and bent,
/// and the black of the notch melts into the glass like ink.
struct IslandBody: View {
    let shape: IslandShape
    let glass: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if glass {
                // Shadow cast on the desktop, cut out under the slab so it doesn't dim the glass
                shape.fill(Color.black)
                    .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 9)
                    .mask {
                        Rectangle().padding(-80)
                            .overlay(shape.blendMode(.destinationOut))
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)

                Color.clear
                    .liquidGlass(shape, tint: Color.black.opacity(0.36), clear: true,
                                 fallback: Color.black.opacity(0.88))
                    .transition(.opacity)
            }

            shape.fill(Color.black)
                .opacity(glass ? 0 : 1)

            if glass {
                // The notch, dissolving into the glass
                ZStack(alignment: .top) {
                    LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: notchHeight * 0.7)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black)
                        .frame(width: notchWidth + 26, height: notchHeight + 16)
                        .offset(y: -12)
                        .blur(radius: 9)
                }
                .frame(width: shape.width, height: shape.height, alignment: .top)
                .clipShape(shape)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: glass)
    }
}

// MARK: - Island backdrop

/// The wallpaper inside the expanded island: colour in slow motion, keyed to what is in focus
/// (the album cover while music plays, the pill's colour, the alert's colour).
struct IslandBackdrop: View {
    @ObservedObject var state: AppState

    var body: some View {
        let theme = Self.theme(for: state)
        ZStack {
            FlowingMesh(colors: theme.colors, calm: theme.calm)
                .id(theme.key)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.7), value: theme.key)
        // A glow of colour inside the glass, not a wallpaper: the desktop still shows through
        .opacity(0.42)
        .mask(
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black, location: 0.6)],
                           startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }

    private struct Theme {
        let key: String
        let colors: [Color]
        var calm = false
    }

    private static func theme(for state: AppState) -> Theme {
        switch state.view {
        case .approval:            return tone("#F5A524", key: "approval")
        case .question:            return tone("#22D3EE", key: "question")
        case .error:               return tone("#F4505E", key: "error")
        case .finished, .result:   return tone("#34D399", key: "finished")
        case .confused:            return tone("#F472B6", key: "confused")
        case .prompt, .searching:  return tone("#6366F1", key: "chat")
        case .toast:               return Theme(key: "toast", colors: Array(repeating: .black, count: 9), calm: true)
        case .overview:            break
        default:                   return tone("#64748B", key: "neutral", calm: true)
        }

        if state.showWeather, let weather = state.weather {
            return tone(weather.accent, key: "weather-\(weather.accent)", calm: true)
        }
        guard let task = state.focusTask else { return tone("#64748B", key: "neutral", calm: true) }
        if task.id == "integration_music", let np = state.nowPlaying, np.palette.count == 9 {
            return Theme(key: "music-" + np.trackKey, colors: np.palette, calm: !np.isPlaying)
        }
        if task.id == "integration_timer" {
            // Amber rather than the pill's yellow: dark yellow turns olive
            return state.countdowns.contains(where: \.done) ? tone("#34D399", key: "timer-done")
                                                            : tone("#F59E0B", key: "timer")
        }
        if task.id == "integration_system", let s = state.systemStats, s.cpuHot || s.thermalWarning {
            return tone("#F4505E", key: "system-hot")
        }
        // Claude Code follows what the session is doing
        if task.source == .claudeCode || !task.isIntegration {
            switch task.state {
            case .working:            return tone("#3B9EFF", key: "claude-working")
            case .thinking:           return tone("#8B5CF6", key: "claude-thinking")
            case .searching:          return tone("#6366F1", key: "claude-searching")
            case .finished:           return tone("#34D399", key: "claude-finished")
            case .error:              return tone("#F4505E", key: "claude-error")
            case .approval:           return tone("#F5A524", key: "claude-approval")
            case .ratelimit:          return tone("#FB923C", key: "claude-rate")
            default:                  return tone("#818CF8", key: "claude-idle", calm: true)
            }
        }
        return tone(task.color, key: "pill-" + task.id)
    }

    /// Nine mesh colours grown from one accent (hex).
    static func colors(from hex: String) -> [Color] { tone(hex, key: "").colors }

    /// A nine-colour mesh grown from one accent: the accent itself, two neighbours on the
    /// colour wheel, and deep shades so the glass has light and dark to bend.
    private static func tone(_ hex: String, key: String, calm: Bool = false) -> Theme {
        let base = NSColor(Color(hex: hex)).usingColorSpace(.deviceRGB) ?? .gray
        let h = Double(base.hueComponent), s = Double(base.saturationComponent)
        func c(_ dh: Double, _ sat: Double, _ bri: Double) -> Color {
            Color(hue: (h + dh + 1).truncatingRemainder(dividingBy: 1), saturation: min(1, s * sat), brightness: bri)
        }
        return Theme(key: key, colors: [
            c(-0.06, 1.0, 0.16), c(0.02, 1.1, 0.42),  c(0.08, 1.0, 0.20),
            c(-0.04, 1.1, 0.50), c(0, 1.0, 0.78),     c(0.07, 1.1, 0.46),
            c(0.05, 1.0, 0.24),  c(-0.07, 1.1, 0.52), c(0.03, 1.0, 0.18),
        ], calm: calm)
    }
}

/// 3×3 mesh gradient whose inner points drift: corners pinned, edges slide, the centre wanders.
struct FlowingMesh: View {
    let colors: [Color]
    var calm = false          // slower, for paused / idle states
    @ObservedObject private var motion = IslandMotion.shared

    var body: some View {
        // The colours drift slowly behind frosted glass, so 15 frames a second look the same as
        // 60. They drift while the pointer is on the island and for a moment after it opens, and
        // hold still otherwise (and during the opening itself, so the spring gets every frame).
        TimelineView(.beat(15, paused: motion.opening || !motion.lively)) { timeline in
            MeshGradient(width: 3, height: 3,
                         points: Self.points(motion.flowTime(at: timeline.date) * (calm ? 0.35 : 1)),
                         colors: colors, smoothsColors: true)
        }
    }

    private static func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ amp: Double, _ speed: Double, _ phase: Double) -> Float { Float(amp * sin(t * speed + phase)) }
        return [
            [0, 0], [0.5 + w(0.18, 0.42, 0), 0], [1, 0],
            [0, 0.5 + w(0.22, 0.36, 1.3)], [0.5 + w(0.24, 0.52, 2.1), 0.5 + w(0.26, 0.61, 3.4)], [1, 0.5 + w(0.22, 0.47, 4.2)],
            [0, 1], [0.5 + w(0.18, 0.39, 5.0), 1], [1, 1],
        ]
    }
}

// MARK: - Island motion

/// What the island's ambient animations (Mochi, the small characters in the pills, the colour
/// flow) are allowed to spend. They are the only things that keep drawing while the island just
/// sits there, so their frame rate is what the island costs in energy.
@MainActor
final class IslandMotion: ObservableObject {
    static let shared = IslandMotion()

    /// True for the half second the island takes to spring open. The colour flow and the pill
    /// characters wait for it to settle before they start moving.
    @Published private(set) var opening = false

    /// True while the pointer is on the island, and for a moment after it opens or Mochi reacts
    /// to something. Animations run at full rate then, and at half rate the rest of the time:
    /// on a breathing mascot the eye barely sees the difference, the battery does.
    @Published private(set) var lively = false

    /// The pointer is within a few centimetres of the island (not published: read when drawing).
    var pointerNear = false

    private var openToken = 0
    private var boostToken = 0
    private var hovering = false
    private var boosted = false

    func islandWillOpen() {
        openToken += 1
        let mine = openToken
        opening = true
        boost(1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, self.openToken == mine else { return }
            self.opening = false
        }
    }

    func pointer(onIsland: Bool) {
        hovering = onIsland
        refresh()
    }

    /// Full frame rate for a moment: Mochi is reacting to something.
    func boost(_ seconds: Double = 2.5) {
        boostToken += 1
        let mine = boostToken
        boosted = true
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.boostToken == mine else { return }
            self.boosted = false
            self.refresh()
        }
    }

    private func refresh() {
        let now = hovering || boosted
        guard lively != now else { return }
        // The colour flow only moves while lively; keep its clock from jumping when it resumes
        let t = Date().timeIntervalSinceReferenceDate
        if now { flowLost += t - (flowStoppedAt ?? t); flowStoppedAt = nil } else { flowStoppedAt = t }
        lively = now
    }

    private var flowStoppedAt: Double? = Date().timeIntervalSinceReferenceDate
    private var flowLost: Double = 0

    /// Clock of the colour flow: it stands still whenever the flow does.
    func flowTime(at date: Date) -> Double {
        (flowStoppedAt ?? date.timeIntervalSinceReferenceDate) - flowLost
    }
}

/// A timeline that ticks on one shared grid of clock time instead of counting from the moment
/// each view appeared. Every ambient animation uses it with a rate that divides 60 (60, 30, 20,
/// 15, 10), so their ticks fall in the same frames and the island is redrawn once for all of them
/// rather than once for each.
struct BeatSchedule: TimelineSchedule {
    var interval: Double
    var paused = false

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(index: paused ? nil : Int((startDate.timeIntervalSinceReferenceDate / interval).rounded(.up)),
                interval: interval)
    }

    struct Entries: Sequence, IteratorProtocol {
        var index: Int?
        let interval: Double

        mutating func next() -> Date? {
            guard let i = index else { return nil }
            index = i + 1
            return Date(timeIntervalSinceReferenceDate: Double(i) * interval)
        }
    }
}

extension TimelineSchedule where Self == BeatSchedule {
    static func beat(_ perSecond: Double, paused: Bool = false) -> BeatSchedule {
        BeatSchedule(interval: 1 / perSecond, paused: paused)
    }
}
