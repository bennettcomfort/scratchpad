import SwiftUI
import Observation

@MainActor @Observable
final class AppModel {
    // Populated by later tasks (BufferStore in Task 7, session in Task 15).
    func newScratchBuffer() { /* wired in Task 9 */ }
}
