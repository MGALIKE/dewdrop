import SwiftUI

// MARK: - Confetti
// Two party poppers at the bottom corners of the open island. Runs for a couple of seconds
// after `trigger` changes, then leaves the view tree so nothing keeps ticking.

struct ConfettiView: View {
    let trigger: Int
    let size: CGSize

    @State private var start: Date? = nil
    @State private var pieces: [Piece] = []

    private static let life: Double = 2.6
    private static let palette = ["#F472B6", "#FDE047", "#67E8F9", "#6EE7B7", "#A78BFA", "#FB923C", "#FFFFFF"]

    struct Piece {
        var origin: CGPoint
        var velocity: CGVector
        var color: Color
        var size: CGFloat
        var spin: Double
        var phase: Double
        var delay: Double
        var kind: Int          // 0 rectangle, 1 dot, 2 ribbon
    }

    var body: some View {
        Group {
            if let start {
                TimelineView(.animation) { timeline in
                    Canvas { context, _ in
                        draw(context, t: timeline.date.timeIntervalSince(start))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        var new: [Piece] = []
        for i in 0..<64 {
            let left = i % 2 == 0
            // Up and toward the middle, fanned out
            let angle = Double.random(in: 0.32...1.30)
            let speed = Double.random(in: 240...600)
            new.append(Piece(
                origin: CGPoint(x: left ? 14 : size.width - 14, y: size.height - 6),
                velocity: CGVector(dx: cos(angle) * speed * (left ? 1 : -1), dy: -sin(angle) * speed),
                color: Color(hex: Self.palette.randomElement()!),
                size: CGFloat.random(in: 4.5...8),
                spin: Double.random(in: 4...11) * (Bool.random() ? 1 : -1),
                phase: Double.random(in: 0...(2 * .pi)),
                delay: Double.random(in: 0...0.18),
                kind: Int.random(in: 0..<3)))
        }
        // …and a light rain from the top once the burst is in the air
        for _ in 0..<30 {
            new.append(Piece(
                origin: CGPoint(x: CGFloat.random(in: 20...(size.width - 20)), y: -8),
                velocity: CGVector(dx: Double.random(in: -40...40), dy: Double.random(in: 40...150)),
                color: Color(hex: Self.palette.randomElement()!),
                size: CGFloat.random(in: 4.5...7.5),
                spin: Double.random(in: 4...9) * (Bool.random() ? 1 : -1),
                phase: Double.random(in: 0...(2 * .pi)),
                delay: Double.random(in: 0.25...1.1),
                kind: Int.random(in: 0..<3)))
        }
        pieces = new
        let fired = Date()
        start = fired
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.life + 0.1) {
            if start == fired { start = nil; pieces = [] }
        }
    }

    private func draw(_ context: GraphicsContext, t: Double) {
        for piece in pieces {
            let age = t - piece.delay
            guard age > 0, age < Self.life else { continue }
            // Air drag slows the burst; gravity brings it back down
            let drag = (1 - exp(-1.25 * age)) / 1.25
            let x = piece.origin.x + piece.velocity.dx * drag + sin(age * 5 + piece.phase) * 5
            let y = piece.origin.y + piece.velocity.dy * drag + 95 * age * age
            guard y < size.height + 12 else { continue }

            var ctx = context
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: .radians(piece.phase + piece.spin * age))
            ctx.opacity = min(1, (Self.life - age) / 0.6)
            let flip = abs(cos(age * piece.spin * 0.9 + piece.phase))      // tumbling in the air
            switch piece.kind {
            case 0:
                ctx.fill(Path(roundedRect: CGRect(x: -piece.size / 2, y: -piece.size * 0.3 * flip,
                                                  width: piece.size, height: piece.size * 0.6 * max(0.15, flip)),
                              cornerRadius: 1), with: .color(piece.color))
            case 1:
                ctx.fill(Path(ellipseIn: CGRect(x: -piece.size * 0.3, y: -piece.size * 0.3,
                                                width: piece.size * 0.6, height: piece.size * 0.6)), with: .color(piece.color))
            default:
                var ribbon = Path()
                ribbon.move(to: CGPoint(x: -piece.size * 0.8, y: 0))
                ribbon.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -piece.size * 0.4, y: -piece.size * 0.6 * flip))
                ribbon.addQuadCurve(to: CGPoint(x: piece.size * 0.8, y: 0), control: CGPoint(x: piece.size * 0.4, y: piece.size * 0.6 * flip))
                ctx.stroke(ribbon, with: .color(piece.color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }
}

// MARK: - Battery glyph (power banner)

/// A battery that fills up to `level` when it appears; the bolt pulses while charging.
struct BatteryGlyph: View {
    let level: Double
    let charging: Bool
    let color: Color

    @State private var shown: Double = 0
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, (geo.size.width - 4) * shown))
                        .padding(2)
                        .shadow(color: color.opacity(0.7), radius: 4)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 0.5)
                        .scaleEffect(pulse ? 1.18 : 0.92)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 34, height: 18)
            .glassRim(RoundedRectangle(cornerRadius: 5, style: .continuous), strength: 0.9, lineWidth: 0.7)

            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.45))
                .frame(width: 2, height: 7)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.78).delay(0.25)) { shown = level }
            if charging {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }
}

/// "0%" counting up to the real figure.
struct CountingPercent: View, @preconcurrency Animatable {
    var value: Double        // 0…1

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int((value * 100).rounded()))%")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(.white)
    }
}
