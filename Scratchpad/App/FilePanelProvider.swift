import AppKit
import UniformTypeIdentifiers

@MainActor
protocol FilePanelProviding: AnyObject {
    func selectFileToOpen() async -> URL?
    func selectSaveDestination(suggestedName: String) async -> URL?
}

@MainActor
final class FilePanelProvider: NSObject, FilePanelProviding, NSOpenSavePanelDelegate {
    static let allowedFileExtensions = ["md", "markdown", "mdown", "txt"]

    static func makeOpenPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText]
        return panel
    }

    static func allowsOpenURL(_ url: URL) -> Bool {
        allowedFileExtensions.contains(url.pathExtension.lowercased())
    }

    func selectFileToOpen() async -> URL? {
        let panel = Self.makeOpenPanel()
        panel.delegate = self
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                let selectedURL = response == .OK ? panel.url : nil
                continuation.resume(
                    returning: selectedURL.flatMap { Self.allowsOpenURL($0) ? $0 : nil }
                )
            }
        }
    }

    func selectSaveDestination(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = Self.allowedFileExtensions.compactMap {
            UTType(filenameExtension: $0, conformingTo: .plainText)
        }
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return true
        }
        return Self.allowsOpenURL(url)
    }
}
