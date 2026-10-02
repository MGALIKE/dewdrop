import AppKit

// MARK: - TimerEngine
// Focus timer (Pomodoro) and quick reminders for the Timer pill.
// Countdowns are stored as end dates; views tick themselves only while on screen and the
// engine arms a single one-shot timer for the next deadline — nothing runs in between.

@MainActor
final class TimerEngine {
    static let shared = TimerEngine()

    static let focusMinutes = 25
    static let breakMinutes = 5
    static let maxReminders = 5

    private var fireTimer: Timer?
    private var started = false
    private let storeKey = "skillCountdowns"

    private var app: AppState { AppState.shared }

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode([Countdown].self, from: data) {
            app.countdowns = saved
        }
        if ud.string(forKey: "pomodoroDay") == Self.today {
            app.pomodorosToday = ud.integer(forKey: "pomodoroCount")
        }
        reschedule()   // anything that came due while the app was closed fires now
    }

    // MARK: - Queries

    /// The countdown the card shows big: finished first, then focus/break, then the next reminder.
    static func primary(of items: [Countdown]) -> Countdown? {
        if let done = items.first(where: \.done) { return done }
        if let session = items.first(where: { $0.kind != .reminder }) { return session }
        return items.min { $0.remaining(at: Date()) < $1.remaining(at: Date()) }
    }

    // MARK: - Commands

    func startSession(_ kind: Countdown.Kind, minutes: Int) {
        // One focus/break at a time — a new one replaces the old.
        app.countdowns.removeAll { $0.kind != .reminder }
        let label = kind == .rest ? "Break" : "Focus"
        add(Countdown(kind: kind, label: label, total: TimeInterval(minutes * 60),
                      endDate: Date().addingTimeInterval(TimeInterval(minutes * 60))))
    }

    #if DEBUG
    /// Development only: a focus session a few seconds long, to check the running and finished states.
    func debugStart(seconds: Int) {
        app.countdowns.removeAll { $0.kind != .reminder }
        add(Countdown(kind: .focus, label: "Focus", total: TimeInterval(seconds),
                      endDate: Date().addingTimeInterval(TimeInterval(seconds))))
    }
    #endif

    func addReminder(_ text: String, minutes: Int) {
        guard app.countdowns.filter({ $0.kind == .reminder }).count < Self.maxReminders else { return }
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        add(Countdown(kind: .reminder, label: label.isEmpty ? "Reminder" : String(label.prefix(60)),
                      total: TimeInterval(minutes * 60),
                      endDate: Date().addingTimeInterval(TimeInterval(minutes * 60))))
    }

    private func add(_ c: Countdown) {
        app.countdowns.append(c)
        SoundEngine.shared.play("tick")
        commit()
    }

    func togglePause(_ id: UUID) {
        guard let i = app.countdowns.firstIndex(where: { $0.id == id }), !app.countdowns[i].done else { return }
        if let left = app.countdowns[i].pausedRemaining {
            app.countdowns[i].pausedRemaining = nil
            app.countdowns[i].endDate = Date().addingTimeInterval(left)
        } else {
            app.countdowns[i].pausedRemaining = app.countdowns[i].remaining(at: Date())
            app.countdowns[i].endDate = nil
        }
        SoundEngine.shared.play("blip")
        commit()
    }

    /// Cancels a running countdown or dismisses a finished one.
    func remove(_ id: UUID) {
        app.countdowns.removeAll { $0.id == id }
        commit()
        if !app.countdowns.contains(where: \.done) { settle() }
    }

    func snooze(_ id: UUID, minutes: Int) {
        guard let i = app.countdowns.firstIndex(where: { $0.id == id }) else { return }
        app.countdowns[i].done = false
        app.countdowns[i].total = TimeInterval(minutes * 60)
        app.countdowns[i].endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        commit()
        settle()
    }

    func cancelAll() {
        app.countdowns.removeAll()
        commit()
        settle()
    }

    // MARK: - Scheduling

    private func commit() {
        if let data = try? JSONEncoder().encode(app.countdowns) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
        reschedule()
        IslandWindowController.shared?.liveActivityChanged()
    }

    private func reschedule() {
        fireTimer?.invalidate()
        fireTimer = nil
        let now = Date()
        let due = app.countdowns.filter { !$0.done && !$0.isPaused && ($0.endDate ?? .distantFuture) <= now }
        if !due.isEmpty {
            for c in due { finish(c.id) }
            commit()
            return
        }
        guard let next = app.countdowns.compactMap({ $0.done ? nil : $0.endDate }).min() else { return }
        let t = Timer(fire: next, interval: 0, repeats: false) { _ in
            Task { @MainActor in TimerEngine.shared.reschedule() }
        }
        RunLoop.main.add(t, forMode: .common)
        fireTimer = t
    }

    // MARK: - Time's up

    private func finish(_ id: UUID) {
        guard let i = app.countdowns.firstIndex(where: { $0.id == id }) else { return }
        app.countdowns[i].done = true
        app.countdowns[i].endDate = nil
        let item = app.countdowns[i]

        if item.kind == .focus {
            app.pomodorosToday = (UserDefaults.standard.string(forKey: "pomodoroDay") == Self.today ? app.pomodorosToday : 0) + 1
            UserDefaults.standard.set(Self.today, forKey: "pomodoroDay")
            UserDefaults.standard.set(app.pomodorosToday, forKey: "pomodoroCount")
        }
        appendAppLog("nb.log", "Timer done: \(item.kind.rawValue)")

        guard let idx = app.tasks.firstIndex(where: { $0.id == "integration_timer" }) else { return }
        app.tasks[idx].state = .finished          // Mochi rolls and sparkles
        app.tasks[idx].steps = [item.label]
        SoundEngine.shared.play("finish")

        // Bring the card forward — unless Claude Code is waiting on an approval.
        if app.pendingApproval == nil {
            app.focusId = "integration_timer"
            app.isPinned = true
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                NotificationCenter.default.post(name: .botReact, object: BotReaction.party)
                AppState.shared.celebrate()
                SoundEngine.shared.play("proud")
            }
            // Don't hold the island open forever if nobody is there
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                if AppState.shared.countdowns.contains(where: \.done) { AppState.shared.isPinned = false }
            }
        } else {
            app.tasks[idx].pillBadge = .finished
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard let i = AppState.shared.tasks.firstIndex(where: { $0.id == "integration_timer" }),
                  AppState.shared.tasks[i].state == .finished else { return }
            AppState.shared.tasks[i].state = .idle
        }
    }

    /// Nothing left to acknowledge: release the pin and clear the pill.
    private func settle() {
        if app.pendingApproval == nil { app.isPinned = false }
        app.lastActivity = .now
        guard let idx = app.tasks.firstIndex(where: { $0.id == "integration_timer" }) else { return }
        app.tasks[idx].pillBadge = nil
        if app.tasks[idx].state == .finished { app.tasks[idx].state = .idle }
    }

    private static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
