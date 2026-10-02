import SwiftUI

// MARK: - Dew
// The character is a bead of the island's own glass.
//
// In the open island its body is real Liquid Glass (`DewGlass`, under the canvas), so it bends
// whatever is behind it. The canvas adds what makes a drop read as a drop: the flank facing the
// light is the dark one, the light is gathered on the far side, the rim is bright and there is
// one small hard highlight. Beside the folded notch there is only black to bend, so there the
// canvas draws the whole drop and the colour inside it does the work.

extension BotEngine {

    /// The colour held in the glass and how much of it there is.
    private var liquid: (color: Color, amount: Double) {
        // A pill's own colour fills Dew, unless it has none to speak of (the Claude pill is
        // white): then the liquid shows what Claude is doing, like on a session.
        if let bc = bodyColor, let c = bc.components, c.count >= 3,
           max(c[0], c[1], c[2]) - min(c[0], c[1], c[2]) > 0.12 {
            return (Color(cgColor: bc), 0.85)
        }
        return (colorFromTuple(col), Double(tint))
    }

    /// What goes under the real glass, so the glass has something to bend: the shadow Dew
    /// casts and the liquid inside it. (Without real glass, `draw` paints these itself.)
    func drawUnderGlass(context: GraphicsContext, size: CGSize) {
        let R = size.width * 0.3
        let rx = R * DewConst.rx, ry = R * DewConst.ry
        var ctx = context
        ctx.translateBy(x: size.width / 2 + ox * R, y: size.height / 2 + particleOverhang / 2 + oy * R + R * 0.06)
        if tilt != 0 { ctx.rotate(by: .radians(tilt)) }
        ctx.scaleBy(x: sx, y: sy)
        drawLiquid(ctx: ctx, path: bodyPath(rx: rx, ry: ry, morph: morph, R: R), R: R, rx: rx, ry: ry)
    }

    func drawLiquid(ctx: GraphicsContext, path: Path, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        guard !isMini else { return }
        let (tone, amount) = liquid
        let small = R * displayScale < 9          // beside the folded notch: a few points across

        // Shadow on whatever Dew rests on
        if !small {
            let w = rx * 1.7, h = R * 0.30
            ctx.fill(Path(ellipseIn: CGRect(x: -w / 2 + R * 0.10, y: ry * 0.98 - h / 2, width: w, height: h)),
                     with: .radialGradient(Gradient(colors: [.black.opacity(0.30), .clear]),
                                           center: CGPoint(x: R * 0.10, y: ry * 0.98), startRadius: 0, endRadius: w / 2))
        }

        // The surface: level whatever way Dew tilts, tipped and rippled by what just moved it
        let fill = 0.24 + 0.50 * CGFloat(amount)                // how full the bulb is
        let top = ry - fill * 2 * ry
        let slope = tan(max(-0.6, min(0.6, slosh - tilt)))
        let t = CGFloat(CACurrentMediaTime() - t0)
        let wave = R * (0.05 * ripple + (externalMotion ? 0 : 0.012))
        var surface = Path()
        let steps = 28
        for i in 0...steps {
            let x = -rx * 1.25 + rx * 2.5 * CGFloat(i) / CGFloat(steps)
            // Seen through real glass the surface bends by itself; without it, draw the bend:
            // the liquid climbs the wall a little
            let climb = glassUnder ? 0 : R * 0.11 * pow(x / rx, 2)
            let y = top + slope * x + wave * sin(x / R * 5.2 + t * 4.2) - climb
            if i == 0 { surface.move(to: CGPoint(x: x, y: y)) } else { surface.addLine(to: CGPoint(x: x, y: y)) }
        }
        var pool = surface
        pool.addLine(to: CGPoint(x: rx * 1.25, y: ry * 1.4))
        pool.addLine(to: CGPoint(x: -rx * 1.25, y: ry * 1.4))
        pool.closeSubpath()

        var inner = ctx
        inner.clip(to: path)
        let strength = 0.22 + 0.68 * amount
        inner.fill(pool, with: .linearGradient(
            Gradient(stops: [.init(color: tone.opacity(strength * 0.62), location: 0),
                             .init(color: tone.opacity(strength), location: 1)]),
            startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: ry)))
        // Depth: the liquid is lighter where the light comes through it
        var lit = inner
        lit.blendMode = .plusLighter
        lit.fill(pool, with: .radialGradient(
            Gradient(colors: [.white.opacity(0.30 * strength), .clear]),
            center: CGPoint(x: rx * 0.40, y: ry * 0.45), startRadius: 0, endRadius: R * 0.85))
        // The surface catches the light
        inner.stroke(surface, with: .color(.white.opacity(small ? 0.35 : 0.62)),
                     lineWidth: max(0.8 / max(displayScale, 0.2), R * 0.035))
    }

    func drawDewBody(ctx: GraphicsContext, path: Path, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        if isMini { drawDewMini(ctx: ctx, path: path, R: R, rx: rx, ry: ry); return }

        let (tone, amount) = liquid
        let small = R * displayScale < 9

        var inner = ctx
        inner.clip(to: path)

        // The glass itself: a breath of white, and a trace of the liquid's colour above it.
        // With real glass underneath, that glass is the body and this stays out of its way.
        if !glassUnder { inner.fill(path, with: .color(.white.opacity(0.07))) }
        if amount > 0.01 { inner.fill(path, with: .color(tone.opacity(0.10 * amount))) }

        // A drop is a lens: the flank facing the light goes dark…
        inner.fill(path, with: .linearGradient(
            Gradient(stops: [.init(color: .black.opacity(0.20), location: 0),
                             .init(color: .black.opacity(0.06), location: 0.24),
                             .init(color: .clear, location: 0.42)]),
            startPoint: CGPoint(x: -rx * 0.95, y: -ry * 1.05), endPoint: CGPoint(x: rx * 0.55, y: ry * 0.75)))

        // …and the light it took is gathered low on the far side
        var lit = inner
        lit.blendMode = .plusLighter
        let glow = amount > 0.01 ? tone : Color(red: 0.80, green: 0.90, blue: 1)
        lit.fill(path, with: .radialGradient(
            Gradient(stops: [.init(color: .white.opacity(0.34), location: 0),
                             .init(color: glow.opacity(0.22), location: 0.45),
                             .init(color: .clear, location: 1)]),
            center: CGPoint(x: rx * 0.58, y: ry * 0.56), startRadius: 0, endRadius: R * 0.50))
        // The sky in the tip
        lit.fill(path, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.20), .clear]),
            startPoint: CGPoint(x: 0, y: -ry * 1.45), endPoint: CGPoint(x: 0, y: -ry * 0.45)))

        // Rim: bright where the light lands and where it leaves, a breath of colour between.
        // Stroked at twice the width and clipped, so it sits inside the outline.
        let rim = max(1.0 / max(displayScale, 0.2), R * 0.05)
        inner.stroke(path, with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.95), location: 0),
                             .init(color: Color(hex: "#BAE6FD").opacity(0.45), location: 0.24),
                             .init(color: .white.opacity(0.14), location: 0.46),
                             .init(color: .white.opacity(0.10), location: 0.64),
                             .init(color: Color(hex: "#F5D0FE").opacity(0.50), location: 0.86),
                             .init(color: .white.opacity(0.80), location: 1)]),
            startPoint: CGPoint(x: -rx * 0.8, y: -ry * 1.2), endPoint: CGPoint(x: rx * 0.8, y: ry * 1.0)),
            lineWidth: rim * 2)

        guard !small, morph < 0.5 else { return }
        let fade = Double(1 - morph * 2)

        // One hard highlight on the shoulder facing the light, and its small echo
        var shine = Path()
        shine.addArc(center: .zero, radius: R * 0.70, startAngle: .degrees(200), endAngle: .degrees(238), clockwise: false)
        var glint = inner
        glint.scaleBy(x: rx / R, y: ry / R)
        glint.stroke(shine, with: .color(.white.opacity(0.88 * fade)),
                     style: StrokeStyle(lineWidth: R * 0.085, lineCap: .round))
        var dot = Path()
        dot.addEllipse(in: CGRect(x: -R * 0.335, y: -R * 0.705, width: R * 0.09, height: R * 0.09))
        glint.fill(dot, with: .color(.white.opacity(0.80 * fade)))

        // Light leaving low on the far side
        var back = Path()
        back.addArc(center: .zero, radius: R * 0.80, startAngle: .degrees(22), endAngle: .degrees(62), clockwise: false)
        glint.stroke(back, with: .color(.white.opacity(0.34 * fade)),
                     style: StrokeStyle(lineWidth: R * 0.05, lineCap: .round))
    }

    /// The pill characters: a bead of coloured glass, too small for more than a body, a light
    /// and two eyes.
    private func drawDewMini(ctx: GraphicsContext, path: Path, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        let tone = Color(cgColor: bodyColor ?? DewConst.ink)
        var inner = ctx
        inner.clip(to: path)
        inner.fill(path, with: .color(tone))
        inner.fill(path, with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.42), location: 0),
                             .init(color: .white.opacity(0.0), location: 0.55),
                             .init(color: .black.opacity(0.12), location: 1)]),
            startPoint: CGPoint(x: -rx * 0.7, y: -ry * 1.2), endPoint: CGPoint(x: rx * 0.7, y: ry * 1.0)))
        inner.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: max(1, R * 0.10))
    }

    /// A small bead of the same glass (Dew's hands).
    func drawBead(_ ctx: GraphicsContext, in rect: CGRect) {
        guard rect.width > 0.5, rect.height > 0.5 else { return }
        let (tone, amount) = liquid
        let bead = Path(ellipseIn: rect)
        var inner = ctx
        inner.clip(to: bead)
        inner.fill(bead, with: .color(.white.opacity(0.16)))
        inner.fill(bead, with: .color(tone.opacity(0.55 * amount)))
        inner.fill(bead, with: .linearGradient(
            Gradient(colors: [.black.opacity(0.22), .clear, .white.opacity(0.28)]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        inner.stroke(bead, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.95), .white.opacity(0.15), .white.opacity(0.6)]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)),
            lineWidth: max(1.2, rect.width * 0.14))
    }

    /// Where the body is, for the glass that sits under the canvas.
    func pose(in size: CGSize) -> DewPose {
        let R = size.width * 0.3
        return DewPose(center: CGPoint(x: size.width / 2 + ox * R,
                                       y: size.height / 2 + particleOverhang / 2 + oy * R + R * 0.06),
                       R: R, sx: sx, sy: sy, tilt: tilt, lean: tipLean, morph: morph)
    }
}

struct DewPose: Equatable {
    var center: CGPoint
    var R: CGFloat
    var sx: CGFloat
    var sy: CGFloat
    var tilt: CGFloat
    var lean: CGFloat
    var morph: CGFloat
}

/// Dew's outline as a shape, centred on the bulb.
struct DropShape: Shape {
    var R: CGFloat
    var lean: CGFloat
    var morph: CGFloat

    func path(in rect: CGRect) -> Path {
        BotEngine.dropPath(rx: R * DewConst.rx, ry: R * DewConst.ry, R: R, lean: lean, morph: morph)
            .offsetBy(dx: rect.midX, dy: rect.midY)
    }
}

/// Real Liquid Glass in Dew's outline. It sits under the canvas and follows the body.
@available(macOS 26.0, *)
struct DewGlass: View {
    let pose: DewPose

    var body: some View {
        // A box centred on the bulb and tall enough for the tip
        Color.clear
            .frame(width: pose.R * 2.6, height: pose.R * 3.2)
            .glassEffect(Glass.clear, in: DropShape(R: pose.R, lean: pose.lean, morph: pose.morph))
            .scaleEffect(x: pose.sx, y: pose.sy)
            .rotationEffect(.radians(pose.tilt))
            .position(pose.center)
            .allowsHitTesting(false)
    }
}
