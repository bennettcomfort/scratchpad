enum RecoveryStage: String, Equatable, Sendable {
    case baselineContainment

    static let current: Self = .baselineContainment

    var title: String { "Scratchpad Recovery" }

    var explanation: String {
        "The unsafe prototype is contained while its editor core is rebuilt."
    }
}
