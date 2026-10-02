#if DEBUG
import AppKit

/// Development only: opens and closes the island on a loop and logs how smoothly each opening ran
/// (main-thread frame intervals from a display link). `-debugBounce 1`
@MainActor
final class PerfProbe: NSObject {
    static let shared = PerfProbe()

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var label = ""

    func bounce(view: IslandView = .overview) {
        guard let controller = IslandWindowController.shared else { return }
        let opening = AppState.shared.mode != .expanded
        measure(opening ? "open" : "close")
        if opening { controller.expand(to: view) } else { controller.collapse() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.bounce(view: view) }
    }

    private func measure(_ label: String) {
        guard let window = IslandWindowController.shared?.window, let view = window.contentView else { return }
        self.label = label
        intervals = []
        last = 0
        link?.invalidate()
        let l = view.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.report() }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if last > 0 { intervals.append((now - last) * 1000) }
        last = now
    }

    private func report() {
        link?.invalidate()
        link = nil
        guard !intervals.isEmpty else { return }
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        let slow = intervals.filter { $0 > median * 1.6 }
        appendAppLog("nb.log", String(format: "PERF %@ frames=%d median=%.1fms max=%.1fms slow=%d slowSum=%.0fms first5=%@",
                                      label, intervals.count, median, sorted.last ?? 0, slow.count, slow.reduce(0, +),
                                      intervals.prefix(6).map { String(format: "%.0f", $0) }.joined(separator: ",")))
    }
}

/// Development only: counts what is being redrawn and why, and logs it every five seconds.
/// `-debugFrames 1`
@MainActor
enum FrameLog {
    static let enabled = UserDefaults.standard.bool(forKey: "debugFrames")
    private static var counts: [String: Int] = [:]
    private static var last = CACurrentMediaTime()

    static func hit(_ name: String) {
        guard enabled else { return }
        counts[name, default: 0] += 1
        let now = CACurrentMediaTime()
        guard now - last >= 5 else { return }
        appendAppLog("nb.log", "FRAMES/5s " + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        counts = [:]
        last = now
    }
}

extension BotEngine {
    /// Which of the `isAnimating` conditions holds (for the frame log).
    var animatingReason: String {
        if !tweens.isEmpty { return "tween:" + tweens.keys.sorted().joined(separator: "+") }
        if !particles.isEmpty { return "particles" }
        if abs(tgYaw - yaw) > 0.02 || abs(tgPitch - pitch) > 0.02 { return "look" }
        if abs(tgTilt - tilt) > 0.01 { return "tilt" }
        if abs(tgSy - sy) > 0.004 || abs(tgSx - sx) > 0.004 || abs(tgEs - es) > 0.004 { return "scale" }
        if abs(col.0 - colT.0) + abs(col.1 - colT.1) + abs(col.2 - colT.2) > 0.01 { return "colour" }
        if morph > 0.01 || slotH > 0.005 || abs(slotHTarget - slotH) > 0.005 || abs(ox) > 0.002 { return "morph" }
        if isChewing || CACurrentMediaTime() < waveUntil { return "wave" }
        return propVel.contains { $0 != 0 } ? "prop" : "none"
    }
}
#endif
