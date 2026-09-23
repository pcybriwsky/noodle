import ServiceManagement

/// Open at login, via SMAppService so it shows up under System Settings > Login Items.
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            debug("login item \(on ? "on" : "off") failed: \(error)")
        }
    }
}
