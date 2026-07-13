import SwiftUI

struct QuickSwitcherItem: Identifiable {
    let id = UUID()
    let display: String
    let detail: String
    let bufferID: UUID?
    let fileURL: URL?
    let score: Int
}

struct QuickSwitcherView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var items: [QuickSwitcherItem] {
        var results: [QuickSwitcherItem] = []

        // Scratch buffers
        for buffer in model.bufferStore.buffers {
            let display = buffer.fileURL?.lastPathComponent ?? "Scratch — \(buffer.firstLinePreview)"
            let detail = buffer.fileURL != nil ? "Open buffer" : "Scratch buffer"
            let score = query.isEmpty ? 0 : FuzzyMatcher.score(query: query, candidate: display)
            if score >= 0 || query.isEmpty {
                results.append(QuickSwitcherItem(
                    display: display, detail: detail,
                    bufferID: buffer.id, fileURL: buffer.fileURL, score: score))
            }
        }

        // Workspace files (not already open)
        if let root = model.workspace.rootURL {
            let openURLs = Set(model.bufferStore.buffers.compactMap(\.fileURL))
            for node in flatten(model.workspace.nodes) where !openURLs.contains(node.url) {
                let relative = node.url.path.replacingOccurrences(of: root.path + "/", with: "")
                let score = query.isEmpty ? 0 : FuzzyMatcher.score(query: query, candidate: node.name)
                if score >= 0 || query.isEmpty {
                    results.append(QuickSwitcherItem(
                        display: node.name, detail: relative,
                        bufferID: nil, fileURL: node.url, score: score))
                }
            }
        }

        if !query.isEmpty {
            results = results.sorted { $0.score > $1.score }
        }
        return results
    }

    private func flatten(_ nodes: [FileNode]) -> [FileNode] {
        nodes.flatMap { node in
            node.isDirectory ? flatten(node.children ?? []) : [node]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search buffers and files…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onChange(of: query) { _, _ in selectedIndex = 0 }
                    .onSubmit { activateSelected() }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if items.isEmpty {
                Text(query.isEmpty ? "No open buffers" : "No matches")
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                List(Array(items.enumerated()), id: \.element.id, selection: $selectedIndex) { idx, item in
                    HStack {
                        Image(systemName: item.bufferID != nil ? "doc" : "folder")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.display).lineLimit(1)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.bufferID != nil {
                            Text("open")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .tag(idx)
                    .onTapGesture { activate(at: idx) }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 500)
        .frame(maxHeight: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 20)
        .onAppear { isFocused = true }
        .onKeyPress(.downArrow) { selectedIndex = min(selectedIndex + 1, items.count - 1); return .handled }
        .onKeyPress(.upArrow) { selectedIndex = max(selectedIndex - 1, 0); return .handled }
        .onKeyPress(.escape) {
            NotificationCenter.default.post(name: .dismissQuickSwitcher, object: nil)
            return .handled
        }
        .onKeyPress(.return) { activateSelected(); return .handled }
    }

    private func activate(at index: Int) {
        guard index < items.count else { return }
        let item = items[index]
        if let bufferID = item.bufferID {
            model.bufferStore.activeBufferID = bufferID
        } else if let fileURL = item.fileURL {
            model.openWorkspaceFile(fileURL)
        }
        NotificationCenter.default.post(name: .dismissQuickSwitcher, object: nil)
    }

    private func activateSelected() { activate(at: selectedIndex) }
}

extension Notification.Name {
    static let dismissQuickSwitcher = Notification.Name("dismissQuickSwitcher")
}
