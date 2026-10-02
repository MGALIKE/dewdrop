import SwiftUI

// Overview cards for the local skills (Music, Timer, System).
// Same grid as the other integration cards: Mochi keeps the left 108 pt, content sits right.

enum SkillLayout {
    static let leading: CGFloat = 108
    static let trailing: CGFloat = 12
}

// MARK: - Shared pieces

struct SkillHeader<Trailing: View>: View {
    let color: String
    let title: String
    let subtitle: String
    var trailingInset: CGFloat = 36          // room for the ↗ button
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: color))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(1)
                .layoutPriority(1)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.62))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 2)
            trailing()
        }
        .frame(height: 15)
        .padding(.top, 6)
        .padding(.leading, SkillLayout.leading)
        .padding(.trailing, trailingInset)
    }
}

extension SkillHeader where Trailing == EmptyView {
    init(color: String, title: String, subtitle: String) {
        self.init(color: color, title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// Round icon button with a hover lift.
struct SkillIconButton: View {
    let icon: String
    var size: CGFloat = 22
    var iconSize: CGFloat = 9
    var filled = false
    var tint: Color = Color(hex: "#F5F6F8")
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(filled ? Color(hex: "#0B0C0E") : tint.opacity(hovered ? 1 : 0.8))
                .frame(width: size, height: size)
                .liquidGlass(Circle(), tint: filled ? tint : (hovered ? Color.white.opacity(0.18) : nil),
                             interactive: true, fallback: Color.white.opacity(hovered ? 0.16 : 0.08))
                .glassRim(Circle(), strength: 0.7, lineWidth: 0.7)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.08 : 1)
        .onHover { h in withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { hovered = h } }
    }
}

/// Small capsule chip (presets, durations).
struct SkillChip: View {
    let text: String
    var icon: String? = nil
    let color: Color
    var prominent = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon { Image(systemName: icon).font(.system(size: 8, weight: .semibold)) }
                Text(text).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
            }
            .foregroundColor(prominent ? Color(hex: "#0B0C0E") : .white.opacity(hovered ? 1 : 0.85))
            .padding(.horizontal, 8).frame(height: 21)
            .liquidGlass(Capsule(), tint: prominent ? color : (hovered ? color.opacity(0.28) : nil),
                         interactive: true, fallback: Color.white.opacity(0.07))
            .glassRim(Capsule(), strength: 0.7, lineWidth: 0.7)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
    }
}

private struct SkillTextButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color.opacity(0.9))
            .buttonStyle(.plain)
    }
}

// MARK: - Music

struct MusicCardView: View {
    @ObservedObject private var appState = AppState.shared
    private let pink = Color(hex: "#EC4899")

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let np = appState.nowPlaying {
                playing(np)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: appState.nowPlaying?.trackKey)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: appState.nowPlaying?.isPlaying)
        .onAppear { MusicMonitor.shared.refresh() }
    }

    private func playing(_ np: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                ArtworkView(image: np.artwork, accent: pink, playing: np.isPlaying)
                    .id(np.trackKey)
                    .transition(.blurReplace.combined(with: .scale(0.8)))

                VStack(alignment: .leading, spacing: 0) {
                    MarqueeText(text: np.title, font: .system(size: 15, weight: .semibold), color: .white)
                        .padding(.trailing, 18)   // clear of the ↗ button
                        .id(np.trackKey)
                        .transition(.blurReplace)
                    Text(np.artist.isEmpty ? np.album : np.artist)
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.64))
                        .lineLimit(1).truncationMode(.tail)
                        .id("artist-" + np.trackKey)
                        .transition(.blurReplace)
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        TransportControls(playing: np.isPlaying)
                        Spacer(minLength: 0)
                        EqualizerBars(active: np.isPlaying)
                            .padding(.trailing, 2)
                    }
                }
                .frame(height: 56)
            }
            .padding(.top, 9)
            .padding(.leading, SkillLayout.leading)
            .padding(.trailing, SkillLayout.trailing)

            Scrubber(np: np)
                .padding(.top, 5)
                .padding(.leading, SkillLayout.leading)
                .padding(.trailing, SkillLayout.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 7) {
            SkillHeader(color: "#EC4899", title: "Music", subtitle: "Nothing playing")

            Text(appState.musicAutomationDenied
                 ? "Allow Coucou under Privacy → Automation to use the controls."
                 : "Play something in Spotify or Apple Music.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, SkillLayout.leading)
                .padding(.trailing, SkillLayout.trailing)

            HStack(spacing: 6) {
                if appState.musicAutomationDenied {
                    SkillChip(text: "Open Privacy settings", icon: "lock.fill", color: pink) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else {
                    ForEach(NowPlaying.Player.allCases.filter(\.isInstalled), id: \.self) { player in
                        SkillChip(text: player.displayName, icon: "play.fill", color: pink) {
                            MusicMonitor.shared.openPlayer(player)
                        }
                    }
                }
            }
            .padding(.leading, SkillLayout.leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

private struct ArtworkView: View {
    let image: NSImage?
    let accent: Color
    let playing: Bool

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [accent, Color(hex: "#7C3AED")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(shape)
        // Sheen across the top-left corner, as if the cover sat under glass
        .overlay(
            LinearGradient(stops: [.init(color: .white.opacity(0.30), location: 0),
                                   .init(color: .clear, location: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(shape)
                .blendMode(.plusLighter))
        .glassRim(shape, strength: 0.8, lineWidth: 0.8)
        .shadow(color: .black.opacity(playing ? 0.45 : 0.2), radius: playing ? 9 : 4, x: 0, y: playing ? 5 : 2)
        // Like Apple Music: the cover sits back when paused and comes forward when playing
        .scaleEffect(playing ? 1 : 0.86)
        .saturation(playing ? 1 : 0.7)
    }
}

/// Play / pause / skip as bare glyphs; a lens of glass forms under the one you point at.
private struct TransportControls: View {
    let playing: Bool
    @State private var backTaps = 0
    @State private var nextTaps = 0

    var body: some View {
        HStack(spacing: 4) {
            TransportButton(size: 22) {
                backTaps += 1
                MusicMonitor.shared.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 11, weight: .bold))
                    .symbolEffect(.bounce, value: backTaps)
            }
            TransportButton(size: 26) {
                MusicMonitor.shared.playPause()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            TransportButton(size: 22) {
                nextTaps += 1
                MusicMonitor.shared.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 11, weight: .bold))
                    .symbolEffect(.bounce, value: nextTaps)
            }
        }
        .padding(.leading, -5)   // optical alignment of the first glyph with the title
    }
}

private struct TransportButton<Label: View>: View {
    let size: CGFloat
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background {
                    if hovered {
                        Color.clear
                            .liquidGlass(Circle(), interactive: true, clear: true, fallback: Color.white.opacity(0.16))
                            .glassRim(Circle(), strength: 0.7, lineWidth: 0.7)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hovered = h } }
    }
}

/// Position bar with a knob: slim at rest, swells under the cursor, drag to seek.
private struct Scrubber: View {
    let np: NowPlaying
    @State private var hovering = false
    @State private var dragFraction: Double? = nil

    var body: some View {
        Beat(2) { timeline in
            let live = np.duration > 0 ? np.position(at: timeline.date) / np.duration : 0
            let fraction = dragFraction ?? live
            let shown = fraction * np.duration
            let active = hovering || dragFraction != nil

            HStack(spacing: 7) {
                Text(Self.clock(np.duration > 0 ? shown : np.position(at: timeline.date)))
                    .frame(minWidth: 22, alignment: .leading)
                GeometryReader { geo in
                    let knob: CGFloat = active ? 11 : 8
                    let x = max(0, min(geo.size.width, geo.size.width * fraction))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.24))
                            .frame(height: active ? 5 : 3)
                        Capsule().fill(Color.white)
                            .frame(width: max(knob / 2, x), height: active ? 5 : 3)
                        Circle()
                            .fill(Color.white)
                            .frame(width: knob, height: knob)
                            .shadow(color: .black.opacity(0.35), radius: 2.5, x: 0, y: 1)
                            .offset(x: min(max(0, x - knob / 2), geo.size.width - knob))
                    }
                    // No animation between the half-second steps: they are a fraction of a point
                    // apart, and gliding between them kept the island redrawing 120 times a second.
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard np.duration > 0 else { return }
                                dragFraction = min(1, max(0, value.location.x / geo.size.width))
                            }
                            .onEnded { _ in
                                if let f = dragFraction { MusicMonitor.shared.seek(to: f * np.duration) }
                                dragFraction = nil
                            })
                }
                .frame(height: 14)
                .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { hovering = h } }
                Text(np.duration > 0 ? "-" + Self.clock(np.duration - shown) : "--:--")
                    .frame(minWidth: 26, alignment: .trailing)
            }
            .font(.system(size: 9.5, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.white.opacity(0.72))
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Single-line text that glides back and forth when it doesn't fit.
/// The text lives in an overlay, so however long it is, it can never widen its container.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var height: CGFloat = 18

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @ObservedObject private var motion = IslandMotion.shared

    private var overflow: CGFloat { max(0, textWidth - boxWidth) }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .overlay(alignment: .leading) {
                // Glides while someone is pointing at the island, and in a banner (which is
                // only up for a few seconds); otherwise the title rests at its start.
                Beat(30, paused: overflow <= 0 || !(motion.lively || AppState.shared.view == .toast)) { timeline in
                    Text(text)
                        .font(font)
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                        .offset(x: -Self.offset(at: timeline.date.timeIntervalSinceReferenceDate, overflow: overflow))
                }
            }
            .clipped()
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: overflow > 0 ? 0.88 : 1),
                                       .init(color: overflow > 0 ? .clear : .black, location: 1)],
                               startPoint: .leading, endPoint: .trailing))
    }

    /// Rest, glide to the end, rest, glide back.
    private static func offset(at t: Double, overflow: CGFloat) -> CGFloat {
        guard overflow > 0 else { return 0 }
        let travel = Double(overflow) / 22, rest = 1.8
        let phase = t.truncatingRemainder(dividingBy: 2 * (travel + rest))
        if phase < rest { return 0 }
        if phase < rest + travel { return overflow * CGFloat((phase - rest) / travel) }
        if phase < 2 * rest + travel { return overflow }
        return overflow * CGFloat(1 - (phase - 2 * rest - travel) / travel)
    }
}

// MARK: - System

struct SystemCardView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkillHeader(color: "#22D3EE", title: "System", subtitle: appState.keepAwake ? "Staying awake" : subtitle) {
                SkillIconButton(icon: "cup.and.saucer.fill", size: 16, iconSize: 7,
                                filled: appState.keepAwake, tint: appState.keepAwake ? Color(hex: "#FBBF24") : .white) {
                    KeepAwake.shared.toggle()
                }
                .help(appState.keepAwake ? "Keep awake is on — click to let the Mac sleep again"
                                         : "Keep the Mac and display awake")
            }

            HStack(spacing: 6) {
                if let s = appState.systemStats {
                    StatTile(label: "CPU", value: "\(Int((s.cpu * 100).rounded()))", unit: "%",
                             fraction: s.cpu, color: Self.loadColor(s.cpu))
                    StatTile(label: "MEMORY", value: Self.gigabytes(s.memUsed), unit: "GB",
                             fraction: s.memFraction, color: Self.loadColor(s.memFraction))
                    if let level = s.battery {
                        StatTile(label: "BATTERY", value: "\(Int((level * 100).rounded()))", unit: "%",
                                 icon: s.onAC ? "bolt.fill" : nil,
                                 fraction: level, color: Self.batteryColor(level, onAC: s.onAC))
                    } else {
                        StatTile(label: "POWER", value: "AC", unit: "", icon: "powerplug.fill",
                                 fraction: 1, color: Color(hex: "#4ADE80"))
                    }
                } else {
                    ForEach(["CPU", "MEMORY", "BATTERY"], id: \.self) { label in
                        StatTile(label: label, value: "–", unit: "", fraction: 0, color: .white)
                    }
                }
            }
            .padding(.top, 7)
            .padding(.leading, SkillLayout.leading)
            .padding(.trailing, SkillLayout.trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private var subtitle: String {
        guard let s = appState.systemStats else { return "Measuring…" }
        if s.thermalWarning { return "Running hot" }
        if s.cpuHot { return "CPU maxed out" }
        guard s.battery != nil else { return "All calm" }
        let time = s.minutesRemaining.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }
        if s.isCharging { return time.map { "Charging · \($0)" } ?? "Charging" }
        if s.onAC { return "Plugged in" }
        if s.batteryLow { return time.map { "Low battery · \($0)" } ?? "Low battery" }
        return time.map { "\($0) left" } ?? "On battery"
    }

    private static func loadColor(_ v: Double) -> Color {
        v >= 0.85 ? Color(hex: "#FF6B78") : (v >= 0.65 ? Color(hex: "#FFC048") : .white)
    }

    private static func batteryColor(_ v: Double, onAC: Bool) -> Color {
        if !onAC && v <= 0.20 { return Color(hex: "#FF6B78") }
        if !onAC && v <= 0.40 { return Color(hex: "#FFC048") }
        return Color(hex: "#4ADE80")
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 10 ? String(format: "%.0f", gb) : String(format: "%.1f", gb)
    }
}

/// A small pane of glass per reading: caption, big number, slim gauge.
private struct StatTile: View {
    let label: String
    let value: String
    let unit: String
    var icon: String? = nil
    let fraction: Double
    let color: Color
    @ObservedObject private var motion = IslandMotion.shared

    private let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
                .fixedSize()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(color)
                        .padding(.leading, 2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 1)
            Spacer(minLength: 0)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(color)
                        .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
                        .shadow(color: color.opacity(0.6), radius: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 8).padding(.top, 7).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 58)
        .liquidGlass(shape, tint: Color.black.opacity(0.14), fallback: Color.white.opacity(0.06))
        .glassRim(shape, strength: 0.6, lineWidth: 0.7)
        // The readings refresh every two seconds; they glide only while someone is looking
        .animation(motion.lively ? .easeOut(duration: 0.4) : nil, value: fraction)
        .animation(motion.lively ? .easeInOut(duration: 0.4) : nil, value: color)
    }
}

// MARK: - Timer

struct TimerCardView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var motion = IslandMotion.shared
    @State private var adding = false
    @State private var reminderText = ""
    @State private var reminderMinutes = 10
    @FocusState private var fieldFocused: Bool

    private let accent = Color(hex: "#FACC15")
    private static let reminderSteps = [5, 10, 15, 30, 60]

    private var primary: Countdown? { TimerEngine.primary(of: appState.countdowns) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let c = primary, c.done {
                    finished(c)
                } else if let c = primary, !adding {
                    running(c)
                } else {
                    setup
                }
            }
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: primary?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: primary?.done)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: adding)
        .onChange(of: appState.focusId) { _, _ in adding = false }
    }

    // MARK: Setup — presets + quick reminder

    private var setup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkillHeader(color: "#FACC15", title: "Timer",
                        subtitle: appState.pomodorosToday > 0 ? "\(appState.pomodorosToday) focus today" : "Focus & reminders",
                        trailingInset: SkillLayout.trailing) {
                if primary != nil {
                    SkillIconButton(icon: "chevron.left", size: 16, iconSize: 7) { adding = false }
                }
            }

            HStack(spacing: 5) {
                SkillChip(text: "Focus \(TimerEngine.focusMinutes)", icon: "play.fill", color: accent, prominent: true) {
                    begin(.focus, TimerEngine.focusMinutes)
                }
                SkillChip(text: "Break \(TimerEngine.breakMinutes)", color: accent) { begin(.rest, TimerEngine.breakMinutes) }
                SkillChip(text: "15", color: accent) { begin(.focus, 15) }
                SkillChip(text: "50", color: accent) { begin(.focus, 50) }
            }
            .padding(.top, 8)
            .padding(.leading, SkillLayout.leading)

            HStack(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 8))
                        .foregroundColor(fieldFocused ? accent : Color.white.opacity(0.55))
                    TextField("Remind me to…", text: $reminderText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .focused($fieldFocused)
                        .onSubmit(addReminder)
                }
                .padding(.horizontal, 8).frame(height: 22)
                .liquidGlass(Capsule(), fallback: Color.white.opacity(fieldFocused ? 0.1 : 0.06))
                .overlay(Capsule().strokeBorder(accent.opacity(fieldFocused ? 0.5 : 0), lineWidth: 0.8))
                .contentShape(Capsule())
                .onTapGesture {
                    // The island is a non-activating panel: it must be key before it can take text
                    IslandWindowController.shared?.window?.makeKey()
                    fieldFocused = true
                }

                SkillChip(text: "in \(Self.minutesLabel(reminderMinutes))", color: accent) {
                    let steps = Self.reminderSteps
                    reminderMinutes = steps[((steps.firstIndex(of: reminderMinutes) ?? 0) + 1) % steps.count]
                    SoundEngine.shared.play("tick")
                }
                SkillIconButton(icon: "plus", size: 21, iconSize: 9, filled: true, tint: accent, action: addReminder)
            }
            .padding(.top, 7)
            .padding(.leading, SkillLayout.leading)
            .padding(.trailing, SkillLayout.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    // MARK: Running

    private func running(_ c: Countdown) -> some View {
        Beat(1) { timeline in
            let now = timeline.date
            let left = c.remaining(at: now)
            VStack(alignment: .leading, spacing: 0) {
                SkillHeader(color: "#FACC15", title: "Timer", subtitle: c.isPaused ? "\(c.label) · paused" : c.label,
                            trailingInset: SkillLayout.trailing) {
                    SkillIconButton(icon: "plus", size: 16, iconSize: 7) { adding = true }
                }

                HStack(alignment: .center, spacing: 6) {
                    Text(Countdown.clock(left))
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .opacity(c.isPaused ? 0.55 : 1)
                        .contentTransition(.numericText(countsDown: true))
                        // Digits roll while someone is pointing at the island; otherwise they just change
                        .animation(motion.lively ? .snappy(duration: 0.3) : nil, value: Int(left.rounded(.up)))
                    Spacer(minLength: 4)
                    SkillIconButton(icon: c.isPaused ? "play.fill" : "pause.fill", size: 24, iconSize: 10,
                                    filled: true, tint: accent) { TimerEngine.shared.togglePause(c.id) }
                    SkillIconButton(icon: "xmark", size: 24, iconSize: 9) { TimerEngine.shared.remove(c.id) }
                }
                .frame(height: 30)
                .padding(.top, 3)
                .padding(.leading, SkillLayout.leading)
                .padding(.trailing, SkillLayout.trailing)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.09))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: "#F59E0B"), accent],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * c.progress(at: now)))
                            .shadow(color: accent.opacity(0.5), radius: 4)
                            // Only a short timer moves enough each second to need gliding
                            .animation(c.total <= 180 && motion.lively ? .linear(duration: 1) : nil, value: c.progress(at: now))
                    }
                }
                .frame(height: 4)
                .padding(.top, 5)
                .padding(.leading, SkillLayout.leading)
                .padding(.trailing, SkillLayout.trailing)

                footnote(for: c, now: now)
                    .padding(.top, 6)
                    .padding(.leading, SkillLayout.leading)
                    .padding(.trailing, SkillLayout.trailing)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
        }
    }

    /// Under the bar: the next waiting reminder, else when this one ends.
    private func footnote(for c: Countdown, now: Date) -> some View {
        let others = appState.countdowns.filter { $0.id != c.id && !$0.done }
            .sorted { $0.remaining(at: now) < $1.remaining(at: now) }
        return HStack(spacing: 4) {
            if let next = others.first {
                Image(systemName: "bell.fill").font(.system(size: 7.5)).foregroundColor(accent.opacity(0.8))
                Text(next.label).lineLimit(1).truncationMode(.tail).foregroundColor(Color.white.opacity(0.88))
                Text("· \(Countdown.short(next.remaining(at: now)))")
                    .monospacedDigit().fixedSize().foregroundColor(Color.white.opacity(0.55))
                if others.count > 1 {
                    Text("+\(others.count - 1)").fixedSize().foregroundColor(Color.white.opacity(0.55))
                }
            } else if let end = c.endDate {
                Text("Ends at \(end.formatted(date: .omitted, time: .shortened))")
                    .foregroundColor(Color.white.opacity(0.55))
            } else {
                Text("Paused").foregroundColor(Color.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5))
        .frame(height: 13)
    }

    // MARK: Finished

    private func finished(_ c: Countdown) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SkillHeader(color: "#34D399", title: "Timer", subtitle: "Time's up", trailingInset: SkillLayout.trailing) {
                EmptyView()
            }

            Text(c.kind == .focus ? "Focus complete — nice work." : (c.kind == .rest ? "Break's over." : c.label))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(1).truncationMode(.tail)
                .padding(.top, 7)
                .padding(.leading, SkillLayout.leading)
                .padding(.trailing, SkillLayout.trailing)

            HStack(spacing: 6) {
                switch c.kind {
                case .focus:
                    SkillChip(text: "Break \(TimerEngine.breakMinutes)", icon: "cup.and.saucer.fill",
                              color: Color(hex: "#F5F6F8"), prominent: true) {
                        TimerEngine.shared.remove(c.id); begin(.rest, TimerEngine.breakMinutes)
                    }
                case .rest:
                    SkillChip(text: "Focus \(TimerEngine.focusMinutes)", icon: "play.fill",
                              color: Color(hex: "#F5F6F8"), prominent: true) {
                        TimerEngine.shared.remove(c.id); begin(.focus, TimerEngine.focusMinutes)
                    }
                case .reminder:
                    SkillChip(text: "Snooze 5", icon: "moon.zzz.fill", color: Color(hex: "#F5F6F8")) {
                        TimerEngine.shared.snooze(c.id, minutes: 5)
                    }
                }
                SkillChip(text: "Done", icon: "checkmark", color: Color(hex: "#34D399"),
                          prominent: c.kind == .reminder) {
                    TimerEngine.shared.remove(c.id)
                }
            }
            .padding(.top, 9)
            .padding(.leading, SkillLayout.leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    // MARK: Actions

    private func begin(_ kind: Countdown.Kind, _ minutes: Int) {
        TimerEngine.shared.startSession(kind, minutes: minutes)
        adding = false
    }

    private func addReminder() {
        TimerEngine.shared.addReminder(reminderText, minutes: reminderMinutes)
        reminderText = ""
        fieldFocused = false
        adding = false
    }

    private static func minutesLabel(_ m: Int) -> String { m >= 60 ? "\(m / 60)h" : "\(m)m" }
}

// MARK: - Compact timer (right ear of the collapsed island while a countdown runs)

struct CompactTimerView: View {
    let countdown: Countdown

    var body: some View {
        Beat(1) { timeline in
            HStack(spacing: 4) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.14), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.02, 1 - countdown.progress(at: timeline.date)))
                        .stroke(Color(hex: "#FACC15"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 10, height: 10)
                Text(Countdown.clock(countdown.remaining(at: timeline.date)))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Color(hex: countdown.isPaused ? "#8E939C" : "#F5F6F8"))
            }
        }
        .fixedSize()
    }
}
