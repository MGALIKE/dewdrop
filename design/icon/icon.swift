import AppKit
import CoreGraphics

// Renders the Dewdrop app icon (1024 px) and the menu bar template (drop silhouette).
// usage: swiftc -O -o icon icon.swift && ./icon <out dir>   (then sips the 1024 into the appiconset sizes)
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let N = 1024.0

func ctx(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)   // y down, like the app's canvases
    return c
}
func save(_ c: CGContext, _ name: String) {
    let img = c.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/" + name))
}
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func grad(_ cols: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: cols as CFArray, locations: locs)! }

/// Dew's outline: a circle with two tangents meeting at a rounded tip (same math as BotEngine.dropPath)
func dropPath(rx: CGFloat, ry: CGFloat, R: CGFloat) -> CGPath {
    let n = 192, tip: CGFloat = 1.75, soft: CGFloat = 0.16
    let cone = acos(1 / tip)
    let p = CGMutablePath()
    for i in 0...n {
        let a = CGFloat(i) / CGFloat(n) * .pi * 2 + .pi / 2
        let ca = cos(a), sa = sin(a)
        let phi = acos(max(-1, min(1, -sa)))
        var rho: CGFloat = 1
        if phi < cone { let k = soft * (1 - phi / cone); rho = 1 / cos(cone - (phi * phi + k * k).squareRoot()) }
        let pt = CGPoint(x: rx * ca * rho, y: ry * sa * rho)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

// ---------- App icon ----------
let c = ctx(Int(N), Int(N))
// macOS icon shape: the system masks it on macOS 26; draw our own squircle for older systems
let inset = N * 0.0
let square = CGRect(x: inset, y: inset, width: N - 2 * inset, height: N - 2 * inset)
let shape = CGPath(roundedRect: square, cornerWidth: N * 0.2237, cornerHeight: N * 0.2237, transform: nil)
c.saveGState(); c.addPath(shape); c.clip()
// Background: deep water, light from the upper left
c.drawLinearGradient(grad([rgb(0.10, 0.36, 0.78), rgb(0.05, 0.16, 0.42), rgb(0.03, 0.08, 0.24)], [0, 0.6, 1]),
                     start: CGPoint(x: 0, y: 0), end: CGPoint(x: N * 0.6, y: N), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Caustic light in the water
c.setBlendMode(.plusLighter)
c.drawRadialGradient(grad([rgb(0.45, 0.80, 1, 0.55), rgb(0.45, 0.80, 1, 0)], [0, 1]),
                     startCenter: CGPoint(x: N * 0.28, y: N * 0.22), startRadius: 0, endCenter: CGPoint(x: N * 0.28, y: N * 0.22), endRadius: N * 0.55, options: [])
c.setBlendMode(.normal)
// a breath of teal low on the right, the way deep water turns
c.drawRadialGradient(grad([rgb(0.20, 0.75, 0.75, 0.30), rgb(0.20, 0.75, 0.75, 0)], [0, 1]),
                     startCenter: CGPoint(x: N * 0.85, y: N * 0.95), startRadius: 0, endCenter: CGPoint(x: N * 0.85, y: N * 0.95), endRadius: N * 0.6, options: [])
// a little depth at the edges
c.drawRadialGradient(grad([rgb(0, 0, 0.1, 0), rgb(0, 0, 0.1, 0.35)], [0.55, 1]),
                     startCenter: CGPoint(x: N * 0.5, y: N * 0.5), startRadius: 0, endCenter: CGPoint(x: N * 0.5, y: N * 0.5), endRadius: N * 0.75, options: [.drawsAfterEndLocation])
// Ripple rings low in the picture (where the drop would land)
c.setStrokeColor(rgb(1, 1, 1, 0.10))
for (i, r) in [0.30, 0.42, 0.55].enumerated() {
    c.setLineWidth(N * (0.012 - Double(i) * 0.003))
    c.strokeEllipse(in: CGRect(x: N * 0.5 - N * r, y: N * 0.86 - N * r * 0.22, width: N * r * 2, height: N * r * 0.44))
}

// The drop
let R = N * 0.235
let cx = N * 0.5, cy = N * 0.555
let drop = dropPath(rx: R, ry: R * 0.94, R: R)
c.translateBy(x: cx, y: cy)
// shadow in the water
c.saveGState()
c.setFillColor(rgb(0, 0, 0, 0.001))
c.setShadow(offset: CGSize(width: 0, height: N * 0.03), blur: N * 0.06, color: rgb(0.0, 0.05, 0.2, 0.55))
c.addPath(drop); c.fillPath()
c.restoreGState()
// body: glass
c.saveGState(); c.addPath(drop); c.clip()
c.drawLinearGradient(grad([rgb(0.80, 0.93, 1, 0.55), rgb(0.55, 0.80, 1, 0.35), rgb(0.35, 0.60, 0.95, 0.45)], [0, 0.5, 1]),
                     start: CGPoint(x: -R, y: -R * 1.7), end: CGPoint(x: R * 0.6, y: R), options: [])
// dark flank on the lit side (a drop is a lens)
c.drawLinearGradient(grad([rgb(0.0, 0.08, 0.30, 0.45), rgb(0.0, 0.08, 0.30, 0.10), rgb(0, 0, 0, 0)], [0, 0.25, 0.45]),
                     start: CGPoint(x: -R * 0.95, y: -R), end: CGPoint(x: R * 0.55, y: R * 0.7), options: [])
// liquid: fills the lower half, surface slightly curved
let top = R * 0.94 - 0.60 * 2 * R * 0.94
let pool = CGMutablePath()
pool.move(to: CGPoint(x: -R * 1.3, y: top + R * 0.10))
pool.addQuadCurve(to: CGPoint(x: R * 1.3, y: top + R * 0.10), control: CGPoint(x: 0, y: top - R * 0.12))
pool.addLine(to: CGPoint(x: R * 1.3, y: R * 1.4)); pool.addLine(to: CGPoint(x: -R * 1.3, y: R * 1.4)); pool.closeSubpath()
c.saveGState(); c.addPath(pool); c.clip()
c.drawLinearGradient(grad([rgb(0.25, 0.62, 1, 0.85), rgb(0.10, 0.40, 0.95, 0.95)], [0, 1]),
                     start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: R), options: [])
c.setBlendMode(.plusLighter)
c.drawRadialGradient(grad([rgb(1, 1, 1, 0.35), rgb(1, 1, 1, 0)], [0, 1]), startCenter: CGPoint(x: R * 0.4, y: R * 0.45), startRadius: 0, endCenter: CGPoint(x: R * 0.4, y: R * 0.45), endRadius: R * 0.9, options: [])
c.setBlendMode(.normal)
c.restoreGState()
// surface line
let surf = CGMutablePath()
surf.move(to: CGPoint(x: -R * 1.3, y: top + R * 0.10)); surf.addQuadCurve(to: CGPoint(x: R * 1.3, y: top + R * 0.10), control: CGPoint(x: 0, y: top - R * 0.12))
c.setStrokeColor(rgb(1, 1, 1, 0.75)); c.setLineWidth(R * 0.035); c.addPath(surf); c.strokePath()
// light gathered on the far side, and the sky in the tip
c.setBlendMode(.plusLighter)
c.drawRadialGradient(grad([rgb(1, 1, 1, 0.45), rgb(0.6, 0.85, 1, 0.25), rgb(1, 1, 1, 0)], [0, 0.45, 1]), startCenter: CGPoint(x: R * 0.58, y: R * 0.52), startRadius: 0, endCenter: CGPoint(x: R * 0.58, y: R * 0.52), endRadius: R * 0.55, options: [])
c.drawLinearGradient(grad([rgb(1, 1, 1, 0.35), rgb(1, 1, 1, 0)], [0, 1]), start: CGPoint(x: 0, y: -R * 1.6), end: CGPoint(x: 0, y: -R * 0.5), options: [])
c.setBlendMode(.normal)
// rim (stroked wide, clipped to the inside)
c.setLineWidth(R * 0.10)
c.addPath(drop)
c.replacePathWithStrokedPath(); c.clip()
c.drawLinearGradient(grad([rgb(1, 1, 1, 0.95), rgb(0.73, 0.90, 0.99, 0.45), rgb(1, 1, 1, 0.12), rgb(0.96, 0.82, 1, 0.5), rgb(1, 1, 1, 0.8)], [0, 0.24, 0.5, 0.86, 1]),
                     start: CGPoint(x: -R * 0.8, y: -R * 1.2), end: CGPoint(x: R * 0.8, y: R), options: [])
c.restoreGState()
// hard highlight and its echo
c.setStrokeColor(rgb(1, 1, 1, 0.92)); c.setLineCap(.round); c.setLineWidth(R * 0.085)
c.addArc(center: .zero, radius: R * 0.70, startAngle: .pi * 200 / 180, endAngle: .pi * 238 / 180, clockwise: false); c.strokePath()
c.setFillColor(rgb(1, 1, 1, 0.85)); c.fillEllipse(in: CGRect(x: -R * 0.335, y: -R * 0.705, width: R * 0.09, height: R * 0.09))
c.setStrokeColor(rgb(1, 1, 1, 0.38)); c.setLineWidth(R * 0.05)
c.addArc(center: .zero, radius: R * 0.80, startAngle: .pi * 22 / 180, endAngle: .pi * 62 / 180, clockwise: false); c.strokePath()
// eyes
c.saveGState(); c.addPath(drop); c.clip()
c.setShadow(offset: CGSize(width: 0, height: R * 0.02), blur: R * 0.06, color: rgb(0, 0, 0, 0.40))
c.setFillColor(rgb(1, 1, 1, 0.97))
let ew = R * 0.21, eh = R * 0.36, sp = sin(0.40) * R, ey = sin(0.14) * R * 0.94
for sd in [-1.0, 1.0] {
    c.addPath(CGPath(roundedRect: CGRect(x: sd * sp - ew / 2, y: ey - eh / 2, width: ew, height: eh), cornerWidth: ew / 2, cornerHeight: ew / 2, transform: nil)); c.fillPath()
}
c.restoreGState()
c.restoreGState()
save(c, "icon_1024.png")

// ---------- Menu bar template: a drop with eye holes ----------
for (scale, name) in [(1, "menubar.png"), (2, "menubar@2x.png"), (3, "menubar@3x.png")] {
    let pt = 18.0, w = Int(pt * Double(scale)), h = Int(pt * Double(scale))
    let m = ctx(w, h)
    let r = pt * Double(scale) * 0.30
    m.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) * 0.60)
    let d = dropPath(rx: r, ry: r * 0.94, R: r)
    m.setFillColor(rgb(0, 0, 0, 1)); m.addPath(d); m.fillPath()
    m.setBlendMode(.clear)
    let ew = r * 0.24, eh = r * 0.40, sp = sin(0.40) * r, ey = sin(0.14) * r * 0.94
    for sd in [-1.0, 1.0] {
        m.addPath(CGPath(roundedRect: CGRect(x: sd * sp - ew / 2, y: ey - eh / 2, width: ew, height: eh), cornerWidth: ew / 2, cornerHeight: ew / 2, transform: nil)); m.fillPath()
    }
    save(m, name)
}
print("ok")
