import CoreAudio
import CoreMediaIO
import EventKit

/// "Are you on a call right now?" from the mic and camera. Neither check needs a permission
/// prompt: they only ask whether some app is using the device, never read from it.
enum Calls {
    static func inProgress() -> Bool { micInUse() || cameraInUse() }

    /// Some app is recording audio. On macOS 14.2+ this asks per process, so music playing
    /// through AirPods (one device, input and output) doesn't count as a call.
    static func micInUse() -> Bool {
        if #available(macOS 14.2, *) {
            let processes: [AudioObjectID] = audioArray(AudioObjectID(kAudioObjectSystemObject),
                                                        kAudioHardwarePropertyProcessObjectList)
            return processes.contains { audioUInt32($0, kAudioProcessPropertyIsRunningInput) == 1 }
        }
        let devices: [AudioObjectID] = audioArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        return devices.contains { id in
            hasStreams(id, kAudioObjectPropertyScopeInput) && !hasStreams(id, kAudioObjectPropertyScopeOutput)
                && audioUInt32(id, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
        }
    }

    static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == 0 else { return false }
        return devices.contains { id in
            var a = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0
            var got: UInt32 = 0
            return CMIOObjectGetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == 0
                && running != 0
        }
    }

    // MARK: CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioArray(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func audioUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func hasStreams(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }
}

/// "Are you in a meeting on your calendar right now?" Off until you turn it on in Settings,
/// since it needs calendar access.
@MainActor
final class CalendarWatch {
    private let store = EKEventStore()

    var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, *) { return status == .fullAccess }
        return status.rawValue == 3   // .authorized, deprecated in 14 but the right check before it
    }

    /// Asks macOS for calendar access (a one-time system prompt). Calls back on the main actor.
    func requestAccess(_ done: @escaping @MainActor (Bool) -> Void) {
        Task { @MainActor in
            var granted = false
            do {
                if #available(macOS 14, *) {
                    granted = try await store.requestFullAccessToEvents()
                } else {
                    granted = try await store.requestAccess(to: .event)
                }
            } catch {
                debug("calendar access failed: \(error)")
            }
            done(granted)
        }
    }

    /// A timed event you haven't declined, marked busy, is happening now.
    func busyNow(at now: Date = Date()) -> Bool {
        guard hasAccess else { return false }
        let events = store.events(matching: store.predicateForEvents(
            withStart: now.addingTimeInterval(-60), end: now.addingTimeInterval(60), calendars: nil))
        return events.contains { e in
            guard !e.isAllDay, e.startDate <= now, e.endDate > now,
                  e.availability != .free, e.status != .canceled else { return false }
            let declined = e.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
            return !declined
        }
    }
}
