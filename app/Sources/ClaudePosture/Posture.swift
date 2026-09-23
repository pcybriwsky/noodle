import AppKit

/// All scheduling logic. Lives in the single app process, so concurrent Claude sessions
/// just send events here and can never produce two cards.
@MainActor
final class Posture {
    static let graceSeconds: Double = 30
    static let readingSeconds: Double = 180
    static let workingSubtitle = "Claude's on it. Good time for a quick one."
    static let manualSubtitle = "Quick one while you're here."
    static let stoppedSubtitle = "Claude's done, finish your set"

    let store: Store
    let card: CardController
    let calendar = CalendarWatch()
    var onChange: (() -> Void)?

    private var delayTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var current: Exercise?
    private var stopped = false
    private var welcomeShowing = false

    init(store: Store, card: CardController) {
        self.store = store
        self.card = card
        card.onAction = { [weak self] action in
            switch action {
            case "done": self?.finish("done")
            case "snooze": self?.finish("snoozed")
            case "howto": self?.extendForReading()
            case "welcome-close": self?.closeWelcome()
            case let a where a.hasPrefix("focus:"):
                if let self, let f = Focus(rawValue: String(a.dropFirst(6))) {
                    self.store.apply(focus: f)
                    debug("focus \(f.rawValue)")
                }
            case "welcome-try":
                self?.closeWelcome()
                self?.showNow()
            default: debug("unknown card action \(action)")
            }
        }
    }

    func handle(_ event: String) {
        debug("event \(event)")
        switch event {
        case "prompt": prompt()
        case "stop": stop()
        case "show": showNow()
        case "intro": showWelcome()
        case "login-on": LoginItem.set(true)
        case "login-off": LoginItem.set(false)
        default: break
        }
    }

    // MARK: Events

    /// Start the delay. A pending delay isn't restarted, so back-to-back prompts
    /// from several sessions still fire on the first one's schedule.
    private func prompt() {
        guard current == nil, delayTask == nil else { return }
        let delay = max(0, store.config().delaySeconds)
        delayTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.delayTask = nil
            self.delayFired()
        }
    }

    private func stop() {
        delayTask?.cancel()
        delayTask = nil
        if current != nil, !stopped {
            stopped = true
            card.setSubtitle(Self.stoppedSubtitle)
        }
    }

    func showNow() {
        guard current == nil else { return }
        delayTask?.cancel()
        delayTask = nil
        show(subtitle: Self.manualSubtitle)
    }

    private func delayFired() {
        guard current == nil else { return }
        if welcomeShowing { return debug("not showing: intro is up") }
        if let reason = blockedReason() { return debug("not showing: \(reason)") }
        show(subtitle: Self.workingSubtitle)
    }

    /// Why an automatic card can't show right now, or nil if it can.
    func blockedReason(at now: Date = Date()) -> String? {
        let c = store.config(), s = store.state()
        if let p = s.pausedUntil, p > now { return "paused" }
        if c.quietHours.contains(now) { return "quiet hours" }
        if let n = s.nextAllowed, n > now { return "cooldown" }
        if c.holdDuringCalls && Calls.inProgress() { return "on a call" }
        if c.holdDuringCalendarEvents && calendar.busyNow(at: now) { return "calendar event" }
        if store.enabledExercises(c).isEmpty { return "no exercises enabled" }
        return nil
    }

    // MARK: Card lifecycle

    private func show(subtitle: String) {
        welcomeShowing = false
        let c = store.config()
        let list = store.enabledExercises(c)
        guard !list.isEmpty else { return debug("no exercises enabled") }
        var s = store.state()
        let i = s.rotationIndex % list.count
        let ex = list[i]
        let now = Date()
        s.rotationIndex = (i + 1) % list.count
        s.lastShown = now
        s.nextAllowed = now.addingTimeInterval(c.cooldownMinutes * 60)
        store.save(s)

        current = ex
        stopped = false
        var payload: [String: Any] = [
            "id": ex.id, "name": ex.name, "instruction": ex.instruction, "spec": ex.spec,
            "durationSeconds": ex.durationSeconds, "figure": ex.figure, "subtitle": subtitle,
            "index": i + 1, "total": list.count, "doneToday": store.doneToday(),
            "steps": ex.steps ?? [], "tip": ex.tip ?? "", "expand": c.expandSteps,
        ]
        if let svg = figureSVG(ex.figure, character: c.character) { payload["figureSVG"] = svg }
        debug("show \(ex.id) (\(i + 1) of \(list.count))")
        card.show(payload: payload, position: c.position, inset: CGFloat(c.inset), dropSVG: dropSVG(c))

        let timeout = ex.durationSeconds + Self.graceSeconds
        armDismiss(after: c.expandSteps ? max(timeout, Self.readingSeconds) : timeout)
    }

    /// Character variants live in figures/<character>/; the base files are the sprout.
    private func figureSVG(_ path: String, character: String) -> String? {
        let base = store.resources.appendingPathComponent(path)
        let variant = base.deletingLastPathComponent().appendingPathComponent(character)
            .appendingPathComponent(base.lastPathComponent)
        let url = FileManager.default.fileExists(atPath: variant.path) ? variant : base
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func dropSVG(_ c: Config) -> String? {
        c.entrance == "noodle" ? figureSVG("figures/hang.svg", character: c.character) : nil
    }

    // MARK: Intro

    /// The one-time "hey, I'm Toni" card (or whichever noodle you picked). Shown on first launch and from the menu.
    func showWelcome() {
        guard current == nil else { return }
        var s = store.state()
        s.onboarded = true
        store.save(s)
        let c = store.config()
        let cast = Cast.from(c.character)
        var payload: [String: Any] = ["character": c.character, "focus": c.focus,
                                      "name": cast.name, "fullName": cast.fullName]
        if let svg = figureSVG("figures/wave.svg", character: c.character) { payload["figureSVG"] = svg }
        debug("show intro")
        welcomeShowing = true
        card.show(payload: payload, position: c.position, inset: CGFloat(c.inset), function: "showWelcome",
                  dropSVG: dropSVG(c))
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.readingSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.closeWelcome()
        }
    }

    private func closeWelcome() {
        guard welcomeShowing else { return }
        welcomeShowing = false
        dismissTask?.cancel()
        dismissTask = nil
        card.hide()
    }

    private func armDismiss(after seconds: Double) {
        dismissTask?.cancel()
        debug("auto dismiss in \(Int(seconds))s")
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            debug("auto dismiss fired")
            self?.finish("ignored")
        }
    }

    /// Opening "How to" means someone is reading, so give them a fresh window before auto dismiss.
    private func extendForReading() {
        guard let ex = current else { return }
        let seconds = max(ex.durationSeconds + Self.graceSeconds, Self.readingSeconds)
        debug("how to opened, auto dismiss in \(Int(seconds))s")
        armDismiss(after: seconds)
    }

    private func finish(_ outcome: String) {
        guard let ex = current else { return }
        current = nil
        dismissTask?.cancel()
        dismissTask = nil
        store.log(exercise: ex.id, outcome: outcome)
        if outcome == "snoozed" {
            var s = store.state()
            let snooze = store.config().snoozeMinutes * 60
            s.nextAllowed = max(s.nextAllowed ?? Date(), Date()).addingTimeInterval(snooze)
            store.save(s)
        }
        card.hide()
        onChange?()
    }

    // MARK: Pause

    func pause(until date: Date?) {
        var s = store.state()
        s.pausedUntil = date
        store.save(s)
        if date != nil { delayTask?.cancel(); delayTask = nil }
        onChange?()
    }
}
