import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    private func createFile(in directory: URL) {
        let name = "untitled-\(Int(Date().timeIntervalSince1970)).md"
        let url = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: "# \(name)\n".data(using: .utf8))
        // Re-index workspace to pick up the new file.
        if let root = model.workspace.rootURL {
            Task {
                model.workspace.setNodes(FileNode.sortFoldersFirst(
                    await FileIndexer().scan(root: root)))
            }
        }
        model.openWorkspaceFile(url)
    }

    var body: some View {
        HStack(spacing: 0) {
            if model.workspace.rootURL != nil {
                VStack(spacing: 0) {
                    HStack {
                        Text(model.workspace.rootName ?? "Workspace")
                            .font(.headline)
                        Spacer()
                        Button { model.workspace.closeWorkspace() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()

                    if model.workspace.isScanning {
                        Spacer()
                        ProgressView().padding()
                        Spacer()
                    } else {
                        List(model.workspace.nodes, children: \.children) { node in
                            HStack {
                                Image(systemName: node.isDirectory ? "folder" : "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(node.name)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !node.isDirectory {
                                    model.openWorkspaceFile(node.url)
                                }
                            }
                            .contextMenu {
                                if !node.isDirectory {
                                    Button("Open") { model.openWorkspaceFile(node.url) }
                                }
                                Button("New File") {
                                    createFile(in: node.isDirectory ? node.url : node.url.deletingLastPathComponent())
                                }
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                                }
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(node.url.path, forType: .string)
                                }
                            }
                        }
                        .listStyle(.sidebar)
                    }
                }
                .frame(minWidth: 200, idealWidth: 240)
                .background(Color(nsColor: .windowBackgroundColor))
                Divider()
            }
        }
    }
}
