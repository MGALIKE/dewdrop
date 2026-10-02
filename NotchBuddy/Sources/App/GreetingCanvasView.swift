import SwiftUI

// MARK: - Timing constants (mirrors greeting-v2.html T = {...})

private enum GT {
    static let grow:     Double = 0.45
    static let squint0:  Double = 0.60
    static let squint1:  Double = 0.82
    static let dip0:     Double = 1.25
    static let dip1:     Double = 1.40
    static let pop0:     Double = 1.36
    static let pop1:     Double = 1.52
    static let content0: Double = 2.45
    static let content1: Double = 2.58
    static let tuck0:    Double = 2.58
    static let tuck1:    Double = 2.80
    static let badge:    Double = 2.72
    static let down0:    Double = 2.85
    static let down1:    Double = 3.20
    static let blink2:   Double = 3.80
    static let tint0:    Double = 3.85
    static let tint1:    Double = 4.15
    static let end:      Double = 4.60   // animation done; greetComplete fires here
    static let autoLeave:Double = 4.90   // visual collapse trigger (no hover)
    static let COLLAPSE: Double = 0.34
}

// MARK: - Geometry constants (640×150 reference space)

private let GC0     = CGPoint(x: 320, y: 90)   // Dew center
private let GHB:    CGFloat = 58                // body height at full size
private let GASP:   CGFloat = 1.34             // body width/height ratio
private let GEAR_X: CGFloat = 40               // ear x from small island left edge (matches BotPlacement compact x=40)
private let GEAR_HB:CGFloat = 17               // ear body height
private let GCARD   = CGRect(x: 10, y: 36, width: 620, height: 104)
private let GCARD_R:CGFloat = 20

// MARK: - Easing (mirrors E = {...})

private enum GE {
    static func out(_ t: Double)   -> Double { 1 - pow(1 - t, 3) }
    static func easeIn(_ t: Double)-> Double { t * t * t }
    static func inOut(_ t: Double) -> Double {
        t < 0.5 ? 4*t*t*t : 1 - pow(-2*t+2, 3)/2
    }
    static func back(_ t: Double)  -> Double {
        let c1=1.70158, c3=c1+1
        return 1 + c3*pow(t-1,3) + c1*pow(t-1,2)
    }
}

private func gClamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }
private func gLerp(_ a: Double, _ b: Double, _ t: Double)  -> Double { a + (b - a) * t }
private func gSeg(_ t: Double, _ a: Double, _ b: Double)   -> Double { gClamp((t-a)/(b-a), 0, 1) }
private func gLerpF(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b-a)*t }

// MARK: - Pose

private enum GEyeType { case dot, happy, content }

private struct GreetPose {
    var hb, x, y, sx, sy, tilt: Double
    var eye: GEyeType; var open, eyeRoll: Double
    var lookX, lookY: Double
    var handL, handR, wave: Double
    var badge, tint, halo, haloBlue, minis, fx: Double
    var header, card: Double
    // island dims (only for reference — not drawn here, just used for clip ref)
    var iw, ih: Double
}

// MARK: - Particles (seeded LCG matching JS reference seed=7)

private struct GRingDot { let a, j, s, al: Double }
private struct GRing    { let t0: Double; let dots: [GRingDot] }
private struct GStreak  { let a, sp, len, t0: Double; let col: String }

private let greetParticles: (rings: [GRing], streaks: [GStreak]) = {
    var seed: UInt32 = 7
    func rnd() -> Double {
        seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
        return Double(seed) / Double(0x7fff_ffff)
    }
    let rings = [0.10, 0.20, 0.30, 0.45, 0.60].map { t0 in
        GRing(t0: t0, dots: (0..<170).map { _ in
            GRingDot(a: rnd() * .pi * 2, j: (rnd()-0.5)*0.22, s: 0.7+rnd()*0.9, al: 0.45+rnd()*0.55)
        })
    }
    let cols = ["#3B9EFF","#F29B38","#FF5A4E","#2EC4A0","#A78BFA"]
    let streaks = (0..<16).map { i in
        GStreak(a: Double(i)/16 * .pi * 2+(rnd()-0.5)*0.3, sp: 230+rnd()*260,
                len: 6+rnd()*9, t0: 0.08+rnd()*0.14, col: cols[i%5])
    }
    return (rings, streaks)
}()

// MARK: - Pose computation

private func greetPose(_ t: Double, compact: IslandRestingLayout) -> GreetPose {
    // island size interpolation (used as reference for clip, not drawn)
    let gx = gSeg(t, 0, 0.5)
    let g  = sin(.pi*gx/2) + 0.04*sin(.pi*gx)*gx
    let iw = gLerp(Double(compact.width - 160), 640, g)
    let ih = gLerp(Double(compact.height), 150, g)

    // body grows with back-ease (tiny → full size)
    let gg = GE.back(gSeg(t, 0.02, GT.grow))
    var hb = gLerp(3, Double(GHB), gg)
    var x  = Double(GC0.x)
    var y  = gLerp(Double(compact.botCenterY), Double(GC0.y), GE.out(gSeg(t, 0.02, GT.grow)))
    var sx = 1.0, sy = 1.0, tilt = 0.0

    // dip (1.25→1.52): body squishes forward
    if t >= GT.dip0 && t < GT.pop1 {
        let k = sin(.pi*gSeg(t, GT.dip0, GT.pop1))
        y += hb*0.22*k; sy = 1-0.06*k; sx = 1+0.04*k
    }
    // wave sway (1.52→2.80)
    if t >= GT.pop1 && t < GT.tuck1 {
        let w = t - GT.pop1
        let fade = 1 - gSeg(t, GT.tuck0, GT.tuck1)
        x += sin(w*2 * .pi*0.9)*hb*Double(GASP)*0.05*fade
        tilt = sin(w*2 * .pi*0.9+0.6)*0.05*fade
        y += sin(w*2 * .pi*1.8)*0.8*fade
    }
    // settle (2.58→3.20)
    if t >= GT.tuck0 && t < GT.down1 {
        y += hb*0.12*sin(.pi*gSeg(t, GT.tuck0, GT.down1))
    }

    // eyes
    var eye: GEyeType = .dot
    if t >= GT.squint0 && t < GT.squint1 { eye = .happy }
    if t >= GT.content0 && t < GT.content1 { eye = .content }
    if t >= GT.down0 && t < GT.down1 { eye = .content }
    var eyeRoll = 0.0
    if t >= GT.dip0 && t < GT.pop1 { eyeRoll = sin(.pi*gSeg(t, GT.dip0, GT.pop1)) }
    let blink: (Double) -> Double = { tb in
        let k = gSeg(t, tb, tb+0.12); return (k>0&&k<1) ? 1-sin(.pi*k)*0.94 : 1
    }
    let openVal = min(blink(1.95), blink(GT.blink2))

    // look
    var lookX = 0.0, lookY = 0.0
    if t >= GT.squint1 && t < GT.dip0 { lookY = -0.2 }
    if t >= GT.pop1 && t < GT.content0 { lookX = 0.55; lookY = -0.45 }
    if t >= GT.content0 && t < GT.down1 { lookX = -0.3; lookY = 0.6 }
    if t >= GT.down1 {
        let k = GE.inOut(gSeg(t, GT.down1, GT.down1+0.35))
        lookX = gLerp(-0.3, 0, k); lookY = gLerp(0.6, 0, k)
    }

    // hands
    let handL = t < GT.tuck0
        ? GE.back(gSeg(t, GT.pop0, GT.pop0+0.14))
        : 1 - GE.easeIn(gSeg(t, GT.tuck0, GT.tuck1-0.03))
    let handR = t < GT.tuck0
        ? GE.back(gSeg(t, GT.pop0+0.04, GT.pop0+0.18))
        : 1 - GE.easeIn(gSeg(t, GT.tuck0+0.03, GT.tuck1))
    let wave = (t >= GT.pop1 && t < GT.tuck0) ? t - GT.pop1 : -1.0

    return GreetPose(
        hb: hb, x: x, y: y, sx: sx, sy: sy, tilt: tilt,
        eye: eye, open: openVal, eyeRoll: eyeRoll,
        lookX: lookX, lookY: lookY,
        handL: handL, handR: handR, wave: wave,
        badge: GE.back(gSeg(t, GT.badge, GT.badge+0.28)),
        tint:  0.6*GE.inOut(gSeg(t, GT.tint0, GT.tint1)),
        halo:  GE.out(gSeg(t, 0.3, 0.7)),
        haloBlue: gSeg(t, GT.tint0, GT.tint1),
        minis: 0, fx: 1,
        header: gSeg(t, 0.35, 0.6), card: gSeg(t, 0.18, 0.45),
        iw: iw, ih: ih
    )
}

private func smallPose(_ compact: IslandRestingLayout) -> GreetPose {
    let sw = Double(compact.width)
    return GreetPose(
        hb: Double(GEAR_HB * compact.botDiameter / 20),
        x: 320 - sw/2 + Double(GEAR_X),
        y: Double(compact.botCenterY),
        sx: 1, sy: 1, tilt: 0,
        eye: .dot, open: 1, eyeRoll: 0,
        lookX: 0, lookY: 0,
        handL: 0, handR: 0, wave: -1,
        badge: 1, tint: 0.6, halo: 0.6, haloBlue: 1,
        minis: 1, fx: 1,
        header: 0, card: 0,
        iw: sw, ih: Double(compact.height)
    )
}

private func pose(_ t: Double, tc: Double, compact: IslandRestingLayout) -> GreetPose {
    if t < tc { return greetPose(min(t, GT.end + 10), compact: compact) }
    let a = greetPose(tc, compact: compact)
    let b = smallPose(compact)
    let e = GE.inOut(gSeg(t, tc, tc + GT.COLLAPSE))
    var p = a
    p.iw = gLerp(a.iw, b.iw, e); p.ih = gLerp(a.ih, b.ih, e)
    p.x  = gLerp(a.x, b.x, e);   p.y  = gLerp(a.y, b.y, e)
    p.hb = gLerp(a.hb, b.hb, e)
    p.badge    = gLerp(a.badge, b.badge, e)
    p.tint     = gLerp(a.tint,  b.tint,  e)
    p.halo     = gLerp(a.halo,  b.halo,  e)
    p.haloBlue = gLerp(a.haloBlue, b.haloBlue, e)
    p.header   = a.header * (1 - gSeg(t, tc, tc+0.1))
    p.card     = a.card   * (1 - gSeg(t, tc, tc+0.18))
    p.handL    = a.handL  * (1 - gSeg(t, tc, tc+0.15))
    p.handR    = a.handR  * (1 - gSeg(t, tc, tc+0.15))
    p.wave     = a.wave >= 0 ? a.wave : -1
    p.tilt     = a.tilt * (1 - e)
    p.sx       = gLerp(a.sx, 1, e); p.sy = gLerp(a.sy, 1, e)
    p.eyeRoll  = a.eyeRoll * (1 - e)
    let bk = gSeg(t, tc+0.14, tc+0.26)
    p.eye = .dot; p.open = (bk > 0 && bk < 1) ? 1 - sin(.pi*bk)*0.94 : 1
    p.lookX = a.lookX*(1-e); p.lookY = a.lookY*(1-e)
    p.minis = GE.back(gSeg(t, tc+0.24, tc+0.42))
    p.fx    = 1 - gSeg(t, tc, tc+0.2)
    return p
}

// MARK: - Drawing helpers

private func gHex(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn:"#"))
    let v = UInt64(h, radix: 16) ?? 0
    return CGColor(red: CGFloat((v>>16)&0xFF)/255,
                   green: CGFloat((v>>8)&0xFF)/255,
                   blue: CGFloat(v&0xFF)/255, alpha: alpha)
}

private func gRR(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
    let r = max(0, min(r, w/2, h/2))
    ctx.beginPath()
    ctx.move(to: CGPoint(x: x+r, y: y))
    ctx.addArc(tangent1End: CGPoint(x: x+w, y: y), tangent2End: CGPoint(x: x+w, y: y+h), radius: r)
    ctx.addArc(tangent1End: CGPoint(x: x+w, y: y+h), tangent2End: CGPoint(x: x, y: y+h), radius: r)
    ctx.addArc(tangent1End: CGPoint(x: x, y: y+h), tangent2End: CGPoint(x: x, y: y), radius: r)
    ctx.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x+r, y: y), radius: r)
    ctx.closePath()
}

// MARK: - Dew
// The greeting draws Dew itself (its poses are scripted here), with the same glass, liquid
// and light as everywhere else (DewBody.swift).

/// Bulb radius. Beside the notch it matches the resting Dew; at full size it leaves room for the tip.
private func dewR(_ p: GreetPose) -> CGFloat {
    CGFloat(p.hb) * (0.588 - 0.07 * dewGrown(p))
}

/// 0 beside the notch, 1 at full size.
private func dewGrown(_ p: GreetPose) -> CGFloat {
    CGFloat(gClamp((p.hb - Double(GEAR_HB)) / Double(GHB - GEAR_HB), 0, 1))
}

/// Centre of the bulb. At full size it sits lower, so the drop (tip included) is centred in the card.
private func dewCenter(_ p: GreetPose) -> CGPoint {
    CGPoint(x: p.x, y: p.y + Double(dewR(p) * (0.06 + 0.24 * dewGrown(p))))
}

private func dewPose(_ p: GreetPose) -> DewPose {
    DewPose(center: dewCenter(p), R: dewR(p), sx: p.sx, sy: p.sy, tilt: p.tilt, lean: -p.tilt * 3, morph: 0)
}

private func dewPath(_ p: GreetPose) -> Path {
    let R = dewR(p)
    return BotEngine.dropPath(rx: R * DewConst.rx, ry: R * DewConst.ry, R: R, lean: CGFloat(-p.tilt * 3))
}

/// What the greeting asks of the shared drawing code: blue liquid that rises at the end,
/// stirred by the hop and the wave.
@MainActor
private func tune(_ dew: BotEngine, t: Double, p: GreetPose, glass: Bool) {
    dew.col = (0.231, 0.620, 1)
    dew.tint = CGFloat(p.tint)                   // clear at first; it fills at the end
    dew.tilt = CGFloat(p.tilt)
    dew.glassUnder = glass
    dew.displayScale = 1
    var slosh = 0.0, ripple = 0.0
    if t >= GT.pop1 {
        let w = t - GT.pop1
        slosh = sin(w * 9) * 0.34 * exp(-w * 1.5)
        ripple = exp(-w * 1.4)
    }
    if t >= GT.tint0 { ripple = max(ripple, exp(-(t - GT.tint0) * 2.2)) }
    dew.slosh = CGFloat(slosh)
    dew.ripple = CGFloat(ripple)
}

private func drawHalo(_ ctx: CGContext, p: GreetPose) {
    let R = dewR(p)
    guard p.halo > 0, R > 0.4 else { return }
    // Pale sky → blue, a soft aura in two passes. It is also what the glass has to bend.
    let bl = CGFloat(p.haloBlue)
    let cr = gLerpF(140/255, 59/255, bl)
    let cg = gLerpF(205/255, 158/255, bl)
    let cb = gLerpF(255/255, 255/255, bl)
    let cs = CGColorSpaceCreateDeviceRGB()
    let c = dewCenter(p)
    let cx = c.x, cy = c.y - R * 0.35
    for (radius, alpha) in [(R * 3.2, 0.24), (R * 5.2, 0.08)] {
        let inner = CGColor(red: cr, green: cg, blue: cb, alpha: CGFloat(alpha * p.halo))
        let outer = CGColor(red: cr, green: cg, blue: cb, alpha: 0)
        guard let g = CGGradient(colorsSpace: cs, colors: [inner, outer] as CFArray, locations: [0, 1]) else { continue }
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
        ctx.clip()
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cy), endRadius: radius, options: [])
        ctx.restoreGState()
    }
}

/// Dew's own space: origin on the bulb's centre.
private func dewContext(_ context: GraphicsContext, p: GreetPose) -> GraphicsContext {
    let c = dewCenter(p)
    var ctx = context
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: .radians(p.tilt))
    ctx.scaleBy(x: CGFloat(p.sx), y: CGFloat(p.sy))
    return ctx
}

/// Behind the glass: the hands and the liquid.
@MainActor
private func drawDewUnder(_ context: GraphicsContext, p: GreetPose, dew: BotEngine) {
    let R = dewR(p); guard R > 0.4 else { return }
    let rx = R * DewConst.rx, ry = R * DewConst.ry, hb = ry * 2
    let ctx = dewContext(context, p: p)

    // Left hand: a bead resting at the side
    let kl = CGFloat(p.handL)
    if kl > 0.01 {
        let r = hb * 0.15 * kl
        let hx = gLerpF(-rx * 0.35, -rx - hb * 0.20, kl)
        var hy = gLerpF(ry * 0.85, ry * 0.62, kl)
        if p.wave >= 0 { hy += CGFloat(sin(p.wave * 6)) * hb * 0.02 }
        dew.drawBead(ctx, in: CGRect(x: hx - r, y: hy - r, width: r * 2, height: r * 2))
    }
    // Right hand: raised, and waving
    let kr = CGFloat(p.handR)
    if kr > 0.01 {
        let L = hb * 0.40 * kr, T = hb * 0.24 * kr
        var hx = gLerpF(rx * 0.35, rx + hb * 0.20, kr)
        var hy = gLerpF(ry * 0.85, ry * 0.20, kr)
        var ang = -0.61
        if p.wave >= 0 {
            let w = p.wave * 2 * .pi * 2.5
            ang += sin(w) * 0.21; hy += CGFloat(sin(w + 0.8)) * hb * 0.04; hx += CGFloat(cos(w)) * hb * 0.015
        }
        var hand = ctx
        hand.translateBy(x: hx, y: hy)
        hand.rotate(by: .radians(ang))
        dew.drawBead(hand, in: CGRect(x: -L / 2, y: -T / 2, width: L, height: T))
    }

    dew.drawLiquid(ctx: ctx, path: dewPath(p), R: R, rx: rx, ry: ry)
}

/// In front of the glass: its light, the eyes and the badge.
@MainActor
private func drawDewOver(_ context: GraphicsContext, p: GreetPose, dew: BotEngine) {
    let R = dewR(p); guard R > 0.4 else { return }
    let rx = R * DewConst.rx, ry = R * DewConst.ry
    let ctx = dewContext(context, p: p)
    let path = dewPath(p)
    dew.drawDewBody(ctx: ctx, path: path, R: R, rx: rx, ry: ry)

    // Eyes (clipped to the body, so they can roll out of sight when Dew ducks)
    var eyes = ctx
    eyes.clip(to: path)
    eyes.addFilter(.shadow(color: .black.opacity(0.38), radius: R * 0.05, x: 0, y: R * 0.02))
    let ink = Color(cgColor: DewConst.ink)
    let ew = R * DewConst.eyeW, eh = R * DewConst.eyeH
    let sp = sin(DewConst.eyeSp) * rx
    let lx = CGFloat(p.lookX) * R * 0.34
    let ly = CGFloat(p.lookY) * ry * 0.24 + ry * 0.13 + CGFloat(p.eyeRoll) * ry * 1.25
    let stroke = StrokeStyle(lineWidth: ew * 0.52, lineCap: .round)
    for sd: CGFloat in [-1, 1] {
        var eye = eyes
        eye.translateBy(x: sd * sp + lx, y: ly)
        switch p.eye {
        case .happy:
            var arc = Path()
            arc.addArc(center: CGPoint(x: 0, y: ew * 0.45), radius: ew * 0.80,
                       startAngle: .radians(.pi * 1.15), endAngle: .radians(.pi * 1.85), clockwise: false)
            eye.stroke(arc, with: .color(ink), style: stroke)
        case .content:
            var arc = Path()
            arc.addArc(center: CGPoint(x: 0, y: -ew * 0.40), radius: ew * 0.80,
                       startAngle: .radians(.pi * 0.15), endAngle: .radians(.pi * 0.85), clockwise: false)
            eye.stroke(arc, with: .color(ink), style: stroke)
        case .dot:
            let h = max(eh * CGFloat(p.open), ew * 0.3)
            let r = min(ew, h) / 2
            eye.fill(Path(roundedRect: CGRect(x: -ew / 2, y: -h / 2, width: ew, height: h),
                          cornerSize: CGSize(width: r, height: r)), with: .color(ink))
        }
    }

    // Activity badge on the shoulder
    if p.badge > 0.01 {
        var badge = ctx
        badge.translateBy(x: -R * 0.72, y: -R * 0.72)
        badge.scaleBy(x: CGFloat(p.badge), y: CGFloat(p.badge))
        let pw = R * 0.72, ph = R * 0.36
        badge.fill(Path(roundedRect: CGRect(x: -pw / 2, y: -ph / 2, width: pw, height: ph),
                        cornerSize: CGSize(width: ph / 2, height: ph / 2)),
                   with: .color(Color(hex: "#3B9EFF")))
        for i: CGFloat in [-1, 0, 1] {
            let d = R * 0.055
            badge.fill(Path(ellipseIn: CGRect(x: i * R * 0.18 - d, y: -d, width: d * 2, height: d * 2)),
                       with: .color(.white))
        }
    }
}

private func drawParticles(_ ctx: CGContext, t: Double, tc: Double, p: GreetPose) {
    guard p.card > 0 || p.fx < 1 else { return }
    let fx = p.fx
    // RINGS
    for ring in greetParticles.rings {
        let k = gSeg(t, ring.t0, ring.t0 + 1.35)
        guard k > 0 && k < 1 else { continue }
        let rx = gLerpF(14, 380, CGFloat(GE.out(k)))
        let ry = rx * 0.34
        let fade = CGFloat((1-k) * (k < 0.08 ? k/0.08 : 1) * fx * p.card)
        for dot in ring.dots {
            let r: CGFloat = 1 + CGFloat(dot.j)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(dot.al)*fade))
            let dx = CGFloat(GC0.x) + cos(CGFloat(dot.a))*rx*r
            let dy = CGFloat(GC0.y) + sin(CGFloat(dot.a))*ry*r
            ctx.fill(CGRect(x: dx, y: dy, width: CGFloat(dot.s), height: CGFloat(dot.s)))
        }
    }
    // STREAKS
    for s in greetParticles.streaks {
        let k = gSeg(t, s.t0, s.t0 + 0.6)
        guard k > 0 && k < 1 else { continue }
        let dist = CGFloat(s.sp * GE.out(k) * 0.9 + 10)
        let alpha = CGFloat((1-k) * fx)
        ctx.setStrokeColor(gHex(s.col, alpha: alpha))
        ctx.setLineWidth(1.6); ctx.setLineCap(.round)
        let a = CGFloat(s.a)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: CGFloat(GC0.x)+cos(a)*(dist-CGFloat(s.len)),
                             y: CGFloat(GC0.y)+sin(a)*(dist-CGFloat(s.len))*0.42))
        ctx.addLine(to: CGPoint(x: CGFloat(GC0.x)+cos(a)*dist,
                                y: CGFloat(GC0.y)+sin(a)*dist*0.42))
        ctx.strokePath()
    }
}

private func drawHeader(_ ctx: CGContext, alpha: Double) {
    guard alpha > 0 else { return }
    ctx.saveGState()
    ctx.setAlpha(CGFloat(alpha))
    // VS Code icon pill (top-left)
    gRR(ctx, 18, 4, 44, 26, 13)
    ctx.setFillColor(gHex("#1D1F23")); ctx.fillPath()
    ctx.setFillColor(gHex("#F5F6F8"))
    // Simple chevron-up shape
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 33, y: 20)); ctx.addLine(to: CGPoint(x: 40, y: 13))
    ctx.addLine(to: CGPoint(x: 47, y: 20)); ctx.addLine(to: CGPoint(x: 47, y: 25))
    ctx.addLine(to: CGPoint(x: 33, y: 25)); ctx.closePath(); ctx.fillPath()
    // Two dots (circles) top-right
    ctx.setFillColor(gHex("#8E939C"))
    ctx.addEllipse(in: CGRect(x: 75.5, y: 10.5, width: 13, height: 13)); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: 572, y: 11, width: 12, height: 12)); ctx.fillPath()
    ctx.setFillColor(gHex("#000000"))
    ctx.addEllipse(in: CGRect(x: 575.6, y: 14.6, width: 4.8, height: 4.8)); ctx.fillPath()
    ctx.restoreGState()
}

private let miniColors = ["#E86A6A","#3E86E0","#EFAE5A","#8C73F2"]

private func drawMinis(_ ctx: CGContext, alpha: Double, compact: IslandRestingLayout) {
    guard alpha > 0.01 else { return }
    let cx = 320 - compact.width/2 + compact.miniGridCenterX
    let cy = compact.botCenterY
    let sp: CGFloat = 6 * compact.miniGridScale
    let offsets: [(CGFloat, CGFloat)] = [(-sp,-sp),(sp,-sp),(-sp,sp),(sp,sp)]
    for (i,(dx,dy)) in offsets.enumerated() {
        ctx.saveGState()
        ctx.translateBy(x: cx+dx, y: cy+dy)
        let scale = CGFloat(alpha) * compact.miniGridScale
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(gHex(miniColors[i]))
        ctx.addPath(BotEngine.dropPath(rx: 4.4, ry: 4.4 * DewConst.ry, R: 4.4).cgPath); ctx.fillPath()
        ctx.restoreGState()
    }
}

// MARK: - Full draw function

/// Everything but Dew: the card, the particles, the pills' characters and Dew's halo.
private func drawGreeting(_ ctx: CGContext, size: CGSize, t: Double, tc: Double, p: GreetPose, compact: IslandRestingLayout) {

    // Card background (dark panel)
    if p.card > 0 {
        ctx.saveGState()
        ctx.setAlpha(CGFloat(p.card))
        gRR(ctx, GCARD.minX, GCARD.minY, GCARD.width, GCARD.height, GCARD_R)
        ctx.setFillColor(gHex("#141518")); ctx.fillPath()
        ctx.restoreGState()

        // Particles inside card area
        ctx.saveGState()
        gRR(ctx, GCARD.minX, GCARD.minY, GCARD.width, GCARD.height, GCARD_R)
        ctx.clip()
        drawParticles(ctx, t: t, tc: tc, p: p)
        ctx.restoreGState()
    } else if tc.isFinite && t >= tc {
        // During collapse, fade particles without card clip
        ctx.saveGState()
        drawParticles(ctx, t: t, tc: tc, p: p)
        ctx.restoreGState()
    }

    // drawHeader: no icons during greeting
    drawMinis(ctx, alpha: p.minis, compact: compact)
    drawHalo(ctx, p: p)
}

// MARK: - SwiftUI View

struct GreetingCanvasView: View {
    @ObservedObject var state: AppState

    @State private var startDate = Date()
    @State private var tc: Double = .infinity   // collapses only when FSM fires .greetingInterrupt
    @State private var greetFired = false
    @StateObject private var dew = BotEngine()   // only for its drawing code and the liquid's state

    private var glass: Bool {
        if #available(macOS 26.0, *) { return !DewDebug.noGlass }
        return false
    }

    // Scheduled works (cancellable)
    @State private var soundWork1: DispatchWorkItem? = nil
    @State private var soundWork2: DispatchWorkItem? = nil
    @State private var doneWork:   DispatchWorkItem? = nil

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(startDate)
            let compact = IslandRestingLayout(width: state.notchWidth + 160, height: state.notchHeight)
            let p = pose(t, tc: tc, compact: compact)
            let _ = tune(dew, t: t, p: p, glass: glass)
            // Dew's body is real glass between two canvases, like in the open island
            ZStack {
                Canvas { context, size in
                    context.withCGContext { cgCtx in
                        drawGreeting(cgCtx, size: size, t: t, tc: tc, p: p, compact: compact)
                    }
                    drawDewUnder(context, p: p, dew: dew)
                }
                if #available(macOS 26.0, *), glass {
                    DewGlass(pose: dewPose(p))
                }
                Canvas { context, size in
                    drawDewOver(context, p: p, dew: dew)
                }
            }
            // Fire greetComplete exactly once at T.end (when no hover)
            .onChange(of: !greetFired && t >= GT.end && tc >= GT.autoLeave) { _, trigger in
                if trigger { fireGreetComplete() }
            }
        }
        .onAppear {
            startDate = Date()
            tc = .infinity
            greetFired = false
            scheduleWorks()
        }
        .onDisappear {
            cancelWorks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingHover)) { _ in
            // Mouse on notch during greeting → hold open (no auto-collapse)
            if tc >= GT.autoLeave { tc = .infinity }
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingInterrupt)) { _ in
            // Mouse left during greeting → start collapse from current time
            let t = Date().timeIntervalSince(startDate)
            if tc.isInfinite || tc > t { tc = t }
            cancelWorks()   // cancel auto-done timer (FSM already went to .petit)
        }
    }

    private func fireGreetComplete() {
        guard !greetFired else { return }
        greetFired = true
        cancelWorks()
        NotificationCenter.default.post(name: .greetComplete, object: nil)
    }

    private func scheduleWorks() {
        func schedule(_ delay: Double, _ block: @escaping () -> Void) -> DispatchWorkItem {
            let item = DispatchWorkItem(block: block)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
        soundWork1 = schedule(GT.pop0)  { SoundEngine.shared.play("greet") }
        soundWork2 = schedule(GT.badge) { SoundEngine.shared.play("blip")  }
        // doneWork is a safety fallback; normal path fires via .onChange
        doneWork = schedule(GT.end + 0.05) { fireGreetComplete() }
    }

    private func cancelWorks() {
        soundWork1?.cancel(); soundWork1 = nil
        soundWork2?.cancel(); soundWork2 = nil
        doneWork?.cancel();   doneWork = nil
    }
}
