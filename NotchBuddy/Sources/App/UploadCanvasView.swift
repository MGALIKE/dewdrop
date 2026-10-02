import SwiftUI
import AppKit

// Full 640×176 canvas that drives the upload sequence animation.
// Replaces the header + content area when the upload engine is active.

struct UploadCanvasView: View {
    @ObservedObject var state: AppState
    @State private var fileIcon: NSImage? = nil
    @StateObject private var dew = BotEngine()   // only for its drawing code and the liquid's state

    private var glass: Bool {
        if #available(macOS 26.0, *) { return !DewDebug.noGlass }
        return false
    }

    private var engine: UploadSequenceEngine { .shared }

    var body: some View {
        TimelineView(.animation) { tl in
            let f = engine.frame(at: tl.date)
            let wallTime = tl.date.timeIntervalSinceReferenceDate

            let _ = tune(f)

            // Dew's body is real glass between two canvases, like in the open island
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    drawScene(ctx: ctx, f: f, wallTime: wallTime)
                }
                .frame(width: 640, height: 176)

                if #available(macOS 26.0, *), glass {
                    DewGlass(pose: dewPose(f))
                        .frame(width: 640, height: 176)
                }

                Canvas { ctx, _ in
                    var c = ctx
                    drawDewOver(ctx: &c, f: f)
                    if f.fileVisible { drawFile(ctx: &c, f: f) }
                }
                .frame(width: 640, height: 176)
                .allowsHitTesting(false)

                // Interactive choose buttons (invisible hit areas at reference positions)
                if f.chooseAlpha > 0 {
                    chooseOverlay(f: f)
                        .frame(width: 640, height: 176)
                }
            }
        }
        .onChange(of: state.droppedFile?.url) { _, url in
            if let url { loadIcon(url: url) }
        }
        .onAppear {
            if let url = state.droppedFile?.url { loadIcon(url: url) }
        }
        .frame(width: 640, height: 176)
    }

    // MARK: - File icon

    private func loadIcon(url: URL) {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 64, height: 64)
        fileIcon = img
    }

    // MARK: - Choose overlay (transparent SwiftUI buttons over canvas)

    @ViewBuilder
    private func chooseOverlay(f: USFrame) -> some View {
        // Reference positions: button1 x=100 w=176 y=113 h=26, button2 x=284 w=128
        ZStack(alignment: .topLeading) {
            // Primary: "Ask a question about it"
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { state.view = .prompt }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    UploadSequenceEngine.shared.deactivate()
                }
            } label: {
                Color.clear
                    .frame(width: 168, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 168, height: 26)
            .position(x: 114 + 84, y: 113 + 13)   // center = (198, 126)

            // Secondary: "Send by email"
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { state.view = .mail }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    UploadSequenceEngine.shared.deactivate()
                }
            } label: {
                Color.clear
                    .frame(width: 120, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 120, height: 26)
            .position(x: 290 + 60, y: 113 + 13)   // center = (350, 126)

            // Tertiary: "Open shelf" — the file is already parked there
            if state.activeIntegrations.contains("integration_shelf") {
                Button {
                    state.setFocus("integration_shelf")
                    withAnimation(.easeInOut(duration: 0.22)) { state.view = .overview }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        UploadSequenceEngine.shared.deactivate()
                    }
                } label: {
                    Color.clear
                        .frame(width: 96, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 96, height: 26)
                .position(x: 418 + 48, y: 113 + 13)   // center = (466, 126)
            }
        }
        .opacity(f.chooseAlpha)
        .allowsHitTesting(f.chooseAlpha > 0.5)
    }

    // MARK: - Main draw

    private func drawScene(ctx: GraphicsContext, f: USFrame, wallTime: Double = 0) {
        var c = ctx

        // ── Island background ──────────────────────────────────────
        // The island body behind this canvas is glass — nothing to paint here.

        // ── Card ──────────────────────────────────────────────────
        let cardPath = roundedRect(CGRect(x: USC.CARD_X, y: USC.CARD_Y, width: USC.CARD_W, height: USC.CARD_H), r: USC.CARD_R)

        var cardCtx = c
        cardCtx.clip(to: cardPath)
        cardCtx.fill(Path(CGRect(x: USC.CARD_X, y: USC.CARD_Y, width: USC.CARD_W, height: USC.CARD_H)),
                     with: .color(Color.black.opacity(0.38)))

        // Green glow from card bottom — grows slowly with upload progress
        if f.greenWash > 0 {
            // Center at card bottom edge; gradient fans upward through the card
            let gx = USC.CARD_X + USC.CARD_W/2
            let gy = USC.CARD_Y + USC.CARD_H   // bottom of card
            let gGrad = Gradient(stops: [
                .init(color: Color(red:0.157,green:0.831,blue:0.510).opacity(f.greenWash * 0.90), location:0),
                .init(color: Color(red:0.157,green:0.831,blue:0.510).opacity(f.greenWash * 0.30), location:0.55),
                .init(color: Color(red:0.157,green:0.831,blue:0.510).opacity(0), location:1)
            ])
            cardCtx.fill(Path(CGRect(x:USC.CARD_X,y:USC.CARD_Y,width:USC.CARD_W,height:USC.CARD_H)),
                         with: .radialGradient(gGrad, center:CGPoint(x:gx,y:gy),
                                              startRadius:0, endRadius:USC.CARD_H*1.5))
        }

        // ── Dashed border (animates left→right while on drop zone) ────
        if f.zoneAlpha > 0 {
            var borderCtx = c
            borderCtx.opacity = f.zoneAlpha
            let borderColor = f.zoneOver
                ? Color(red:0.204,green:0.831,blue:0.600).opacity(0.55)
                : Color.white.opacity(0.14)
            let inset = CGRect(x: USC.CARD_X+0.75, y: USC.CARD_Y+0.75,
                               width: USC.CARD_W-1.5, height: USC.CARD_H-1.5)
            // dashPhase increases → pattern marches left-to-right at ~20 pt/s
            let dashPhase = CGFloat(wallTime * 20)
            borderCtx.stroke(roundedRect(inset, r: USC.CARD_R-0.5),
                             with: .color(borderColor),
                             style: StrokeStyle(lineWidth:1.5, dash:[6,5], dashPhase: dashPhase))
        }

        // ── Drop zone text ─────────────────────────────────────────
        if f.zoneAlpha > 0 && f.textAlpha > 0 {
            drawDropText(ctx: &c, f: f)
        }

        // ── Progress bar ──────────────────────────────────────────
        if f.barAlpha > 0 || f.barReveal > 0 {
            drawProgressBar(ctx: &c, f: f)
        }

        // ── Choose view text ─────────────────────────────────────
        if f.chooseAlpha > 0 {
            drawChooseView(ctx: &c, f: f)
        }

        // ── Dew: what is behind its glass (the rest is drawn in front, with the file) ──
        drawDewUnder(ctx: c, f: f)
    }

    // MARK: - Drop zone text + chips

    private func drawDropText(ctx: inout GraphicsContext, f: USFrame) {
        var tCtx = ctx
        tCtx.opacity = f.textAlpha

        let label = Text("Drop your files here")
            .font(.system(size:13, weight:.medium))
            .foregroundColor(Color(hex:"#D5D7DB"))
        tCtx.draw(label, at: CGPoint(x: USC.TEXT_X, y: USC.TEXT_Y - 4), anchor: .leading)

        let chips = ["PDF","Images","Code","Docs"]
        var cx = USC.TEXT_X
        for chip in chips {
            let chipText = Text(chip).font(.system(size:11, weight:.medium)).foregroundColor(Color(hex:"#B9BDC4"))
            // measure approximate width
            let estW = Double(chip.count) * 6.5 + 16
            tCtx.fill(roundedRect(CGRect(x:cx, y:USC.TEXT_Y+9, width:estW, height:18), r:9),
                      with: .color(Color.white.opacity(0.07)))
            tCtx.draw(chipText, at: CGPoint(x: cx + 8, y: USC.TEXT_Y + 18), anchor: .leading)
            cx += estW + 6
        }
    }

    // MARK: - Progress bar

    private func drawProgressBar(ctx: inout GraphicsContext, f: USFrame) {
        var pCtx = ctx
        pCtx.opacity = max(f.barAlpha, 0.001)

        let x0 = USC.BAR_X0, x1 = USC.BAR_X1, by = USC.BAR_Y
        let barLen = (x1-x0) * f.barReveal

        // Filename label
        let name = state.droppedFile?.name ?? "file"
        let label = Text("Uploading \(name)")
            .font(.system(size:12.5, weight:.medium))
            .foregroundColor(Color(hex:"#A9ADB5"))
        pCtx.draw(label, at: CGPoint(x: x0, y: by-30), anchor: .leading)

        // Checkmark or percentage
        if f.check > 0 {
            var ckCtx = pCtx
            ckCtx.concatenate(CGAffineTransform(translationX: CGFloat(x1-8), y: CGFloat(by-30)))
            ckCtx.concatenate(CGAffineTransform(scaleX: CGFloat(f.check), y: CGFloat(f.check)))
            var circle = Path(); circle.addEllipse(in: CGRect(x:-8,y:-8,width:16,height:16))
            ckCtx.fill(circle, with: .color(Color(hex:"#34D399")))
            var ck = Path()
            ck.move(to: CGPoint(x:-3.6,y:0.2)); ck.addLine(to: CGPoint(x:-1,y:2.8)); ck.addLine(to: CGPoint(x:3.8,y:-2.6))
            ckCtx.stroke(ck, with: .color(Color(red:0.027,green:0.075,blue:0.055)),
                         style: StrokeStyle(lineWidth:2, lineCap:.round, lineJoin:.round))
        } else {
            let pct = Text("\(Int(f.progress*100)) %")
                .font(.system(size:12.5, weight:.medium).monospacedDigit())
                .foregroundColor(Color(hex:"#A9ADB5"))
            pCtx.draw(pct, at: CGPoint(x: x1, y: by-30), anchor: .trailing)
        }

        // Bar track
        if barLen > 0 {
            pCtx.fill(roundedRect(CGRect(x:x0, y:by-3, width:barLen, height:6), r:3),
                      with: .color(Color.white.opacity(0.08)))
        }

        // Bar fill
        let fx = usLerp(USC.BAR_X0, USC.BAR_X1, f.progress)
        if fx > x0 + 1 {
            // Flash color at completion
            let flashGreen = Color(
                red:   usLerp(0.204, 0.431, f.flash),
                green: usLerp(0.827, 0.906, f.flash),
                blue:  usLerp(0.600, 0.718, f.flash))
            let fillGrad = Gradient(stops: [
                .init(color: Color(hex:"#1FA87A"), location:0),
                .init(color: flashGreen, location:1)
            ])
            pCtx.fill(roundedRect(CGRect(x:x0, y:by-3, width:fx-x0, height:6), r:3),
                      with: .linearGradient(fillGrad,
                                           startPoint: CGPoint(x:x0, y:0),
                                           endPoint:   CGPoint(x:fx,  y:0)))
        }

        // Glow trail
        if f.progress > 0.01 && f.progress < 1 {
            let v = (usProgressAt(f.t+0.01, progStart:USC.T_PROG_START, progEnd:f.progEnd)
                   - usProgressAt(f.t,      progStart:USC.T_PROG_START, progEnd:f.progEnd)) / 0.01
            let tl = max(8, min(34, 8 + v*40))
            let tGrad = Gradient(stops:[
                .init(color: Color(red:0.204,green:0.831,blue:0.600,opacity:0), location:0),
                .init(color: Color(red:0.431,green:0.906,blue:0.718,opacity:0.6), location:1)
            ])
            var glowCtx = pCtx
            glowCtx.addFilter(.blur(radius:3))
            glowCtx.fill(roundedRect(CGRect(x:fx-tl, y:by-4, width:tl, height:8), r:4),
                         with: .linearGradient(tGrad,
                                              startPoint:CGPoint(x:fx-tl,y:0),
                                              endPoint:  CGPoint(x:fx,y:0)))
        }
    }

    // MARK: - Choose view text + buttons (canvas layer)

    private func drawChooseView(ctx: inout GraphicsContext, f: USFrame) {
        var cCtx = ctx
        cCtx.opacity = f.chooseAlpha
        // Slide up: translate down by (1-alpha)*4
        cCtx.concatenate(CGAffineTransform(translationX: 0, y: CGFloat((1-f.chooseAlpha)*4)))

        let name = state.droppedFile?.name ?? "file"
        let titleText = Text("\(name) is ready.")
            .font(.system(size:14, weight:.semibold))
            .foregroundColor(Color(hex:"#F5F6F8"))
        cCtx.draw(titleText, at: CGPoint(x:114, y:80), anchor: .leading)

        let onShelf = state.activeIntegrations.contains("integration_shelf")
        let subText = Text(onShelf ? "It's on your shelf. Anything else?" : "What do you want to do with it?")
            .font(.system(size:12.5))
            .foregroundColor(Color(hex:"#9398A1"))
        cCtx.draw(subText, at: CGPoint(x:114, y:100), anchor: .leading)

        // Primary button (white fill)
        cCtx.fill(roundedRect(CGRect(x:114,y:113,width:168,height:26), r:13),
                  with: .color(Color(hex:"#F5F6F8")))
        let btn1 = Text("Ask a question about it")
            .font(.system(size:12.5, weight:.medium))
            .foregroundColor(Color(red:0.043,green:0.047,blue:0.055))
        cCtx.draw(btn1, at: CGPoint(x:198, y:126), anchor: .center)

        // Secondary button (dim fill)
        cCtx.fill(roundedRect(CGRect(x:290,y:113,width:120,height:26), r:13),
                  with: .color(Color.white.opacity(0.09)))
        let btn2 = Text("Send by email")
            .font(.system(size:12.5, weight:.medium))
            .foregroundColor(Color(hex:"#F1F2F4"))
        cCtx.draw(btn2, at: CGPoint(x:350, y:126), anchor: .center)

        // Tertiary button (dim fill)
        if onShelf {
            cCtx.fill(roundedRect(CGRect(x:418,y:113,width:96,height:26), r:13),
                      with: .color(Color.white.opacity(0.09)))
            let btn3 = Text("Open shelf")
                .font(.system(size:12.5, weight:.medium))
                .foregroundColor(Color(hex:"#F1F2F4"))
            cCtx.draw(btn3, at: CGPoint(x:466, y:126), anchor: .center)
        }
    }

    // MARK: - Dew (a drop that becomes a glass box with a slot, and back)

    private func dewR(_ f: USFrame) -> CGFloat { CGFloat(f.d / 2 / 1.04) }
    private func dewMorph(_ f: USFrame) -> CGFloat { CGFloat(max(0, min(f.morph, 1.0))) }

    private func dewPose(_ f: USFrame) -> DewPose {
        DewPose(center: CGPoint(x: f.x, y: f.y + f.hop), R: dewR(f), sx: f.sx, sy: f.sy,
                tilt: f.tilt, lean: 0, morph: dewMorph(f))
    }

    private func dewPath(_ f: USFrame) -> Path {
        let R = dewR(f)
        return BotEngine.dropPath(rx: R * DewConst.rx, ry: R * DewConst.ry, R: R, morph: dewMorph(f))
    }

    private func dewContext(_ ctx: GraphicsContext, f: USFrame) -> GraphicsContext {
        var c = ctx
        c.concatenate(CGAffineTransform(translationX: CGFloat(f.x), y: CGFloat(f.y + f.hop)))
        c.concatenate(CGAffineTransform(rotationAngle: CGFloat(f.tilt)))
        c.concatenate(CGAffineTransform(scaleX: CGFloat(f.sx), y: CGFloat(f.sy)))
        return c
    }

    /// What the upload asks of the shared drawing code: Dew fills with green as the file goes up.
    private func tune(_ f: USFrame) {
        dew.col = (0.204, 0.831, 0.600)
        dew.tint = CGFloat(0.08 + 0.78 * max(0, min(f.progress, 1)))
        dew.tilt = CGFloat(f.tilt)
        dew.morph = dewMorph(f)
        dew.glassUnder = glass
        dew.displayScale = 1
    }

    private func drawDewUnder(ctx: GraphicsContext, f: USFrame) {
        let R = dewR(f)
        dew.drawLiquid(ctx: dewContext(ctx, f: f), path: dewPath(f), R: R, rx: R * DewConst.rx, ry: R * DewConst.ry)
    }

    private func drawDewOver(ctx: inout GraphicsContext, f: USFrame) {
        let R  = Double(dewR(f))
        let mc = Double(dewMorph(f))
        let rx = R * Double(DewConst.rx), ry = R * Double(DewConst.ry)
        let c  = dewContext(ctx, f: f)
        let bp = dewPath(f)

        dew.drawDewBody(ctx: c, path: bp, R: CGFloat(R), rx: CGFloat(rx), ry: CGFloat(ry))

        // ── Top rim (box mode) ─────────────────────────────────────
        if mc > 0.3 {
            let rimAlpha = max(0, min(1, (mc-0.3)/0.7))
            var rimCtx = c
            rimCtx.clip(to: bp)
            var rim = Path()
            rim.move(to: CGPoint(x: -rx*0.72, y: -ry+0.9))
            rim.addLine(to: CGPoint(x: rx*0.72,  y: -ry+0.9))
            rimCtx.stroke(rim, with: .color(Color.white.opacity(0.6*rimAlpha)),
                          style: StrokeStyle(lineWidth:1.2, lineCap:.round))
        }

        // ── Mouth hole ─────────────────────────────────────────────
        let mh = f.mouth * R * mc
        if mh > 0.3 {
            let mw  = 2*rx - 0.24*R
            let mxO = CGFloat(-mw/2)
            let myO = CGFloat(-ry + 0.10*R)
            let mhr = CGFloat(min(mw/2, mh/2))
            var mCtx = c
            mCtx.clip(to: bp)
            let holeGrad = Gradient(stops:[
                .init(color: Color(red:0.012,green:0.012,blue:0.016), location:0),
                .init(color: Color(red:0.063,green:0.067,blue:0.078), location:1)
            ])
            let holePath = roundedRect(CGRect(x:mxO, y:myO, width:CGFloat(mw), height:CGFloat(mh)), r:Double(mhr))
            mCtx.fill(holePath, with: .linearGradient(holeGrad,
                startPoint: CGPoint(x:0, y:myO),
                endPoint:   CGPoint(x:0, y:myO+CGFloat(mh))))
            // Bottom lip
            if mh > 4 {
                var lip = Path()
                lip.move(to:    CGPoint(x:mxO+mhr,              y:myO+CGFloat(mh)+0.5))
                lip.addLine(to: CGPoint(x:mxO+CGFloat(mw)-mhr,  y:myO+CGFloat(mh)+0.5))
                mCtx.stroke(lip, with: .color(Color.white.opacity(0.55)),
                            style: StrokeStyle(lineWidth:1, lineCap:.round))
            }
        }

        // ── Eyes ───────────────────────────────────────────────────
        let ew = R * Double(DewConst.eyeW)
        let eh = R * (Double(DewConst.eyeH) + 0.08*mc)
        let ey = ry * (0.13 + 0.14*mc)
        let sp = R * (0.39 - 0.07*mc)
        let lx = f.lookX * R * (0.34 - 0.08*mc)
        let ly = f.lookY * R * (0.16 - 0.09*mc)

        var eCtx = c
        eCtx.clip(to: bp)
        if R > 9 { eCtx.addFilter(.shadow(color: .black.opacity(0.38), radius: R * 0.05, x: 0, y: R * 0.02)) }
        for sd in [-1.0, 1.0] {
            var ec = eCtx
            ec.concatenate(CGAffineTransform(translationX: CGFloat(sd*sp+lx), y: CGFloat(ey+ly)))
            drawEyeShape(ctx: &ec, shape: f.eye, w: CGFloat(ew), h: CGFloat(eh))
        }
    }

    // MARK: - Eye shapes

    private func drawEyeShape(ctx: inout GraphicsContext, shape: USEyeShape, w: CGFloat, h: CGFloat) {
        let ink = Color(cgColor: DewConst.ink)
        switch shape {
        case .pill:
            var p = Path()
            p.addRoundedRect(in: CGRect(x:-w/2, y:-h/2, width:w, height:h),
                             cornerSize: CGSize(width:w/2, height:w/2))
            ctx.fill(p, with: .color(ink))

        case .cup:
            // Flat top + semicircle bottom (cup shape)
            let hh = h * 0.55
            var p = Path()
            p.move(to: CGPoint(x:-w/2, y:-hh/2))
            p.addLine(to: CGPoint(x: w/2, y:-hh/2))
            p.addLine(to: CGPoint(x: w/2, y: hh/2-w/2))
            p.addArc(center: CGPoint(x:0, y:hh/2-w/2), radius:w/2, startAngle:.degrees(0), endAngle:.degrees(180), clockwise:false)
            p.closeSubpath()
            ctx.fill(p, with: .color(ink))

        case .content:
            // Upward arc (content / happy)
            var p = Path()
            p.addArc(center: CGPoint(x:0, y:-h*0.12), radius:w*0.85,
                     startAngle:.degrees(180*0.15), endAngle:.degrees(180*0.85), clockwise:false)
            ctx.stroke(p, with: .color(ink),
                       style: StrokeStyle(lineWidth:w*0.5, lineCap:.round))
        }
    }

    // MARK: - File / suction (drawFile port)

    private func drawFile(ctx: inout GraphicsContext, f: USFrame) {
        let cx = f.cursorX, cy = f.cursorY + 14
        if f.suck <= 0 {
            var fc = ctx; fc.opacity = 0.92
            drawDoc(ctx: &fc, cx: cx, cy: cy, wsc:1, hsc:1)
            return
        }

        let m   = f.mouthRect
        let W0  = 34.0, H0 = 42.0
        let p   = usEIn(f.suck)
        let topY = usLerp(cy - H0/2, m.y - 2, usEInOut(f.suck))
        let hs  = usLerp(1.08, 0.55, usEInOut(f.suck))
        let Hh  = H0 * hs
        let sc  = usLerp(1, 0.55, p)
        let q   = usEOut(f.suck)
        let fCx = usLerp(cx, m.x + m.w/2, usEOut(f.suck))
        let wob = sin(f.suck * .pi * 2) * 0.1 * (1-p)
        let clipY = m.y + m.h * 0.5

        // Use withCGContext for the complex strip clipping
        ctx.withCGContext { cg in
            cg.saveGState()
            // Outer clip: above mouth
            cg.clip(to: CGRect(x:0, y:0, width:640, height:clipY))

            for i in 0..<28 {
                let v0 = Double(i) / 28
                let wsc = usLerp(1, usLerp(0.92, 0.22*m.w/W0, pow(v0,1.2)), q) * sc
                let yy  = topY + v0*Hh
                let hh  = Hh/28 + 0.6

                cg.saveGState()
                cg.translateBy(x: CGFloat(fCx), y: CGFloat(yy))
                cg.rotate(by: CGFloat(wob))
                cg.clip(to: CGRect(x: CGFloat(-W0*wsc/2), y:0, width: CGFloat(W0*wsc), height: CGFloat(hh)))
                cg.translateBy(x: CGFloat(-fCx), y: CGFloat(-yy))
                drawDocCG(cg: cg, cx: fCx, cy: topY+Hh/2, wsc: wsc, hsc: hs, fileIcon: fileIcon)
                cg.restoreGState()
            }
            cg.restoreGState()
        }

        // Green particles
        for i in 0..<4 {
            let a   = Double(i)/4 * .pi*2 + 0.6
            let r0  = 24.0
            let k   = max(0, min(1, (f.suck - Double(i)*0.08) / 0.7))
            guard k > 0 && k < 1 else { continue }
            let sx0 = cx + cos(a)*r0, sy0 = cy + sin(a)*r0
            let ex  = m.x + m.w/2,    ey  = m.y + m.h*0.3
            let kk  = pow(k, 0.7)
            let px  = usLerp(sx0,ex,kk), py = usLerp(sy0,ey,kk) - sin(.pi*k)*6
            let rad = 2.2*(1-k*0.5)
            var pp = Path(); pp.addEllipse(in: CGRect(x:px-rad, y:py-rad, width:rad*2, height:rad*2))
            ctx.fill(pp, with: .color(Color(red:0.204,green:0.831,blue:0.600).opacity(1-k)))
        }
    }

    // MARK: - Doc icon (SwiftUI wrapper)

    private func drawDoc(ctx: inout GraphicsContext, cx: Double, cy: Double, wsc: Double, hsc: Double) {
        let w = 34*wsc, h = 42*hsc
        let x = cx-w/2, y = cy-h/2
        let fold = 8*min(wsc,hsc)

        var bodyCtx = ctx
        bodyCtx.addFilter(.shadow(color:.black.opacity(0.45), radius:8, x:0, y:3))
        var body = Path()
        body.move(to: CGPoint(x:x+2,y:y))
        body.addLine(to: CGPoint(x:x+w-fold,y:y))
        body.addLine(to: CGPoint(x:x+w,y:y+fold))
        body.addLine(to: CGPoint(x:x+w,y:y+h-2))
        body.addQuadCurve(to: CGPoint(x:x+w-2,y:y+h), control:CGPoint(x:x+w,y:y+h))
        body.addLine(to: CGPoint(x:x+2,y:y+h))
        body.addQuadCurve(to: CGPoint(x:x,y:y+h-2), control:CGPoint(x:x,y:y+h))
        body.addLine(to: CGPoint(x:x,y:y+2))
        body.addQuadCurve(to: CGPoint(x:x+2,y:y), control:CGPoint(x:x,y:y))
        body.closeSubpath()
        bodyCtx.fill(body, with: .color(Color(red:0.957,green:0.957,blue:0.965)))

        var foldPath = Path()
        foldPath.move(to: CGPoint(x:x+w-fold,y:y))
        foldPath.addLine(to: CGPoint(x:x+w-fold,y:y+fold))
        foldPath.addLine(to: CGPoint(x:x+w,y:y+fold))
        ctx.fill(foldPath, with: .color(Color(red:0.835,green:0.839,blue:0.859)))

        ctx.fill(roundedRect(CGRect(x:x+w*0.18,y:y+h*0.58,width:w*0.64,height:h*0.16),r:2),
                 with: .color(Color(red:0.231,green:0.510,blue:0.961)))
    }
}

// MARK: - Doc icon in CGContext (for suction strips)

private func drawDocCG(cg: CGContext, cx: Double, cy: Double, wsc: Double, hsc: Double, fileIcon: NSImage?) {
    let w = 34*wsc, h = 42*hsc
    let x = cx-w/2, y = cy-h/2
    let fold = 8.0*min(wsc,hsc)

    // Use real file icon if available
    if let icon = fileIcon,
       let cgImg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width:0,height:3), blur:8, color: CGColor(gray:0, alpha:0.45))
        let rect = CGRect(x:x, y:y, width:w, height:h)
        cg.draw(cgImg, in: rect)
        cg.restoreGState()
        return
    }

    // Generic document shape
    cg.saveGState()
    cg.setShadow(offset: CGSize(width:0,height:3), blur:8, color: CGColor(gray:0, alpha:0.45))
    cg.setFillColor(CGColor(red:0.957,green:0.957,blue:0.965,alpha:1))
    let bp = CGMutablePath()
    bp.move(to: CGPoint(x:x+2,y:y))
    bp.addLine(to: CGPoint(x:x+w-fold,y:y))
    bp.addLine(to: CGPoint(x:x+w,y:y+fold))
    bp.addLine(to: CGPoint(x:x+w,y:y+h-2))
    bp.addQuadCurve(to: CGPoint(x:x+w-2,y:y+h), control:CGPoint(x:x+w,y:y+h))
    bp.addLine(to: CGPoint(x:x+2,y:y+h))
    bp.addQuadCurve(to: CGPoint(x:x,y:y+h-2), control:CGPoint(x:x,y:y+h))
    bp.addLine(to: CGPoint(x:x,y:y+2))
    bp.addQuadCurve(to: CGPoint(x:x+2,y:y), control:CGPoint(x:x,y:y))
    bp.closeSubpath()
    cg.addPath(bp); cg.fillPath()
    cg.restoreGState()

    // Fold
    cg.setFillColor(CGColor(red:0.835,green:0.839,blue:0.859,alpha:1))
    let fp = CGMutablePath()
    fp.move(to: CGPoint(x:x+w-fold,y:y)); fp.addLine(to: CGPoint(x:x+w-fold,y:y+fold)); fp.addLine(to: CGPoint(x:x+w,y:y+fold))
    cg.addPath(fp); cg.fillPath()

    // Blue accent line
    cg.setFillColor(CGColor(red:0.231,green:0.510,blue:0.961,alpha:1))
    cg.addRect(CGRect(x:x+w*0.18, y:y+h*0.58, width:w*0.64, height:h*0.16))
    cg.fillPath()
}

// MARK: - Rounded rect helper (mirrors reference rr())

func roundedRect(_ rect: CGRect, r rr: Double) -> Path {
    let r = max(0, min(rr, Double(rect.width)/2, Double(rect.height)/2))
    var p = Path()
    p.addRoundedRect(in: rect, cornerSize: CGSize(width:r, height:r))
    return p
}
