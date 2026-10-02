import Foundation
import Combine
import IOKit.pwr_mgt

// MARK: - KeepAwake
// Stops the Mac (and its display) from going to sleep on idle — for long Claude Code runs,
// downloads or presentations. Either switched on by hand from the System card, or held
// automatically while Claude Code is working when that option is on in Settings.

@MainActor
final class KeepAwake {
    static let shared = KeepAwake()

    private var manualAssertion: IOPMAssertionID = 0
    private var autoAssertion: IOPMAssertionID = 0
    private var watcher: AnyCancellable?

    private init() {}

    func start() {
        // Follow Claude Code's state for the automatic mode
        watcher = AppState.shared.$tasks
            .map { tasks -> Bool in
                guard let claude = tasks.first(where: { $0.id == "integration_claude" }) else { return false }
                return [.working, .thinking, .searching].contains(claude.state)
            }
            .removeDuplicates()
            .sink { busy in
                Task { @MainActor in KeepAwake.shared.updateAuto(claudeBusy: busy) }
            }
    }

    /// Manual switch: keeps the display on too.
    func set(_ on: Bool) {
        AppState.shared.keepAwake = on
        if on {
            hold(&manualAssertion, type: kIOPMAssertionTypePreventUserIdleDisplaySleep, reason: "Dewdrop: keep awake")
        } else {
            release(&manualAssertion)
        }
        SoundEngine.shared.play(on ? "pop" : "blip")
    }

    func toggle() { set(!AppState.shared.keepAwake) }

    /// Automatic: the system stays up while Claude Code works (the display may still dim).
    private func updateAuto(claudeBusy: Bool) {
        if claudeBusy && AppState.shared.keepAwakeAuto {
            hold(&autoAssertion, type: kIOPMAssertionTypePreventUserIdleSystemSleep, reason: "Dewdrop: Claude Code is working")
        } else {
            release(&autoAssertion)
        }
    }

    func releaseAll() {
        release(&manualAssertion)
        release(&autoAssertion)
    }

    private func hold(_ id: inout IOPMAssertionID, type: String, reason: String) {
        guard id == 0 else { return }
        var new: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason as CFString, &new)
        if result == kIOReturnSuccess { id = new }
    }

    private func release(_ id: inout IOPMAssertionID) {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }
}
