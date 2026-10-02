import AppKit
import Foundation
import IOKit.ps

// MARK: - SystemMonitor
// Samples CPU, memory and battery for the System pill and for Mochi's mood
// (sweaty when the CPU is pegged, sleepy when the battery runs low).
// Ticks every 2 s while the System card is on screen, every 10 s otherwise,
// and does nothing at all while the island is hidden or the pill is switched off.

@MainActor
final class SystemMonitor {
    static let shared = SystemMonitor()

    private var timer: Timer?
    private var tickCount = 0
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var hotStreak = 0
    private var cpuHot = false
    private var warnedLowBattery = false
    private var lastOnAC: Bool?
    private var lastLevel: Double?

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { _ in
            Task { @MainActor in SystemMonitor.shared.tick() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Power events come from the system (no polling): charger in/out, each battery percent
        let now = Self.power()
        lastOnAC = now.onAC
        lastLevel = now.level
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            Task { @MainActor in SystemMonitor.shared.powerChanged() }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    // MARK: - Power banners

    /// Charger plugged in → "Charging" banner and a happy Mochi. Battery crossing 20 % / 10 % → warning.
    private func powerChanged() {
        let power = Self.power()
        guard let level = power.level else { return }
        let wasOnAC = lastOnAC, wasLevel = lastLevel
        lastOnAC = power.onAC
        lastLevel = level

        let app = AppState.shared
        guard app.announcePower, app.activeIntegrations.contains("integration_system") else { return }
        if power.onAC && wasOnAC == false {
            announcePower(level: level, charging: true, minutes: power.minutes)
        } else if !power.onAC, let wasLevel,
                  [0.20, 0.10].contains(where: { wasLevel > $0 && level <= $0 }) {
            announcePower(level: level, charging: false, minutes: power.minutes)
        }
    }

    func announcePower(level: Double, charging: Bool, minutes: Int?) {
        let time = minutes.map { Countdown.short(TimeInterval($0 * 60)) }
        let toast = charging
            ? IslandToast(symbol: "bolt.fill", title: level >= 0.995 ? "Fully charged" : "Charging",
                          subtitle: time.map { "\($0) until full" } ?? "Power connected",
                          accent: "#34D399", focusId: "integration_system", battery: level, charging: true)
            : IslandToast(symbol: "battery.25", title: "Low battery",
                          subtitle: time.map { "About \($0) left" } ?? "Plug in soon",
                          accent: level <= 0.10 ? "#F4505E" : "#F5A524", focusId: "integration_system",
                          battery: level, charging: false)
        IslandWindowController.shared?.showToast(toast, duration: 4.2)
        if charging {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .botReact, object: BotReaction.zap)
            }
        }
    }

    private func tick() {
        let app = AppState.shared
        guard app.activeIntegrations.contains("integration_system"), app.mode != .hidden else {
            lastTicks = nil   // stale baseline would skew the next reading
            return
        }
        tickCount += 1
        let onScreen = app.mode == .expanded && app.focusId == "integration_system"
        guard onScreen || tickCount % 5 == 0 || app.systemStats == nil else { return }
        sample()
    }

    private func sample() {
        let app = AppState.shared

        // CPU: share of non-idle ticks since the previous sample
        var cpu = app.systemStats?.cpu ?? 0
        if let now = Self.cpuTicks() {
            if let last = lastTicks, now.total > last.total {
                cpu = Double(now.busy - last.busy) / Double(now.total - last.total)
            }
            lastTicks = now
        }
        cpu = min(max(cpu, 0), 1)

        // Hysteresis so Mochi doesn't flicker between moods
        if cpu >= 0.85 { hotStreak += 1 } else if cpu < 0.70 { hotStreak = 0; cpuHot = false }
        if hotStreak >= 3 { cpuHot = true }

        let mem = Self.memory()
        let power = Self.power()
        let thermal = ProcessInfo.processInfo.thermalState

        let stats = SystemStats(
            cpu: cpu, memUsed: mem.used, memTotal: mem.total,
            battery: power.level, isCharging: power.charging, onAC: power.onAC,
            minutesRemaining: power.minutes, cpuHot: cpuHot,
            thermalWarning: thermal == .serious || thermal == .critical)
        if stats != app.systemStats { app.systemStats = stats }

        updatePill(stats)
    }

    /// Low battery: one amber badge + reveal when crossing 20 %, cleared once plugged in.
    private func updatePill(_ stats: SystemStats) {
        let app = AppState.shared
        guard let idx = app.tasks.firstIndex(where: { $0.id == "integration_system" }) else { return }
        if stats.batteryLow && !warnedLowBattery {
            warnedLowBattery = true
            if app.focusId != "integration_system" { app.tasks[idx].pillBadge = .approval }
            SoundEngine.shared.play("yawn")
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        } else if !stats.batteryLow && warnedLowBattery {
            warnedLowBattery = false
            app.tasks[idx].pillBadge = nil
        }
    }

    // MARK: - Readings

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    /// "Memory Used" as Activity Monitor counts it: app memory + wired + compressed.
    private static func memory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(getpagesize())
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    private static func power() -> (level: Double?, charging: Bool, onAC: Bool, minutes: Int?) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false, true, nil)
        }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let raw = (charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int ?? -1
            let minutes = raw > 0 && (charging || !onAC) ? raw : nil
            return (Double(cur) / Double(max), charging, onAC, minutes)
        }
        return (nil, false, true, nil)
    }
}
