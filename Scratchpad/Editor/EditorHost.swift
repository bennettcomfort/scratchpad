import AppKit
import SwiftUI

@MainActor
private final class RestoringScrollView: NSScrollView {
    var restoredScrollOffsetY: Double?

    override func layout() {
        super.layout()
        applyRestoredScrollOffsetIfPossible()
    }

    func applyRestoredScrollOffsetIfPossible() {
        guard let restoredScrollOffsetY,
              contentView.bounds.width > 0,
              contentView.bounds.height > 0,
              let documentView else { return }
        if let textView = documentView as? NSTextView,
           let textLayoutManager = textView.textLayoutManager {
            textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        }
        documentView.layoutSubtreeIfNeeded()
        let maximumOffset = max(
            0,
            documentView.bounds.height - contentView.bounds.height
        )
        let clampedOffset = min(max(0, restoredScrollOffsetY), maximumOffset)
        let postsBoundsChanges = contentView.postsBoundsChangedNotifications
        contentView.postsBoundsChangedNotifications = false
        contentView.scroll(to: NSPoint(x: 0, y: clampedOffset))
        reflectScrolledClipView(contentView)
        contentView.postsBoundsChangedNotifications = postsBoundsChanges
        self.restoredScrollOffsetY = nil
    }
}

@MainActor
struct EditorHost: NSViewRepresentable {
    let document: DocumentSession
    var settings = EditorSettingsSnapshot.editorDefaults
    var onEdit: @MainActor (DocumentSession) -> Void = { _ in }
    var onStateChange: @MainActor (DocumentSession) -> Void = { _ in }
    var isEditable = true
    var canEdit: @MainActor () -> Bool = { true }

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(
            document: document,
            onEdit: onEdit,
            onStateChange: onStateChange,
            canEdit: canEdit
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(
            document: document,
            coordinator: context.coordinator,
            settings: settings,
            isEditable: isEditable
        )
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        precondition(context.coordinator.documentID == document.id)
        guard let textView = scrollView.documentView as? ScratchTextView else {
            preconditionFailure("EditorHost lost its ScratchTextView")
        }
        precondition(textView.textLayoutManager != nil)
        precondition(textView.textStorage === document.storage)
        textView.isEditable = isEditable
        textView.commandContext = .defaults(lineEnding: document.lineEnding)
        context.coordinator.apply(settings: settings, to: textView)
    }

    static func dismantleNSView(
        _ scrollView: NSScrollView,
        coordinator: EditorCoordinator
    ) {
        coordinator.detach()
        if let textView = scrollView.documentView as? ScratchTextView {
            textView.delegate = nil
        }
    }

    static func makeScrollView(
        document: DocumentSession,
        coordinator: EditorCoordinator,
        settings: EditorSettingsSnapshot = .editorDefaults,
        isEditable: Bool = true
    ) -> NSScrollView {
        let scrollView = RestoringScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = ScratchTextView(usingTextLayoutManager: true)
        textView.commandContext = .defaults(lineEnding: document.lineEnding)
        guard let contentStorage = textView.textContentStorage else {
            preconditionFailure("TextKit 2 content storage is unavailable")
        }
        guard let textContainer = textView.textContainer else {
            preconditionFailure("TextKit 2 text container is unavailable")
        }

        contentStorage.textStorage = document.storage
        precondition(textView.textLayoutManager != nil)
        precondition(textView.textStorage === document.storage)

        textView.isRichText = false
        textView.isEditable = isEditable
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.frame = scrollView.contentView.bounds
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        coordinator.apply(settings: settings, to: textView)

        scrollView.documentView = textView
        textView.setSelectedRange(document.selection.nsRange)
        scrollView.restoredScrollOffsetY = document.scrollOffsetY
        coordinator.attach(to: scrollView, textView: textView)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyRestoredScrollOffsetIfPossible()
        return scrollView
    }
}
