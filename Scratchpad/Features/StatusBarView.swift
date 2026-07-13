import SwiftUI

struct StatusBarView: View {
    @Environment(AppModel.self) private var model

    private var buffer: OpenBuffer? {
        guard let id = model.bufferStore.activeBufferID else { return nil }
        return model.bufferStore.buffer(id: id)
    }

    private var wordCount: Int {
        guard let text = buffer?.text else { return 0 }
        return text.split(separator: #/\s+/#).count
    }

    private var lineCol: String {
        guard let buf = buffer else { return "0:0" }
        let text = buf.text as NSString
        let pos = min(buf.cursorLocation, text.length)
        let line = text.substring(to: pos).components(separatedBy: "\n").count
        let lastNL = text.range(of: "\n", options: .backwards,
                                range: NSRange(location: 0, length: pos))
        let col = pos - (lastNL.location != NSNotFound ? lastNL.upperBound : 0) + 1
        return "\(line):\(col)"
    }

    private var saveStatus: String {
        switch buffer?.saveState {
        case .clean: return "saved"
        case .dirty: return "unsaved"
        case .conflicted: return "⚠ conflicted"
        case .deletedOnDisk: return "⚠ deleted"
        case .readOnly: return "read only"
        case .scratch: return "scratch"
        case .none: return ""
        }
    }

    private var statusColor: Color {
        switch buffer?.saveState {
        case .dirty: return .yellow
        case .conflicted, .deletedOnDisk: return .red
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            if let name = buffer?.displayName {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("\(wordCount) words")
            Text(lineCol)
            Spacer()
            Text(saveStatus)
                .foregroundStyle(statusColor)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(model.themeManager.current.background.opacity(0.6))
    }
}
