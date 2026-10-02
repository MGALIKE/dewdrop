import SwiftUI
import QuartzCore

// Animations that run for as long as something is on screen are played by Core Animation: the
// system moves the layers by itself, and the app neither draws nor wakes up for them.

// MARK: - Equalizer bars

/// Little bars dancing while music plays; they settle flat when paused. Four layers animated by
/// Core Animation: they sit in the folded notch for as long as music plays, so they must not
/// cost the app a frame.
struct EqualizerBars: View {
    let active: Bool
    var color: Color = .white.opacity(0.85)
    var height: CGFloat = 9

    var body: some View {
        BarsLayerView(active: active, color: NSColor(color), height: height)
            .frame(width: BarsView.width, height: height)
            .allowsHitTesting(false)
    }
}

private struct BarsLayerView: NSViewRepresentable {
    let active: Bool
    let color: NSColor
    let height: CGFloat

    func makeNSView(context: Context) -> BarsView { BarsView() }
    func updateNSView(_ view: BarsView, context: Context) {
        view.configure(active: active, color: color, height: height)
    }
}

final class BarsView: NSView {
    static let barWidth: CGFloat = 2, gap: CGFloat = 1.5, count = 4
    static let width = CGFloat(count) * barWidth + CGFloat(count - 1) * gap

    private let bars = (0..<BarsView.count).map { _ in CALayer() }
    private var active = false
    private var color = NSColor.white
    private var barHeight: CGFloat = 9
    private var configured = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = BarsView.barWidth / 2
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Layers drop their animations when they leave the window
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    func configure(active: Bool, color: NSColor, height: CGFloat) {
        guard !configured || active != self.active || color != self.color || height != barHeight else { return }
        configured = true
        self.active = active
        self.color = color
        barHeight = height
        apply()
    }

    private func apply() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.backgroundColor = color.cgColor
            bar.position = CGPoint(x: BarsView.barWidth / 2 + CGFloat(i) * (BarsView.barWidth + BarsView.gap),
                                   y: barHeight / 2)
            bar.removeAnimation(forKey: "dance")
            guard active, window != nil else {
                bar.bounds = CGRect(x: 0, y: 0, width: BarsView.barWidth, height: barHeight * 0.25)
                continue
            }
            // Each bar rises and falls at its own pace, quick off the floor and slow at the top
            bar.bounds = CGRect(x: 0, y: 0, width: BarsView.barWidth, height: barHeight * 0.3)
            let dance = CABasicAnimation(keyPath: "bounds.size.height")
            dance.fromValue = barHeight * 0.3
            dance.toValue = barHeight
            dance.duration = .pi / (3.1 + Double(i) * 0.9) / 2
            dance.autoreverses = true
            dance.repeatCount = .infinity
            dance.timingFunction = CAMediaTimingFunction(name: .easeOut)
            dance.timeOffset = Double(i) * 0.37
            dance.isRemovedOnCompletion = false
            dance.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            bar.add(dance, forKey: "dance")
        }
        CATransaction.commit()
    }
}

// MARK: - Pulsing dots

/// One or more dots that pulse for as long as they are shown: the green dot of a busy session,
/// the three dots while a reply is on its way.
struct PulsingDots: View {
    var count = 1
    var color: Color
    var size: CGFloat
    var spacing: CGFloat = 4
    var scale: ClosedRange<CGFloat> = 1...1.25
    var opacity: ClosedRange<Float> = 1...1
    var glow: ClosedRange<CGFloat> = 0...0      // shadow radius, in the dot's colour
    var duration: Double = 0.9                  // one way
    var stagger: Double = 0                     // delay between neighbours
    var active = true

    var body: some View {
        PulsingDotsLayerView(dots: self)
            .frame(width: CGFloat(count) * size + CGFloat(count - 1) * spacing, height: size)
            .allowsHitTesting(false)
    }
}

private struct PulsingDotsLayerView: NSViewRepresentable {
    let dots: PulsingDots

    func makeNSView(context: Context) -> PulsingDotsView { PulsingDotsView() }
    func updateNSView(_ view: PulsingDotsView, context: Context) { view.configure(dots) }
}

final class PulsingDotsView: NSView {
    private var layers: [CALayer] = []
    private var dots: PulsingDots?
    private var signature = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Layers drop their animations when they leave the window
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    func configure(_ dots: PulsingDots) {
        let new = "\(dots.count)|\(dots.color)|\(dots.size)|\(dots.active)"
        self.dots = dots
        guard new != signature else { return }
        signature = new
        apply()
    }

    private func apply() {
        guard let dots, let root = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while layers.count < dots.count {
            let dot = CALayer()
            root.addSublayer(dot)
            layers.append(dot)
        }
        while layers.count > dots.count { layers.removeLast().removeFromSuperlayer() }
        let colour = NSColor(dots.color).cgColor
        for (i, dot) in layers.enumerated() {
            dot.bounds = CGRect(x: 0, y: 0, width: dots.size, height: dots.size)
            dot.position = CGPoint(x: dots.size / 2 + CGFloat(i) * (dots.size + dots.spacing), y: dots.size / 2)
            dot.cornerRadius = dots.size / 2
            dot.backgroundColor = colour
            dot.shadowColor = colour
            dot.shadowOffset = .zero
            dot.shadowOpacity = dots.glow.upperBound > 0 ? 0.8 : 0
            dot.shadowRadius = dots.glow.lowerBound
            dot.transform = CATransform3DMakeScale(dots.scale.lowerBound, dots.scale.lowerBound, 1)
            dot.opacity = dots.opacity.lowerBound
            dot.removeAnimation(forKey: "pulse")
            guard dots.active, window != nil else { continue }

            var parts: [CABasicAnimation] = []
            func part(_ keyPath: String, _ from: Any, _ to: Any) {
                let a = CABasicAnimation(keyPath: keyPath)
                a.fromValue = from
                a.toValue = to
                parts.append(a)
            }
            if dots.scale.lowerBound != dots.scale.upperBound {
                part("transform.scale", dots.scale.lowerBound, dots.scale.upperBound)
            }
            if dots.opacity.lowerBound != dots.opacity.upperBound {
                part("opacity", dots.opacity.lowerBound, dots.opacity.upperBound)
            }
            if dots.glow.lowerBound != dots.glow.upperBound {
                part("shadowRadius", dots.glow.lowerBound, dots.glow.upperBound)
            }
            let pulse = CAAnimationGroup()
            pulse.animations = parts
            pulse.duration = dots.duration
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.beginTime = dot.convertTime(CACurrentMediaTime(), from: nil) + Double(i) * dots.stagger
            pulse.isRemovedOnCompletion = false
            pulse.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            dot.add(pulse, forKey: "pulse")
        }
        CATransaction.commit()
    }
}
