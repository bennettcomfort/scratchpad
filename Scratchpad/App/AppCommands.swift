import AppKit
import SwiftUI

struct AppCommands: Commands {
    private let model: ApplicationModel?

    init(model: ApplicationModel? = nil) {
        self.model = model
    }

    @MainActor
    static func operationsEnabled(for model: ApplicationModel?) -> Bool {
        model?.launchState == .ready
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                Task { await model?.requestNewDocument() }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!Self.operationsEnabled(for: model))

            Button("Open…") {
                Task { await model?.requestOpen() }
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(!Self.operationsEnabled(for: model))
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                Task { _ = await model?.save() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!Self.operationsEnabled(for: model))

            Button("Save As…") {
                Task { _ = await model?.saveAs() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!Self.operationsEnabled(for: model))
        }
        CommandMenu("Selection") {
            command("Duplicate Line or Selection", #selector(ScratchTextView.scratchpadDuplicateLine(_:)), "d", [.command, .shift])
            command("Delete Line", #selector(ScratchTextView.scratchpadDeleteLine(_:)), "k", [.control, .shift])
            command("Move Lines Up", #selector(ScratchTextView.scratchpadMoveLinesUp(_:)), .upArrow, [.control, .command])
            command("Move Lines Down", #selector(ScratchTextView.scratchpadMoveLinesDown(_:)), .downArrow, [.control, .command])
            command("Select Line", #selector(ScratchTextView.scratchpadSelectLine(_:)), "l", .command)
            command("Indent", #selector(ScratchTextView.scratchpadIndent(_:)), "]", .command)
            command("Outdent", #selector(ScratchTextView.scratchpadOutdent(_:)), "[", .command)
            command("Insert Line After", #selector(ScratchTextView.scratchpadInsertLineAfter(_:)), .return, .command)
            command("Insert Line Before", #selector(ScratchTextView.scratchpadInsertLineBefore(_:)), .return, [.command, .shift])
        }
        CommandGroup(before: .textEditing) {
            command("Join Lines", #selector(ScratchTextView.scratchpadJoinLines(_:)), "j", .command)
        }
    }

    private func command(
        _ title: String,
        _ action: Selector,
        _ key: KeyEquivalent,
        _ modifiers: EventModifiers
    ) -> some View {
        Button(title) {
            NSApp.sendAction(action, to: nil, from: nil)
        }
        .keyboardShortcut(key, modifiers: modifiers)
    }
}
