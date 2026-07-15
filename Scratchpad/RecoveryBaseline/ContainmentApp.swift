import SwiftUI

@main
struct ContainmentApp: App {
    var body: some Scene {
        Window(RecoveryStage.current.title, id: "main") {
            VStack(spacing: 12) {
                Text(RecoveryStage.current.title)
                    .font(.headline)
                Text(RecoveryStage.current.explanation)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(minWidth: 480, minHeight: 320)
        }
        .windowResizability(.contentMinSize)
    }
}
