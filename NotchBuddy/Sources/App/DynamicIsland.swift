import SwiftUI

// Dynamic-Island behaviour: what the island shows while folded (live activities),
// and the short banner that drops from the notch when something happens (toast).

// MARK: - Compact live activity (right ear of the folded island)

/// What the right ear shows, in order of urgency: a running timer, the playing track,
/// and otherwise the usual grid of mini Mochis.
struct CompactActivityView: View {
    @ObservedObject var state: AppState
    let islandWidth: CGFloat
    let islandHeight: CGFloat

    private enum Activity: Equatable { case timer(Countdown), music(String), none }

    private var activity: Activity {
        if state.activeIntegrations.contains("integration_timer"),
           let countdown = TimerEngine.primary(of: state.countdowns), !countdown.done {
            return .timer(countdown)
        }
        if state.activeIntegrations.contains("integration_music"), let np = state.nowPlaying, np.isPlaying {
            return .music(np.trackKey)
        }
        return .none
    }

    var body: some View {
        ZStack {
            switch activity {
            case .timer(let countdown):
                CompactTimerView(countdown: countdown)
                    .transition(.blurReplace)
            case .music:
                if let np = state.nowPlaying {
                    CompactMusicView(np: np)
                        .id(np.trackKey)
                        .transition(.blurReplace)
                }
            case .none:
                CompactMiniGrid(state: state)
                    .scaleEffect(IslandRestingLayout(width: islandWidth, height: islandHeight).miniGridScale)
                    .transition(.blurReplace)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activity)
        .position(x: islandWidth - 41, y: islandHeight / 2)
    }
}

/// Tiny cover and dancing bars in the colours of the track.
private struct CompactMusicView: View {
    let np: NowPlaying

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if let art = np.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color(hex: "#EC4899")
                        Image(systemName: "music.note").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                    }
                }
            }
            .frame(width: 17, height: 17)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))

            EqualizerBars(active: np.isPlaying, color: barColor, height: 12)
        }
        .fixedSize()
    }

    private var barColor: Color {
        guard let tint = np.mochiTint else { return .white }
        return Color(cgColor: tint)
    }
}

// MARK: - Toast (banner under the notch)

struct IslandToastView: View {
    @ObservedObject var state: AppState
    let width: CGFloat
    let height: CGFloat

    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let toast = state.toast {
                backdrop(toast)
                content(toast)
                    .id(toast.id)
                    .transition(.blurReplace)
            }
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            // Open the full island on whatever the banner was about
            if let id = state.toast?.focusId, state.tasks.contains(where: { $0.id == id }) { state.setFocus(id) }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.view = .overview }
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.12)) { appeared = true } }
        .onDisappear { appeared = false }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: state.toast?.id)
    }

    private func backdrop(_ toast: IslandToast) -> some View {
        FlowingMesh(colors: toast.palette.count == 9 ? toast.palette : IslandBackdrop.colors(from: toast.accent))
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .clear, location: 0.3),
                                       .init(color: .black.opacity(0.85), location: 0.85)],
                               startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(_ toast: IslandToast) -> some View {
        if let kind = toast.hud {
            HUDSlider(kind: kind, level: toast.level, muted: toast.muted, tint: Color(hex: toast.accent))
                .padding(.leading, 62)
                .padding(.trailing, 20)
                .frame(height: 52)
                .opacity(appeared ? 1 : 0)
        } else {
            banner(toast)
        }
    }

    private func banner(_ toast: IslandToast) -> some View {
        HStack(spacing: 10) {
            if let level = toast.battery {
                BatteryGlyph(level: level, charging: toast.charging, color: Color(hex: toast.accent))
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)
            } else {
            Group {
                if let art = toast.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color(hex: toast.accent).opacity(0.85)
                        Image(systemName: toast.symbol ?? "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .glassRim(RoundedRectangle(cornerRadius: 10, style: .continuous), strength: 0.8, lineWidth: 0.7)
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            }

            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(text: toast.title, font: .system(size: 13, weight: .semibold), color: .white, height: 16)
                Text(toast.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.68))
                    .lineLimit(1).truncationMode(.tail)
            }
            .offset(x: appeared ? 0 : 10)
            .opacity(appeared ? 1 : 0)

            if toast.showsEqualizer {
                EqualizerBars(active: true, height: 14)
                    .opacity(appeared ? 1 : 0)
            }
            if let level = toast.battery {
                CountingPercent(value: appeared ? level : 0)
                    .animation(.easeOut(duration: 1.0).delay(0.25), value: appeared)
                    .opacity(appeared ? 1 : 0)
            }
            if case .jump(let taskId) = toast.action {
                Button {
                    TerminalJumper.jump(to: state.tasks.first(where: { $0.id == taskId }))
                    IslandWindowController.shared?.collapse()
                } label: {
                    HStack(spacing: 3) {
                        Text("Jump")
                        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 25)
                    .liquidGlass(Capsule(), tint: Color(hex: toast.accent).opacity(0.38), interactive: true)
                    .glassRim(Capsule(), strength: 0.8, lineWidth: 0.7)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Bring this session's terminal to the front")
                .scaleEffect(appeared ? 1 : 0.7)
                .opacity(appeared ? 1 : 0)
            }
        }
        .padding(.leading, 62)      // Mochi sits on the left
        .padding(.trailing, 18)
        .frame(height: 52)
    }
}

// MARK: - Volume / brightness slider

/// The slider shown under the notch when the volume or brightness changes. Drag it to set the level.
struct HUDSlider: View {
    let kind: HUDKind
    let level: Double
    let muted: Bool
    let tint: Color

    @State private var dragging = false

    private var shown: Double { muted ? 0 : min(1, max(0, level)) }

    private var symbol: String {
        switch kind {
        case .volume:     return muted || shown == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol, variableValue: shown)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26)

            GeometryReader { geo in
                let height: CGFloat = dragging ? 13 : 8
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(LinearGradient(colors: [tint, .white], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(height, geo.size.width * shown))
                        .shadow(color: tint.opacity(0.6), radius: 5)
                }
                .frame(height: height)
                .glassRim(Capsule(), strength: 0.7, lineWidth: 0.6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        HUDMonitor.shared.set(kind, level: Double(value.location.x / max(1, geo.size.width)))
                    }
                    .onEnded { _ in dragging = false })
            }
            .frame(height: 28)

            Text("\(Int((shown * 100).rounded()))")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .frame(width: 30, alignment: .trailing)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: shown)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragging)
    }
}
