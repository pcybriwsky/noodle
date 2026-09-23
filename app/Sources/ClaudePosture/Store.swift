import Foundation

struct Exercise: Codable {
    let id: String
    let name: String
    let instruction: String
    let spec: String
    let durationSeconds: Double
    let figure: String
    let steps: [String]?     // beginner walkthrough shown under "How to"
    let tip: String?
}

struct QuietHours: Codable {
    var enabled = false
    var start = "22:00"
    var end = "07:00"

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = QuietHours()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? d.start
        end = try c.decodeIfPresent(String.self, forKey: .end) ?? d.end
    }

    /// True when `date` falls inside the window. Handles windows that wrap past midnight.
    func contains(_ date: Date) -> Bool {
        guard enabled, let s = Self.minutes(start), let e = Self.minutes(end), s != e else { return false }
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return s < e ? (m >= s && m < e) : (m >= s || m < e)
    }

    static func minutes(_ s: String) -> Int? {
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
        return p[0] * 60 + p[1]
    }
}

struct Config: Codable {
    var delaySeconds: Double = 15
    var cooldownMinutes: Double = 20
    var snoozeMinutes: Double = 10
    var position = "top-right"          // top-right, top-left, bottom-right, bottom-left
    var inset: Double = 16
    var quietHours = QuietHours()
    var enabledExercises: [String]?     // nil means all, in exercises.json order
    var character = "rigatoni"          // rigatoni (Toni) or sprout, picks figures/<character>/<id>.svg
    var expandSteps = false             // open "How to" on every card, for when the moves are new
    var walkIn = true                   // Toni walks to the corner before the card appears
    var holdDuringCalls = true          // no cards while any app is using the mic or camera
    var holdDuringCalendarEvents = false // no cards during busy calendar events (asks for calendar access)
    var focus = Focus.all.rawValue      // neck, hips, all, or "custom" once exercises are picked by hand

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        delaySeconds = try c.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? d.delaySeconds
        cooldownMinutes = try c.decodeIfPresent(Double.self, forKey: .cooldownMinutes) ?? d.cooldownMinutes
        snoozeMinutes = try c.decodeIfPresent(Double.self, forKey: .snoozeMinutes) ?? d.snoozeMinutes
        position = try c.decodeIfPresent(String.self, forKey: .position) ?? d.position
        inset = try c.decodeIfPresent(Double.self, forKey: .inset) ?? d.inset
        quietHours = try c.decodeIfPresent(QuietHours.self, forKey: .quietHours) ?? d.quietHours
        enabledExercises = try c.decodeIfPresent([String].self, forKey: .enabledExercises)
        character = try c.decodeIfPresent(String.self, forKey: .character) ?? d.character
        expandSteps = try c.decodeIfPresent(Bool.self, forKey: .expandSteps) ?? d.expandSteps
        walkIn = try c.decodeIfPresent(Bool.self, forKey: .walkIn) ?? d.walkIn
        holdDuringCalls = try c.decodeIfPresent(Bool.self, forKey: .holdDuringCalls) ?? d.holdDuringCalls
        holdDuringCalendarEvents = try c.decodeIfPresent(Bool.self, forKey: .holdDuringCalendarEvents) ?? d.holdDuringCalendarEvents
        focus = try c.decodeIfPresent(String.self, forKey: .focus) ?? d.focus
    }
}

/// What someone wants to work on. Picks which exercises are in the rotation.
enum Focus: String, CaseIterable {
    case neck, hips, all

    var title: String {
        switch self {
        case .neck: return "Tech neck"
        case .hips: return "Tight hips"
        case .all: return "General stiffness"
        }
    }

    /// Exercise ids for this focus, or nil for all of them.
    var exerciseIDs: Set<String>? {
        switch self {
        case .neck: return ["chin-tuck", "neck-side", "scap", "doorway", "t-ext", "walk"]
        case .hips: return ["hip-flexor", "calf-raise", "walk", "t-ext"]
        case .all: return nil
        }
    }
}

struct State: Codable {
    var rotationIndex = 0
    var lastShown: Date?
    var nextAllowed: Date?      // lastShown + cooldown, pushed out by snooze
    var pausedUntil: Date?
    var onboarded: Bool?        // set once the intro card has been shown
}

/// Owns ~/.claude-posture (or $CLAUDE_POSTURE_HOME): config.json, state.json, log.jsonl.
final class Store {
    let dir: URL
    let resources: URL
    let exercises: [Exercise]
    var configURL: URL { dir.appendingPathComponent("config.json") }
    var stateURL: URL { dir.appendingPathComponent("state.json") }
    var logURL: URL { dir.appendingPathComponent("log.jsonl") }
    private var lastGoodConfig = Config()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f
    }()

    init(dir: URL, resources: URL) {
        self.dir = dir
        self.resources = resources
        let data = (try? Data(contentsOf: resources.appendingPathComponent("exercises.json"))) ?? Data("[]".utf8)
        do { exercises = try JSONDecoder().decode([Exercise].self, from: data) }
        catch { exercises = []; debug("exercises.json unreadable: \(error)") }
        ensureConfig()
    }

    /// Writes a default config.json (all exercises enabled) if there isn't one.
    func ensureConfig() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        var c = Config()
        c.enabledExercises = exercises.map(\.id)
        write(c, to: configURL)
    }

    /// Re-read on every use so edits apply without a restart. A broken file keeps the last good config.
    func config() -> Config {
        do {
            lastGoodConfig = try Self.decoder.decode(Config.self, from: Data(contentsOf: configURL))
        } catch {
            debug("config.json unreadable, using last good config: \(error)")
        }
        return lastGoodConfig
    }

    /// Sets the focus and the exercise rotation that goes with it.
    func apply(focus: Focus) {
        var c = config()
        let all = exercises.map(\.id)
        c.focus = focus.rawValue
        c.enabledExercises = focus.exerciseIDs.map { ids in all.filter(ids.contains) } ?? all
        save(c)
    }

    func enabledExercises(_ c: Config) -> [Exercise] {
        guard let ids = c.enabledExercises else { return exercises }
        return ids.compactMap { id in exercises.first { $0.id == id } }
    }

    func state() -> State {
        (try? Self.decoder.decode(State.self, from: Data(contentsOf: stateURL))) ?? State()
    }

    func save(_ s: State) { write(s, to: stateURL) }
    func save(_ c: Config) { write(c, to: configURL); lastGoodConfig = c }

    func log(exercise: String, outcome: String) {
        let line = "{\"ts\":\(json(Self.stamp.string(from: Date()))),\"exercise\":\(json(exercise)),\"outcome\":\(json(outcome))}\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
        debug("log \(exercise) \(outcome)")
    }

    func doneToday() -> Int {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return 0 }
        let cal = Calendar.current
        return text.split(separator: "\n").reduce(0) { n, line in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["outcome"] as? String == "done",
                  let ts = obj["ts"] as? String, let d = Self.stamp.date(from: ts),
                  cal.isDateInToday(d) else { return n }
            return n + 1
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do { try Self.encoder.encode(value).write(to: url, options: .atomic) }
        catch { debug("write \(url.lastPathComponent) failed: \(error)") }
    }
}

/// JSON literal for a string (quoted and escaped), for building JS calls and log lines.
func json(_ s: String) -> String {
    (try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed))
        .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
}

func debug(_ msg: String) {
    FileHandle.standardError.write(Data("[claude-posture] \(msg)\n".utf8))
}
