import OSLog

enum PerformanceProbe {
    static let subsystem = "com.scratchpad.app"
    static let launchToEditorReady: StaticString = "launchToEditorReady"
    static let metricsCalculation: StaticString = "metricsCalculation"
    static let recoveryWrite: StaticString = "recoveryWrite"

    private static let log = OSLog(
        subsystem: subsystem,
        category: .pointsOfInterest
    )

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
