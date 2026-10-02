import SwiftUI

// MARK: - Header chip

/// Icon and temperature in the island header. Click: the weather card takes the left pane.
struct WeatherChip: View {
    @ObservedObject var state: AppState
    @State private var hovered = false

    var body: some View {
        if state.weatherEnabled, let weather = state.weather {
            let on = state.showWeather && state.view == .overview
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    if state.view != .overview { state.view = .overview; state.showWeather = true }
                    else { state.showWeather.toggle() }
                }
                SoundEngine.shared.play("blip")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: WeatherInfo.symbol(code: weather.code, isDay: weather.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                    Text("\(Int(weather.temp.rounded()))°")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(on || hovered ? 1 : 0.85))
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .liquidGlass(Capsule(), tint: on ? Color(hex: weather.accent).opacity(0.35) : nil, interactive: true)
                .glassRim(Capsule(), strength: on ? 0.9 : 0.5, lineWidth: 0.7)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("\(WeatherInfo.label(code: weather.code, isDay: weather.isDay)) in \(weather.city)")
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}

// MARK: - Card

struct WeatherCardView: View {
    let weather: WeatherInfo

    private static let hourFormat: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkillHeader(color: weather.accent, title: weather.city,
                        subtitle: WeatherInfo.label(code: weather.code, isDay: weather.isDay),
                        trailingInset: SkillLayout.trailing) {
                Image(systemName: WeatherInfo.symbol(code: weather.code, isDay: weather.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13))
                    .symbolEffect(.pulse, options: .repeating)
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("\(Int(weather.temp.rounded()))°")
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                    HStack(spacing: 5) {
                        Label("\(Int(weather.high.rounded()))°", systemImage: "arrow.up")
                        Label("\(Int(weather.low.rounded()))°", systemImage: "arrow.down")
                    }
                    .labelStyle(TightLabel())
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.62))
                }
                .fixedSize()

                Spacer(minLength: 0)

                LiquidGroup(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(weather.hours) { hour in
                            VStack(spacing: 3) {
                                Text(Self.hourFormat.string(from: hour.date).lowercased())
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1).fixedSize()
                                Image(systemName: WeatherInfo.symbol(code: hour.code, isDay: hour.isDay))
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 11))
                                    .frame(height: 13)
                                Text("\(Int(hour.temp.rounded()))°")
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.white)
                            }
                            .frame(width: 31, height: 50)
                            .liquidGlass(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .glassRim(RoundedRectangle(cornerRadius: 11, style: .continuous), strength: 0.6, lineWidth: 0.6)
                        }
                    }
                }
            }
            .padding(.top, 5)
            .padding(.leading, SkillLayout.leading)
            .padding(.trailing, SkillLayout.trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon.font(.system(size: 7, weight: .bold))
            configuration.title
        }
    }
}
