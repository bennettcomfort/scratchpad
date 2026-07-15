import AppKit
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
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
