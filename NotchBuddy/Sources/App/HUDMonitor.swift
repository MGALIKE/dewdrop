import AppKit
import AudioToolbox
import CoreAudio

// MARK: - HUDMonitor
// Volume and brightness as Dynamic-Island sliders under the notch.
// Both are event-driven (a CoreAudio property listener, a DisplayServices notification):
// nothing is polled, so the cost is zero until a key is pressed.
//
// The slider in the banner is live: dragging it sets the volume or the brightness.
// macOS still shows its own indicator; there is no supported way to switch that off.

@MainActor
final class HUDMonitor {
    static let shared = HUDMonitor()

    private var device: AudioDeviceID = kAudioObjectUnknown
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var volumeBlock: AudioObjectPropertyListenerBlock?
    private var lastVolume: Double = -1
    private var lastMuted = false
    private var lastBrightness: Double = -1
    private var quietUntil = Date.distantPast      // our own writes must not echo back as banners

    private static let volumeToast = UUID()
    private static let brightnessToast = UUID()

    private init() {}

    func start() {
        // Default output device (speakers ↔ AirPods…)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in HUDMonitor.shared.outputDeviceChanged() }
        }
        deviceBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        attach(Self.defaultOutputDevice())

        Brightness.onChange {
            Task { @MainActor in HUDMonitor.shared.brightnessNotified() }
        }
        lastBrightness = Brightness.get() ?? -1
    }

    // MARK: Volume

    private func attach(_ new: AudioDeviceID) {
        if device != kAudioObjectUnknown, let block = volumeBlock {
            for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, block)
            }
        }
        device = new
        guard new != kAudioObjectUnknown else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in HUDMonitor.shared.volumeChanged() }
        }
        volumeBlock = block
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(new, &address, DispatchQueue.main, block)
        }
        lastVolume = Self.volume(of: new) ?? -1
        lastMuted = Self.muted(new)
    }

    private func outputDeviceChanged() {
        let new = Self.defaultOutputDevice()
        guard new != device else { return }
        attach(new)
        guard AppState.shared.hudEnabled, new != kAudioObjectUnknown else { return }
        // New output (AirPods in, headphones out…): say where the sound goes now
        let name = Self.name(of: new)
        IslandWindowController.shared?.showToast(IslandToast(
            symbol: Self.symbol(for: name, device: new), title: name,
            subtitle: lastVolume >= 0 ? "Sound output · \(Int((lastVolume * 100).rounded()))%" : "Sound output",
            accent: "#60A5FA"), duration: 3.2)
    }

    private func volumeChanged() {
        guard device != kAudioObjectUnknown, let volume = Self.volume(of: device) else { return }
        let muted = Self.muted(device)
        guard abs(volume - lastVolume) > 0.001 || muted != lastMuted else { return }
        lastVolume = volume
        lastMuted = muted
        guard AppState.shared.hudEnabled, Date() > quietUntil else { return }
        show(.volume, level: volume, muted: muted)
    }

    // MARK: Brightness

    /// The system reports ambient-light adjustments in bursts of dozens of notifications, and
    /// reading the level is a round trip to another process: look at once, then at most every
    /// 0.15 s while the burst lasts.
    private func brightnessNotified() {
        let now = CACurrentMediaTime()
        if now - lastBrightnessCheck > 0.15 {
            lastBrightnessCheck = now
            brightnessChanged()
        } else if !brightnessCheckPending {
            brightnessCheckPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                self.brightnessCheckPending = false
                self.lastBrightnessCheck = CACurrentMediaTime()
                self.brightnessChanged()
            }
        }
    }

    private var lastBrightnessCheck = 0.0
    private var brightnessCheckPending = false

    private func brightnessChanged() {
        guard let level = Brightness.get(), abs(level - lastBrightness) > 0.004 else { return }
        // Ambient-light adjustments creep in tiny steps; a key press jumps a sixteenth
        let step = abs(level - lastBrightness)
        lastBrightness = level
        let showing = AppState.shared.toast?.hud == .brightness && AppState.shared.view == .toast
        guard AppState.shared.hudEnabled, Date() > quietUntil, step > 0.02 || showing else { return }
        show(.brightness, level: level, muted: false)
    }

    // MARK: Banner

    func show(_ kind: HUDKind, level: Double, muted: Bool) {
        IslandWindowController.shared?.showToast(IslandToast(
            id: kind == .volume ? Self.volumeToast : Self.brightnessToast,
            title: kind == .volume ? "Volume" : "Brightness", subtitle: "",
            accent: kind == .volume ? "#60A5FA" : "#FBBF24",
            hud: kind, level: level, muted: muted), duration: 1.7)
    }

    /// Slider dragged in the banner.
    func set(_ kind: HUDKind, level: Double) {
        let level = min(1, max(0, level))
        quietUntil = Date().addingTimeInterval(0.4)
        switch kind {
        case .volume:
            guard device != kAudioObjectUnknown else { return }
            var value = Float32(level)
            var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            if lastMuted && level > 0 {
                var off: UInt32 = 0
                var mute = Self.address(kAudioDevicePropertyMute)
                AudioObjectSetPropertyData(device, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
                lastMuted = false
            }
            lastVolume = level
        case .brightness:
            Brightness.set(level)
            lastBrightness = level
        }
        // Keep the banner in step with the finger
        if var toast = AppState.shared.toast, toast.hud == kind {
            toast.level = level
            toast.muted = false
            IslandWindowController.shared?.showToast(toast, duration: 1.7)
        }
    }

    // MARK: CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func volume(of device: AudioDeviceID) -> Double? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    private static func muted(_ device: AudioDeviceID) -> Bool {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private static func name(of device: AudioDeviceID) -> String {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name else { return "Sound output" }
        return name.takeRetainedValue() as String
    }

    private static func symbol(for name: String, device: AudioDeviceID) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") || lower.contains("headphone") || lower.contains("buds") { return "headphones" }
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        default: return "hifispeaker.fill"
        }
    }
}

// MARK: - Display brightness
// There is no public API for the built-in display's brightness on Apple silicon. DisplayServices
// is the framework the system's own brightness keys go through; it is looked up at run time, and
// if any symbol is missing the brightness banner simply never appears.

enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias RegisterFn = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    nonisolated(unsafe) private static var handler: (@Sendable () -> Void)?

    static func get() -> Double? {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        var value: Float = 0
        guard unsafeBitCast(symbol, to: GetFn.self)(CGMainDisplayID(), &value) == 0 else { return nil }
        return Double(value)
    }

    static func set(_ level: Double) {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return }
        _ = unsafeBitCast(symbol, to: SetFn.self)(CGMainDisplayID(), Float(level))
    }

    /// Calls `body` (on the main run loop) whenever the brightness of the main display changes.
    @MainActor
    static func onChange(_ body: @escaping @Sendable () -> Void) {
        guard let handle,
              let symbol = dlsym(handle, "DisplayServicesRegisterForBrightnessChangeNotifications") else { return }
        handler = body
        _ = unsafeBitCast(symbol, to: RegisterFn.self)(CGMainDisplayID(), nil) { _, _, _, _, _ in
            Brightness.handler?()
        }
    }
}
