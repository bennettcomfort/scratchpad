import ServiceManagement

@MainActor
final class LaunchAtLoginService: LaunchAtLoginServicing {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        let wasEnabled = service.status == .enabled

        if enabled != wasEnabled {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        }

        _ = service.status
    }
}
