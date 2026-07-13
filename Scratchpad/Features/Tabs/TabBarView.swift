import SwiftUI

struct TabBarView: View {
    @Environment(AppModel.self) private var model
    @State private var hoveredID: UUID?

    private var theme: EditorTheme { model.themeManager.current }
    private var buffers: [OpenBuffer] { model.bufferStore.buffers }

    var body: some View {
        if buffers.count >= 2 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(buffers) { buffer in
                        TabItemView(
                            buffer: buffer,
                            isActive: model.bufferStore.activeBufferID == buffer.id,
                            isHovered: hoveredID == buffer.id,
                            onSelect: { model.bufferStore.activeBufferID = buffer.id },
                            onClose: { closeBuffer(buffer) }
                        )
                        .onHover { hovering in hoveredID = hovering ? buffer.id : nil }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 32)
            .background(theme.background)
        }
    }

    private func closeBuffer(_ buffer: OpenBuffer) {
        // File-backed dirty → prompt. Scratch buffers close without prompt.
        if buffer.saveState == .dirty, buffer.fileURL != nil {
            let alert = NSAlert()
            alert.messageText = "Do you want to save changes to \"\(buffer.displayName)\"?"
            alert.informativeText = "Your changes will be lost if you don't save."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Discard")
            alert.beginSheetModal(for: NSApp.keyWindow ?? NSWindow()) { response in
                switch response {
                case .alertFirstButtonReturn: // Save
                    Task { try? await model.fileService.save(buffer: buffer) }
                    fallthrough
                case .alertThirdButtonReturn: // Discard
                    model.bufferStore.close(id: buffer.id)
                    model.sessionService.noteStructuralChange()
                default: break // Cancel
                }
            }
        } else {
            model.bufferStore.close(id: buffer.id)
            model.sessionService.noteStructuralChange()
        }
    }
}

struct TabItemView: View {
    let buffer: OpenBuffer
    let isActive: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(buffer.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
            if buffer.saveState == .dirty {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color(nsColor: .controlBackgroundColor).opacity(1.3) : Color.clear)
        .overlay(alignment: .trailing) {
            if isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
                .padding(.trailing, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .accessibilityLabel("\(buffer.displayName)\(buffer.saveState == .dirty ? " unsaved" : "")")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
