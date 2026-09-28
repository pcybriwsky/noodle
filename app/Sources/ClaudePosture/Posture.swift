import AppKit

/// All scheduling logic. Lives in the single app process, so concurrent Claude sessions
/// just send events here and can never produce two cards.
@MainActor
final class Posture {
    static let waitSeconds: Double = 60        // an untouched card bows out after this
    static let readingSeconds: Double = 180    // How to open, or the intro
    static let setGraceSeconds: Double = 20    // a started set finishes itself; this is only a backstop
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
    private var started = false
    private var welcomeShowing = false
    private var hovering = false
    private var dismissDeadline: Date?
    private var dismissOutcome = "ignored"

    init(store: Store, card: CardController) {
        self.store = store
        self.card = card
        card.onAction = { [weak self] action in
            switch action {
            case "start": self?.startSet()
            case "done": self?.finish("done")
            case "snooze": self?.finish("snoozed")
            case "stop": self?.finish("stopped")
            case "howto": self?.extendForReading()
            case "hover:on": self?.hover(true)
            case "hover:off": self?.hover(false)
            case "welcome-close": self?.closeWelcome()
            case let a where a.hasPrefix("focus:"):
                if let self, let f = Focus(rawValue: String(a.dropFirst(6))) {
                    self.store.apply(focus: f)
                    debug("focus \(f.rawValue)")
                }
            case "welcome-try":   // the intro card turns into a stretch in place
                guard let self, self.welcomeShowing else { return }
                self.welcomeShowing = false
                self.dismissTask?.cancel()
                self.dismissDeadline = nil
                self.showNow()
                if self.current == nil { self.card.hide(reason: "closed") }   // nothing enabled, just close up
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
        started = false
        hovering = false
        var payload: [String: Any] = [
            "id": ex.id, "name": ex.name, "instruction": ex.instruction, "spec": ex.spec,
            "durationSeconds": ex.durationSeconds, "figure": ex.figure, "subtitle": subtitle,
            "index": i + 1, "total": list.count, "doneToday": store.doneToday(),
            "steps": ex.steps ?? [], "tip": ex.tip ?? "", "expand": c.expandSteps,
            "snoozeMinutes": c.snoozeMinutes,
        ]
        if let svg = figureSVG(ex.figure, character: c.character) { payload["figureSVG"] = svg }
        if let svg = figureSVG("figures/wave.svg", character: c.character) { payload["waveSVG"] = svg }
        if let svg = figureSVG("figures/peek.svg", character: c.character) { payload["peekSVG"] = svg }
        debug("show \(ex.id) (\(i + 1) of \(list.count))")
        card.show(payload: payload, position: c.position, inset: CGFloat(c.inset), dropSVG: dropSVG(c))
        armDismiss(after: c.expandSteps ? Self.readingSeconds : Self.waitSeconds)
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
        hovering = false
        card.show(payload: payload, position: c.position, inset: CGFloat(c.inset), function: "showWelcome",
                  dropSVG: dropSVG(c))
        armDismiss(after: Self.readingSeconds, outcome: "intro")
    }

    private func closeWelcome() {
        guard welcomeShowing else { return }
        welcomeShowing = false
        dismissTask?.cancel()
        dismissTask = nil
        dismissDeadline = nil
        card.hide(reason: "closed")
    }

    // MARK: Auto dismiss

    /// Untouched cards bow out on their own. The pointer resting on the card holds them, like a
    /// notification banner, and the clock picks back up (with a few seconds' grace) when it leaves.
    private func armDismiss(after seconds: Double, outcome: String = "ignored") {
        dismissDeadline = Date().addingTimeInterval(seconds)
        dismissOutcome = outcome
        debug("auto dismiss in \(Int(seconds))s")
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let deadline = dismissDeadline else { return }
        if hovering && dismissOutcome != "done" { return debug("auto dismiss held, pointer on the card") }
        let seconds = max(0, deadline.timeIntervalSinceNow)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            debug("auto dismiss fired")
            self.dismissDeadline = nil
            if self.dismissOutcome == "intro" { self.closeWelcome() } else { self.finish(self.dismissOutcome) }
        }
    }

    private func hover(_ on: Bool) {
        guard hovering != on else { return }
        hovering = on
        if !on, let d = dismissDeadline, d.timeIntervalSinceNow < 6 {
            dismissDeadline = Date().addingTimeInterval(6)
        }
        scheduleDismiss()
    }

    /// Start pressed: the page runs the timer and reports done itself. This only catches a page
    /// that never does.
    private func startSet() {
        guard let ex = current, !started else { return }
        started = true
        debug("set started, \(Int(ex.durationSeconds))s")
        armDismiss(after: ex.durationSeconds + Self.setGraceSeconds, outcome: "done")
    }

    /// Opening "How to" means someone is reading, so give them a fresh window before auto dismiss.
    private func extendForReading() {
        guard current != nil, !started else { return }
        debug("how to opened")
        armDismiss(after: Self.readingSeconds)
    }

    private func finish(_ outcome: String) {
        guard let ex = current else { return }
        current = nil
        started = false
        hovering = false
        dismissTask?.cancel()
        dismissTask = nil
        dismissDeadline = nil
        store.log(exercise: ex.id, outcome: outcome)
        if outcome == "snoozed" {
            var s = store.state()
            let snooze = store.config().snoozeMinutes * 60
            s.nextAllowed = max(s.nextAllowed ?? Date(), Date()).addingTimeInterval(snooze)
            store.save(s)
        }
        card.hide(reason: outcome)
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
