import SwiftUI

// MARK: - Mochi's props, reactions and idle antics
//
// Props are small things Mochi wears or holds because of what the Mac is doing: headphones while
// music plays, a mug while the Mac is kept awake, a nightcap late at night, a party hat when a
// timer is done. Each pops in and out on a spring and rides the body's tilt, hop and squash.

struct BotProps: OptionSet {
    let rawValue: Int
    static let headphones = BotProps(rawValue: 1 << 0)
    static let mug        = BotProps(rawValue: 1 << 1)
    static let nightcap   = BotProps(rawValue: 1 << 2)
    static let partyHat   = BotProps(rawValue: 1 << 3)
    static let sunglasses = BotProps(rawValue: 1 << 4)
    static let umbrella   = BotProps(rawValue: 1 << 5)
    static let scarf      = BotProps(rawValue: 1 << 6)
    static let laptop     = BotProps(rawValue: 1 << 7)    // Claude Code is working
    static let magnifier  = BotProps(rawValue: 1 << 8)    // …searching
    static let bandage    = BotProps(rawValue: 1 << 9)    // …hit an error
    static let pencil     = BotProps(rawValue: 1 << 10)   // a note was just written
    static let rainfall   = BotProps(rawValue: 1 << 11)   // weather around Mochi
    static let snowfall   = BotProps(rawValue: 1 << 12)

    /// Index of each prop in `BotEngine.propAmount`.
    static let order: [BotProps] = [.headphones, .mug, .nightcap, .partyHat, .sunglasses, .umbrella, .scarf,
                                    .laptop, .magnifier, .bandage, .pencil, .rainfall, .snowfall]

    static func index(_ prop: BotProps) -> Int { order.firstIndex(of: prop) ?? 0 }
}

/// One-shot reactions to something that just happened on the Mac.
enum BotReaction {
    case catchIt   // something landed on the clipboard: quick squash and a sparkle
    case zap       // power plugged in: happy jump, sparks
    case party     // timer done: star eyes, three hops, stars
    case scribble  // a note was saved: pencil out, head tilted in concentration
    case cheer     // a note was ticked off: small hop and a few stars
}

extension Notification.Name {
    static let botReact = Notification.Name("notchBuddy.botReact")
}

extension BotEngine {

    // MARK: Springs

    func updateProps(dt: Double) {
        let d = CGFloat(dt)
        for (i, prop) in BotProps.order.enumerated() {
            let on = props.contains(prop) || (prop == .pencil && CACurrentMediaTime() < scribbleUntil)
            let target: CGFloat = on ? 1 : 0
            guard target != propAmount[i] || propVel[i] != 0 else { continue }
            // Underdamped: pops past full size, settles
            propVel[i] += (260 * (target - propAmount[i]) - 15 * propVel[i]) * d
            propAmount[i] += propVel[i] * d
            if propAmount[i] <= 0 { propAmount[i] = 0; propVel[i] = 0 }
            if target == 1, abs(propAmount[i] - 1) < 0.002, abs(propVel[i]) < 0.02 { propAmount[i] = 1; propVel[i] = 0 }
        }
    }

    // MARK: Reactions

    func react(_ reaction: BotReaction) {
        guard morph < 0.3 else { return }
        let now = CACurrentMediaTime()
        switch reaction {
        case .catchIt:
            squash()
            emit(.spark, count: 2)
            eyeOverride = .happy
            eyeOverrideUntil = now + 0.7
        case .zap:
            eyeOverride = .star
            eyeOverrideUntil = now + 1.6
            emit(.spark, count: 6)
            anim("oy", keys: [
                TweenKey(target: -0.34, duration: 170, ease: Ease.out),
                TweenKey(target: 0,     duration: 360, ease: Ease.back),
            ])
            anim("blush", keys: [
                TweenKey(target: 0.8, duration: 200, ease: Ease.out),
                TweenKey(target: 0.8, duration: 900, ease: Ease.lin),
                TweenKey(target: 0,   duration: 400, ease: Ease.inOut),
            ])
        case .scribble:
            scribbleUntil = now + 1.5
            eyeOverride = .happy
            eyeOverrideUntil = now + 1.5
            anim("tilt", keys: [
                TweenKey(target: 0.10, duration: 200, ease: Ease.out),
                TweenKey(target: 0.10, duration: 1000, ease: Ease.lin),
                TweenKey(target: 0,    duration: 300, ease: Ease.inOut),
            ])
        case .cheer:
            eyeOverride = .happy
            eyeOverrideUntil = now + 1.0
            emit(.star, count: 3)
            anim("oy", keys: [
                TweenKey(target: -0.22, duration: 150, ease: Ease.out),
                TweenKey(target: 0,     duration: 300, ease: Ease.back),
            ])
        case .party:
            eyeOverride = .star
            eyeOverrideUntil = now + 2.6
            emit(.star, count: 7)
            var hops: [TweenKey] = []
            for _ in 0..<3 {
                hops.append(TweenKey(target: -0.30, duration: 170, ease: Ease.out))
                hops.append(TweenKey(target: 0,     duration: 230, ease: Ease.inOut))
            }
            anim("oy", keys: hops)
            anim("tilt", keys: [
                TweenKey(target: 0.14,  duration: 200, ease: Ease.inOut),
                TweenKey(target: -0.14, duration: 400, ease: Ease.inOut),
                TweenKey(target: 0.14,  duration: 400, ease: Ease.inOut),
                TweenKey(target: 0,     duration: 250, ease: Ease.inOut),
            ])
        }
    }

    // MARK: Idle antics

    /// Now and then, when nothing is going on, Mochi does something small on its own.
    func updateAntics(now: Double) {
        guard anticsEnabled, now > nextAntic else { return }
        guard state == .idle, mood == .none, morph < 0.05, tweens.isEmpty,
              eyeOverride == nil else {
            nextAntic = now + 4
            return
        }
        nextAntic = now + Double.random(in: 16...38)

        let hour = Calendar.current.component(.hour, from: Date())
        if (hour >= 23 || hour < 6) && Double.random(in: 0...1) < 0.45 {
            triggerEmote(.yawn, duration: 2.2, silent: true)
            return
        }
        switch Int.random(in: 0..<5) {
        case 0:   // look left, look right
            anim("yaw", keys: [
                TweenKey(target: -0.62, duration: 320, ease: Ease.inOut),
                TweenKey(target: -0.62, duration: 420, ease: Ease.lin),
                TweenKey(target: 0.62,  duration: 480, ease: Ease.inOut),
                TweenKey(target: 0.62,  duration: 420, ease: Ease.lin),
                TweenKey(target: 0,     duration: 320, ease: Ease.inOut),
            ])
        case 1:   // little hop, lands with a squash
            eyeOverride = .happy
            eyeOverrideUntil = now + 0.8
            anim("oy", keys: [
                TweenKey(target: -0.26, duration: 180, ease: Ease.out),
                TweenKey(target: 0,     duration: 240, ease: Ease.inOut),
            ]) { [weak self] in self?.squash() }
        case 2:
            triggerEmote(.wink, duration: 1.0, silent: true)
        case 3:   // happy wiggle
            eyeOverride = .happy
            eyeOverrideUntil = now + 0.9
            anim("tilt", keys: [
                TweenKey(target: 0.13,  duration: 120, ease: Ease.inOut),
                TweenKey(target: -0.13, duration: 180, ease: Ease.inOut),
                TweenKey(target: 0.10,  duration: 180, ease: Ease.inOut),
                TweenKey(target: -0.07, duration: 160, ease: Ease.inOut),
                TweenKey(target: 0,     duration: 160, ease: Ease.inOut),
            ])
            anim("blush", keys: [
                TweenKey(target: 0.6, duration: 200, ease: Ease.out),
                TweenKey(target: 0,   duration: 700, ease: Ease.inOut),
            ])
        default:  // long stretch, eyes shut
            eyeOverride = .closed
            eyeOverrideUntil = now + 1.3
            anim("sy", keys: [
                TweenKey(target: 1.15, duration: 450, ease: Ease.inOut),
                TweenKey(target: 1.15, duration: 400, ease: Ease.lin),
                TweenKey(target: 1,    duration: 350, ease: Ease.back),
            ])
            anim("sx", keys: [
                TweenKey(target: 0.92, duration: 450, ease: Ease.inOut),
                TweenKey(target: 0.92, duration: 400, ease: Ease.lin),
                TweenKey(target: 1,    duration: 350, ease: Ease.back),
            ])
        }
    }

    // MARK: Drawing

    /// Draws the props over the body. Call after `draw`, before `drawHandsAndExtras`.
    func drawProps(context: GraphicsContext, size: CGSize) {
        guard !isMini, morph < 0.3, propAmount.contains(where: { $0 > 0.01 }) else { return }
        let W = size.width, H = size.height
        let R = W * 0.3
        let rx = R * 1.14
        let ry = R * 0.88
        let cx = W / 2 + ox * R
        let cy = H / 2 + particleOverhang / 2 + oy * R + R * 0.06

        var ctx = context
        ctx.translateBy(x: cx, y: cy)
        if tilt != 0 { ctx.rotate(by: .radians(tilt)) }
        ctx.scaleBy(x: sx, y: sy)
        ctx.opacity = Double(1 - morph / 0.3)

        let lean = sin(yaw) * rx * 0.10          // props follow the head a little
        let t = CGFloat(CACurrentMediaTime() - t0)

        func amount(_ prop: BotProps) -> CGFloat { propAmount[BotProps.index(prop)] }
        let body = mochiPath(rx: rx, ry: ry, morph: morph, R: R)

        // Weather falls in the canvas itself, not on the tilted body
        if amount(.rainfall) > 0.01 { drawRain(context, amount: amount(.rainfall), cx: cx, cy: cy, R: R, t: t) }
        if amount(.snowfall) > 0.01 { drawSnow(context, amount: amount(.snowfall), cx: cx, cy: cy, R: R, t: t) }

        if amount(.scarf) > 0.01      { drawScarf(ctx, amount: amount(.scarf), body: body, R: R, rx: rx, ry: ry, t: t) }
        if amount(.bandage) > 0.01    { drawBandage(ctx, amount: amount(.bandage), R: R, rx: rx, ry: ry, lean: lean) }
        if amount(.sunglasses) > 0.01 { drawSunglasses(ctx, amount: amount(.sunglasses), body: body, R: R, rx: rx, ry: ry) }
        if amount(.nightcap) > 0.01   { drawNightcap(ctx, amount: amount(.nightcap), R: R, rx: rx, ry: ry, lean: lean, t: t) }
        if amount(.headphones) > 0.01 { drawHeadphones(ctx, amount: amount(.headphones), R: R, rx: rx, ry: ry, lean: lean) }
        if amount(.partyHat) > 0.01   { drawPartyHat(ctx, amount: amount(.partyHat), R: R, rx: rx, ry: ry, lean: lean, t: t) }
        if amount(.umbrella) > 0.01   { drawUmbrella(ctx, amount: amount(.umbrella), R: R, rx: rx, ry: ry, t: t) }
        if amount(.mug) > 0.01        { drawMug(ctx, amount: amount(.mug), R: R, rx: rx, ry: ry, t: t) }
        if amount(.laptop) > 0.01     { drawLaptop(ctx, amount: amount(.laptop), R: R, rx: rx, ry: ry, t: t) }
        if amount(.magnifier) > 0.01  { drawMagnifier(ctx, amount: amount(.magnifier), R: R, rx: rx, ry: ry, t: t) }
        if amount(.pencil) > 0.01     { drawPencil(ctx, amount: amount(.pencil), R: R, rx: rx, ry: ry, t: t) }
    }

    // MARK: Weather

    private func drawRain(_ base: GraphicsContext, amount: CGFloat, cx: CGFloat, cy: CGFloat, R: CGFloat, t: CGFloat) {
        var ctx = base
        ctx.opacity = Double(min(1, amount))
        // Only beside the umbrella: Mochi stays dry
        for i in 0..<10 {
            let side: CGFloat = i % 2 == 0 ? -1 : 1
            let lane = CGFloat(i / 2)
            let x = cx + side * R * (1.34 + lane * 0.075)
            let phase = (t * (1.5 + lane * 0.13) + CGFloat(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let y = cy - R * 1.5 + phase * R * 2.6
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - R * 0.04, y: y + R * 0.20))
            ctx.stroke(drop, with: .color(Color(hex: "#7DD3FC").opacity(Double(0.85 * sin(phase * .pi)))),
                       style: StrokeStyle(lineWidth: max(1, R * 0.045), lineCap: .round))
        }
    }

    private func drawSnow(_ base: GraphicsContext, amount: CGFloat, cx: CGFloat, cy: CGFloat, R: CGFloat, t: CGFloat) {
        var ctx = base
        ctx.opacity = Double(min(1, amount))
        for i in 0..<12 {
            let seed = CGFloat(i) * 0.618
            let phase = (t * (0.16 + seed.truncatingRemainder(dividingBy: 0.11)) + seed).truncatingRemainder(dividingBy: 1)
            let x = cx + (seed.truncatingRemainder(dividingBy: 1) * 2 - 1) * R * 1.55 + sin(t * 1.2 + seed * 9) * R * 0.10
            let y = cy - R * 1.6 + phase * R * 2.7
            let size = R * (0.05 + (seed * 3).truncatingRemainder(dividingBy: 0.045))
            ctx.fill(Path(ellipseIn: CGRect(x: x - size, y: y - size, width: size * 2, height: size * 2)),
                     with: .color(Color.white.opacity(Double(0.9 * sin(phase * .pi)))))
        }
    }

    private func drawUmbrella(_ base: GraphicsContext, amount: CGFloat, R: CGFloat, rx: CGFloat, ry: CGFloat, t: CGFloat) {
        var ctx = base
        // Held at the right, canopy over the head; opens from the handle
        let grip = CGPoint(x: rx * 0.62, y: ry * 0.62)
        ctx.translateBy(x: grip.x, y: grip.y)
        ctx.rotate(by: .radians(-0.12 + sin(t * 1.3) * 0.025))
        ctx.scaleBy(x: amount, y: amount)

        let top = CGPoint(x: -rx * 0.50, y: -ry * 1.98)          // canopy centre, in grip space
        // Shaft and hook
        var shaft = Path()
        shaft.move(to: CGPoint(x: top.x, y: top.y))
        shaft.addLine(to: CGPoint(x: -R * 0.02, y: R * 0.10))
        shaft.addQuadCurve(to: CGPoint(x: R * 0.20, y: R * 0.10), control: CGPoint(x: R * 0.09, y: R * 0.30))
        ctx.stroke(shaft, with: .color(Color(hex: "#6B7280")), style: StrokeStyle(lineWidth: R * 0.07, lineCap: .round, lineJoin: .round))

        // Canopy: a dome with a scalloped hem
        let w = R * 2.5, h = R * 0.62
        let left = CGPoint(x: top.x - w / 2, y: top.y + h)
        var canopy = Path()
        canopy.move(to: left)
        canopy.addCurve(to: CGPoint(x: top.x + w / 2, y: top.y + h),
                        control1: CGPoint(x: top.x - w * 0.46, y: top.y - h * 0.42),
                        control2: CGPoint(x: top.x + w * 0.46, y: top.y - h * 0.42))
        let scallops = 4
        for i in (0..<scallops).reversed() {
            let x1 = left.x + w * CGFloat(i) / CGFloat(scallops)
            let x2 = left.x + w * CGFloat(i + 1) / CGFloat(scallops)
            canopy.addQuadCurve(to: CGPoint(x: x1, y: left.y), control: CGPoint(x: (x1 + x2) / 2, y: left.y - h * 0.30))
        }
        canopy.closeSubpath()
        ctx.fill(canopy, with: .linearGradient(Gradient(colors: [Color(hex: "#FDA4AF"), Color(hex: "#E11D48")]),
                                               startPoint: CGPoint(x: left.x, y: top.y), endPoint: CGPoint(x: top.x + w / 2, y: left.y)))
        // Ribs
        var ribs = ctx
        ribs.clip(to: canopy)
        for i in 1..<scallops {
            let x = left.x + w * CGFloat(i) / CGFloat(scallops)
            var rib = Path()
            rib.move(to: CGPoint(x: top.x, y: top.y - h * 0.065))
            rib.addQuadCurve(to: CGPoint(x: x, y: left.y), control: CGPoint(x: (top.x + x) / 2 + (x - top.x) * 0.25, y: top.y))
            ribs.stroke(rib, with: .color(Color.white.opacity(0.35)), lineWidth: max(0.6, R * 0.025))
        }
        ctx.stroke(canopy, with: .color(Color.black.opacity(0.10)), lineWidth: max(0.5, R * 0.02))
        ctx.fill(Path(ellipseIn: CGRect(x: top.x - R * 0.06, y: top.y - h * 0.065 - R * 0.11, width: R * 0.12, height: R * 0.14)),
                 with: .color(Color(hex: "#E5E7EB")))
    }

    private func drawScarf(_ base: GraphicsContext, amount: CGFloat, body: Path, R: CGFloat, rx: CGFloat, ry: CGFloat, t: CGFloat) {
        var ctx = base
        ctx.opacity *= Double(min(1, amount * 1.3))
        let y = ry * 0.68       // low, so the eyes stay clear even when Mochi looks down
        // The tail hangs outside the body, swaying
        let sway = sin(t * 1.8) * R * 0.05
        var tail = Path()
        tail.move(to: CGPoint(x: rx * 0.50, y: y + R * 0.02))
        tail.addQuadCurve(to: CGPoint(x: rx * 0.74 + sway, y: y + R * 0.52 * amount), control: CGPoint(x: rx * 0.80, y: y + R * 0.20))
        ctx.stroke(tail, with: .color(Color(hex: "#DC2626")), style: StrokeStyle(lineWidth: R * 0.22, lineCap: .butt))
        var fringe = Path()
        fringe.move(to: CGPoint(x: rx * 0.74 + sway - R * 0.11, y: y + R * 0.52 * amount))
        fringe.addLine(to: CGPoint(x: rx * 0.74 + sway + R * 0.11, y: y + R * 0.52 * amount))
        ctx.stroke(fringe, with: .color(Color.white), style: StrokeStyle(lineWidth: R * 0.07, lineCap: .round, dash: [R * 0.045, R * 0.05]))

        var wrap = ctx
        wrap.clip(to: body)
        var band = Path()
        band.move(to: CGPoint(x: -rx * 1.1, y: y - R * 0.04))
        band.addQuadCurve(to: CGPoint(x: rx * 1.1, y: y - R * 0.04), control: CGPoint(x: 0, y: y + R * 0.22))
        wrap.stroke(band, with: .linearGradient(Gradient(colors: [Color(hex: "#F87171"), Color(hex: "#DC2626")]),
                                                startPoint: CGPoint(x: 0, y: y - R * 0.2), endPoint: CGPoint(x: 0, y: y + R * 0.3)),
                    lineWidth: R * 0.24)
        wrap.stroke(band, with: .color(Color.white.opacity(0.85)),
                    style: StrokeStyle(lineWidth: R * 0.24, dash: [R * 0.07, R * 0.26]))
    }

    private func drawSunglasses(_ base: GraphicsContext, amount: CGFloat, body: Path, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        var ctx = base
        ctx.clip(to: body)
        ctx.opacity *= Double(min(1, amount * 1.5))
        // Slide down from the forehead onto the eyes
        ctx.translateBy(x: 0, y: -(1 - min(1, amount)) * R * 0.55)

        let cp = cos(MochiConst.eyeP + pitch)
        let ey = -sin(MochiConst.eyeP + pitch) * ry
        let w = R * 0.60, h = R * 0.40
        var centres: [CGFloat] = []
        for sd in [CGFloat(-1), 1] { centres.append(sin(sd * MochiConst.eyeSp + yaw) * cp * rx) }
        // Bridge and arms first, lenses on top
        var frame = Path()
        frame.move(to: CGPoint(x: centres[0], y: ey - h * 0.18))
        frame.addLine(to: CGPoint(x: centres[1], y: ey - h * 0.18))
        frame.move(to: CGPoint(x: centres[0] - w / 2, y: ey - h * 0.2))
        frame.addLine(to: CGPoint(x: -rx * 1.1, y: ey - h * 0.45))
        frame.move(to: CGPoint(x: centres[1] + w / 2, y: ey - h * 0.2))
        frame.addLine(to: CGPoint(x: rx * 1.1, y: ey - h * 0.45))
        ctx.stroke(frame, with: .color(Color(hex: "#111318")), style: StrokeStyle(lineWidth: R * 0.07, lineCap: .round))
        for x in centres {
            let rect = CGRect(x: x - w / 2, y: ey - h / 2, width: w, height: h)
            let lens = Path(roundedRect: rect, cornerSize: CGSize(width: w * 0.22, height: h * 0.45), style: .continuous)
            ctx.fill(lens, with: .linearGradient(Gradient(colors: [Color(hex: "#2B2F3A"), Color(hex: "#0B0C10")]),
                                                 startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            var shine = ctx
            shine.clip(to: lens)
            var streak = Path()
            streak.move(to: CGPoint(x: rect.minX + w * 0.15, y: rect.maxY))
            streak.addLine(to: CGPoint(x: rect.minX + w * 0.55, y: rect.minY))
            shine.stroke(streak, with: .color(Color.white.opacity(0.38)), lineWidth: w * 0.14)
            ctx.stroke(lens, with: .color(Color.white.opacity(0.18)), lineWidth: max(0.5, R * 0.02))
        }
    }

    // MARK: Claude Code states

    private func drawLaptop(_ base: GraphicsContext, amount: CGFloat, R: CGFloat, rx: CGFloat, ry: CGFloat, t: CGFloat) {
        var ctx = base
        // Rises from below, lid toward us
        ctx.translateBy(x: 0, y: ry * 0.80 + (1 - min(1, amount)) * R * 0.6)
        ctx.opacity *= Double(min(1, amount * 1.5))
        ctx.rotate(by: .radians(-tilt * 0.7))

        let w = R * 1.20, h = R * 0.66
        // Screen light on Mochi's face
        ctx.fill(Path(ellipseIn: CGRect(x: -w * 0.6, y: -h * 1.5, width: w * 1.2, height: h * 1.5)),
                 with: .radialGradient(Gradient(colors: [Color(hex: "#7DD3FC").opacity(0.30 + 0.06 * Double(sin(t * 9))), .clear]),
                                       center: CGPoint(x: 0, y: -h * 0.55), startRadius: 0, endRadius: w * 0.62))
        // Hands tapping at the sides
        for sd in [CGFloat(-1), 1] {
            let tap = max(0, sin(t * 15 + (sd > 0 ? 1.7 : 0))) * R * 0.07
            let hand = Path(ellipseIn: CGRect(x: sd * w * 0.60 - R * 0.13, y: h * 0.36 - tap, width: R * 0.26, height: R * 0.20))
            ctx.fill(hand, with: .color(Color(cgColor: bodyColor ?? MochiConst.baseTop)))
            ctx.stroke(hand, with: .color(Color.black.opacity(0.10)), lineWidth: max(0.5, R * 0.02))
        }
        let lid = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                       cornerSize: CGSize(width: R * 0.09, height: R * 0.09), style: .continuous)
        ctx.fill(lid, with: .linearGradient(Gradient(colors: [Color(hex: "#E9EBF0"), Color(hex: "#AEB3BF")]),
                                            startPoint: CGPoint(x: -w / 2, y: -h / 2), endPoint: CGPoint(x: w / 2, y: h / 2)))
        ctx.stroke(lid, with: .color(Color.black.opacity(0.14)), lineWidth: max(0.5, R * 0.02))
        // A glowing heart where the logo would be
        var logo = ctx
        logo.translateBy(x: 0, y: -h * 0.02)
        logo.fill(heartShape(size: R * 0.12), with: .color(Color.white.opacity(0.75 + 0.2 * Double(sin(t * 2.2)))))
        // Base
        let baseRect = CGRect(x: -w * 0.58, y: h / 2 - R * 0.01, width: w * 1.16, height: R * 0.10)
        ctx.fill(Path(roundedRect: baseRect, cornerRadius: R * 0.05, style: .continuous), with: .color(Color(hex: "#9197A6")))
    }

    private func drawMagnifier(_ base: GraphicsContext, amount: CGFloat, R: CGFloat, rx: CGFloat, ry: CGFloat, t: CGFloat) {
        var ctx = base
        // Sweeps with the scanning eyes
        ctx.translateBy(x: rx * 0.34 + sin(t * 2.6) * R * 0.30, y: ry * 0.16 + cos(t * 2.6) * R * 0.05)
        ctx.scaleBy(x: amount, y: amount)
        ctx.rotate(by: .radians(-tilt))
        let r = R * 0.40
        var handle = Path()
        handle.move(to: CGPoint(x: r * 0.72, y: r * 0.72))
        handle.addLine(to: CGPoint(x: r * 1.75, y: r * 1.75))
        ctx.stroke(handle, with: .color(Color(hex: "#7C4A21")), style: StrokeStyle(lineWidth: R * 0.15, lineCap: .round))
        ctx.stroke(handle, with: .color(Color(hex: "#B97A45")), style: StrokeStyle(lineWidth: R * 0.07, lineCap: .round))
        let lens = Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        ctx.fill(lens, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.10), Color(hex: "#BAE6FD").opacity(0.42)]),
                                             center: .zero, startRadius: 0, endRadius: r))
        var shine = Path()
        shine.addArc(center: .zero, radius: r * 0.66, startAngle: .degrees(200), endAngle: .degrees(255), clockwise: false)
        ctx.stroke(shine, with: .color(Color.white.opacity(0.85)), style: StrokeStyle(lineWidth: R * 0.06, lineCap: .round))
        ctx.stroke(lens, with: .color(Color(hex: "#3F4654")), lineWidth: R * 0.10)
        ctx.stroke(lens, with: .color(Color(hex: "#C9CDD6")), lineWidth: R * 0.045)
    }

    private func drawBandage(_ base: GraphicsContext, amount: CGFloat, R: CGFloat, rx: CGFloat, ry: CGFloat, lean: CGFloat) {
        var ctx = base
        ctx.translateBy(x: -rx * 0.46 + lean, y: -ry * 0.52)
        ctx.scaleBy(x: amount, y: amount)
        for angle in [0.62, -0.62] {
            var strip = ctx
            strip.rotate(by: .radians(angle))
            let rect = CGRect(x: -R * 0.30, y: -R * 0.095, width: R * 0.60, height: R * 0.19)
            let plaster = Path(roundedRect: rect, cornerRadius: R * 0.095, style: .continuous)
            strip.fill(plaster, with: .color(Color(hex: "#F3C9A4")))
            strip.stroke(plaster, with: .color(Color.black.opacity(0.12)), lineWidth: max(0.5, R * 0.018))
            strip.fill(Path(roundedRect: rect.insetBy(dx: R * 0.19, dy: R * 0.03), cornerRadius: R * 0.03),
                       with: .color(Color(hex: "#FBE6D1")))
        }
    }

    private func drawPencil(_ base: GraphicsContext, amount: CGFloat, R: CGFloat, rx: CGFloat, ry: CGFloat, t: CGFloat) {
        var ctx = base
        // Scribbling: quick small strokes
        ctx.translateBy(x: rx * 0.86 + sin(t * 23) * R * 0.07, y: ry * 0.52 + cos(t * 17) * R * 0.035)
        ctx.scaleBy(x: amount, y: amount)
        ctx.rotate(by: .radians(0.55))
        let w = R * 0.17, h = R * 0.72
        // Tip down (toward +y)
        var wood = Path()
        wood.move(to: CGPoint(x: -w / 2, y: h * 0.30))
        wood.addLine(to: CGPoint(x: 0, y: h * 0.50))
        wood.addLine(to: CGPoint(x: w / 2, y: h * 0.30))
        wood.closeSubpath()
        ctx.fill(wood, with: .color(Color(hex: "#F1D2A9")))
        var lead = Path()
        lead.move(to: CGPoint(x: -w * 0.18, y: h * 0.43))
        lead.addLine(to: CGPoint(x: 0, y: h * 0.50))
        lead.addLine(to: CGPoint(x: w * 0.18, y: h * 0.43))
        lead.closeSubpath()
        ctx.fill(lead, with: .color(Color(hex: "#2B2D33")))
        ctx.fill(Path(CGRect(x: -w / 2, y: -h * 0.36, width: w, height: h * 0.66)), with: .color(Color(hex: "#FACC15")))
        ctx.fill(Path(CGRect(x: -w / 2, y: -h * 0.36, width: w * 0.34, height: h * 0.66)), with: .color(Color(hex: "#FDE68A")))
        ctx.fill(Path(CGRect(x: -w / 2, y: -h * 0.41, width: w, height: h * 0.06)), with: .color(Color(hex: "#C9CDD6")))
        ctx.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h * 0.52, width: w, height: h * 0.12), cornerRadius: w * 0.3),
                 with: .color(Color(hex: "#F9A8D4")))
    }

    private func drawHeadphones(_ base: GraphicsContext, amount: CGFloat, R: CGFloat, rx: CGFloat, ry: CGFloat, lean: CGFloat) {
        var ctx = base
        ctx.opacity *= Double(min(1, amount * 1.4))
        // Drops onto the head from above
        ctx.translateBy(x: lean, y: -(1 - amount) * R * 0.55)

        var band = Path()
        band.move(to: CGPoint(x: -rx * 1.0, y: -ry * 0.05))
        band.addCurve(to: CGPoint(x: rx * 1.0, y: -ry * 0.05),
                      control1: CGPoint(x: -rx * 1.10, y: -ry * 1.50),
                      control2: CGPoint(x: rx * 1.10, y: -ry * 1.50))
        ctx.stroke(band, with: .color(Color(hex: "#8E94A3")), style: StrokeStyle(lineWidth: R * 0.17, lineCap: .round))
        ctx.stroke(band, with: .linearGradient(Gradient(colors: [Color(hex: "#F4F5F8"), Color(hex: "#C5CAD6")]),
                                               startPoint: CGPoint(x: 0, y: -ry * 1.4), endPoint: CGPoint(x: 0, y: 0)),
                   style: StrokeStyle(lineWidth: R * 0.11, lineCap: .round))

        let turn = sin(yaw)
        for sd in [CGFloat(-1), 1] {
            // The cup on the side Mochi turns toward shows more of itself
            let w = R * 0.36 * (1 + sd * turn * 0.28), h = R * 0.66
            let rect = CGRect(x: sd * rx * 1.0 - w / 2, y: ry * 0.06 - h / 2, width: w, height: h)
            let cup = Path(roundedRect: rect, cornerRadius: min(w, h) * 0.42, style: .continuous)
            ctx.fill(cup, with: .linearGradient(Gradient(colors: [Color(hex: "#FF8CC6"), Color(hex: "#EC4899")]),
                                                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            let inner = rect.insetBy(dx: w * 0.26, dy: h * 0.2)
            ctx.fill(Path(roundedRect: inner, cornerRadius: inner.width * 0.5, style: .continuous),
                     with: .color(Color(hex: "#BE185D").opacity(0.75)))
            ctx.stroke(cup, with: .color(Color.white.opacity(0.35)), lineWidth: max(0.5, R * 0.02))
        }
    }

    private func drawMug(_ base: GraphicsContext, amount: CGFloat, R: CGFloat, rx: CGFloat, ry: CGFloat, t: CGFloat) {
        var ctx = base
        // Lower left, handle outward (the right side is where the island's text starts)
        ctx.translateBy(x: -rx * 0.80, y: ry * 0.68)
        ctx.scaleBy(x: -amount, y: amount)
        ctx.rotate(by: .radians(tilt * 0.6))        // the drink stays level-ish

        let w = R * 0.56, h = R * 0.50
        // Steam: two wisps that wander as they rise
        for i in 0..<2 {
            let x0 = (CGFloat(i) - 0.5) * w * 0.36
            var wisp = Path()
            for step in 0...10 {
                let k = CGFloat(step) / 10
                let x = x0 + sin(k * 5.5 + t * 2.4 + CGFloat(i) * 1.9) * R * 0.07 * k
                let y = -h / 2 - R * 0.06 - k * R * 0.50
                if step == 0 { wisp.move(to: CGPoint(x: x, y: y)) } else { wisp.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(wisp, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0)]),
                                                   startPoint: CGPoint(x: 0, y: -h / 2), endPoint: CGPoint(x: 0, y: -h / 2 - R * 0.58)),
                       style: StrokeStyle(lineWidth: max(0.8, R * 0.05), lineCap: .round, lineJoin: .round))
        }

        // Handle
        var handle = Path()
        handle.addEllipse(in: CGRect(x: w / 2 - R * 0.10, y: -h * 0.26, width: R * 0.26, height: h * 0.56))
        ctx.stroke(handle, with: .color(Color(hex: "#EA580C")), lineWidth: R * 0.075)

        let body = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                        cornerSize: CGSize(width: R * 0.11, height: R * 0.11), style: .continuous)
        ctx.fill(body, with: .linearGradient(Gradient(colors: [Color(hex: "#FDBA74"), Color(hex: "#F97316")]),
                                             startPoint: CGPoint(x: -w / 2, y: -h / 2), endPoint: CGPoint(x: w / 2, y: h / 2)))
        ctx.stroke(body, with: .color(Color.black.opacity(0.12)), lineWidth: max(0.5, R * 0.02))
        // Coffee
        ctx.fill(Path(ellipseIn: CGRect(x: -w * 0.40, y: -h / 2 - R * 0.035, width: w * 0.80, height: R * 0.12)),
                 with: .color(Color(hex: "#5B3418")))
        // A heart on the mug
        var heartCtx = ctx
        heartCtx.translateBy(x: 0, y: h * 0.06)
        heartCtx.fill(heartShape(size: R * 0.105), with: .color(.white.opacity(0.92)))
    }

    private func drawNightcap(_ base: GraphicsContext, amount: CGFloat, R: CGFloat, rx: CGFloat, ry: CGFloat, lean: CGFloat, t: CGFloat) {
        var ctx = base
        ctx.translateBy(x: -rx * 0.20 + lean, y: -ry * 0.90)
        ctx.rotate(by: .radians(-0.24))
        ctx.scaleBy(x: amount, y: amount)

        let sway = sin(t * 1.5) * R * 0.05
        let tip = CGPoint(x: R * 1.02, y: -R * 0.02 + sway)
        var cone = Path()
        cone.move(to: CGPoint(x: -R * 0.60, y: 0))
        cone.addCurve(to: tip, control1: CGPoint(x: -R * 0.42, y: -R * 1.05), control2: CGPoint(x: R * 0.62, y: -R * 1.05))
        cone.addQuadCurve(to: CGPoint(x: R * 0.60, y: 0), control: CGPoint(x: R * 0.70, y: -R * 0.40))
        cone.closeSubpath()
        ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color(hex: "#A5B4FC"), Color(hex: "#4F46E5")]),
                                             startPoint: CGPoint(x: -R * 0.4, y: -R * 0.9), endPoint: CGPoint(x: R * 0.7, y: 0)))
        // Little stars on the cloth
        var stars = ctx
        stars.clip(to: cone)
        for (x, y, s) in [(-0.18, -0.38, 0.085), (0.26, -0.56, 0.065), (0.50, -0.26, 0.055)] as [(CGFloat, CGFloat, CGFloat)] {
            var one = stars
            one.translateBy(x: R * x, y: R * y)
            one.fill(starShape(outer: R * s, inner: R * s * 0.45), with: .color(Color(hex: "#FDE68A")))
        }

        let band = Path(roundedRect: CGRect(x: -R * 0.68, y: -R * 0.11, width: R * 1.36, height: R * 0.25),
                        cornerRadius: R * 0.125, style: .continuous)
        ctx.fill(band, with: .color(Color(hex: "#F4F5F8")))
        ctx.stroke(band, with: .color(Color.black.opacity(0.10)), lineWidth: max(0.5, R * 0.02))
        let pom = Path(ellipseIn: CGRect(x: tip.x - R * 0.15, y: tip.y - R * 0.15, width: R * 0.30, height: R * 0.30))
        ctx.fill(pom, with: .color(Color(hex: "#F4F5F8")))
        ctx.stroke(pom, with: .color(Color.black.opacity(0.10)), lineWidth: max(0.5, R * 0.02))
    }

    private func drawPartyHat(_ base: GraphicsContext, amount: CGFloat, R: CGFloat, rx: CGFloat, ry: CGFloat, lean: CGFloat, t: CGFloat) {
        var ctx = base
        ctx.translateBy(x: rx * 0.24 + lean, y: -ry * 0.86)
        ctx.rotate(by: .radians(0.22 + sin(t * 3.1) * 0.03))
        ctx.scaleBy(x: amount, y: amount)

        let apex = CGPoint(x: 0, y: -R * 1.0)
        var cone = Path()
        cone.move(to: CGPoint(x: -R * 0.44, y: 0))
        cone.addLine(to: apex)
        cone.addLine(to: CGPoint(x: R * 0.44, y: 0))
        cone.addQuadCurve(to: CGPoint(x: -R * 0.44, y: 0), control: CGPoint(x: 0, y: R * 0.16))
        cone.closeSubpath()
        ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color(hex: "#F9A8D4"), Color(hex: "#DB2777")]),
                                             startPoint: CGPoint(x: -R * 0.4, y: -R * 0.6), endPoint: CGPoint(x: R * 0.4, y: 0)))
        var stripes = ctx
        stripes.clip(to: cone)
        for i in 0..<4 {
            let y = -R * (0.12 + CGFloat(i) * 0.27)
            var stripe = Path()
            stripe.move(to: CGPoint(x: -R * 0.6, y: y + R * 0.14))
            stripe.addLine(to: CGPoint(x: R * 0.6, y: y - R * 0.14))
            stripes.stroke(stripe, with: .color(Color(hex: i % 2 == 0 ? "#FDE047" : "#67E8F9")), lineWidth: R * 0.085)
        }
        // Brim and pom-pom
        var brim = Path()
        brim.move(to: CGPoint(x: -R * 0.44, y: 0))
        brim.addQuadCurve(to: CGPoint(x: R * 0.44, y: 0), control: CGPoint(x: 0, y: R * 0.16))
        ctx.stroke(brim, with: .color(Color.white), style: StrokeStyle(lineWidth: R * 0.09, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: apex.x - R * 0.13, y: apex.y - R * 0.13, width: R * 0.26, height: R * 0.26)),
                 with: .color(Color(hex: "#FDE047")))
    }
}
