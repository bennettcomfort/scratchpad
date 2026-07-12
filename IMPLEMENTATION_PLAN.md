# Scratchpad v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **For pi agent / DeepSeek / Kimi:** Read `AGENTS.md` in full before every task. Read only your current task's block plus the Global Constraints. Do exactly what the task says — nothing more.

**Goal:** Build Scratchpad — a scratch-first, native macOS Markdown workspace that never loses text.

**Architecture:** SwiftUI shell + AppKit `NSTextView` on TextKit 2. Open-buffer text lives only in `NSTextStorage` (no String bindings). Fixed actor topology: UI/text on `@MainActor`; `SessionWriter`, `BookmarkManager`, `FileIndexer` actors; pure background tokenizer. Hot exit via atomic JSON recovery buffers in Application Support.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, XCTest, XcodeGen, zero runtime dependencies.

**Plan structure:** Milestone 1 (Stages 0–4 → complete daily-usable scratchpad) in full bite-sized detail below. Milestones 2–4 (Stages 5–13) as stage outlines at the end — they are expanded into full task detail after M1 ships.

## Global Constraints (every task implicitly includes these)

```text
- Swift 6, strict concurrency. Zero build warnings on main.
- Minimum deployment: macOS 26.0.
- H1: NEVER access NSTextView.layoutManager (silent TextKit-1 downgrade).
      Use textLayoutManager / textContentStorage only.
- H2: NEVER subclass NSTextStorage.
- H3: No force-unwrap (!), no try!.
- H4: NSTextStorage + all AppKit objects: main actor only.
- H6: ALL file writes (user files AND internal JSON) via AtomicFileWriter.
- H7: ZERO third-party runtime dependencies. Dev tools only: XcodeGen,
      SwiftLint, swift-format, create-dmg.
- H8: No print(). Use os.Logger(subsystem: "com.scratchpad.app", category: ...).
- H9: No network code, no network entitlements.
- Commit per task with conventional commits (feat:/fix:/test:/chore:).
- Build:  xcodegen && xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
- Test:   xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
```

## File Structure (Milestone 1)

```text
Scratchpad/                              # repo root
├── AGENTS.md  SPEC.md  IMPLEMENTATION_PLAN.md  README.md  CHANGELOG.md
├── .gitignore  project.yml  .github/workflows/ci.yml
├── scripts/build_and_notarize.sh
├── Scratchpad/
│   ├── App/ScratchpadApp.swift          # @main, Window scene, AppDelegate adaptor
│   ├── App/AppModel.swift               # root @Observable composition
│   ├── App/AppCommands.swift            # menu commands
│   ├── App/Scratchpad.entitlements  App/Info.plist
│   ├── Domain/ScratchBuffer.swift       # buffer metadata model + SaveState
│   ├── Domain/SessionSnapshot.swift     # Codable session + recovery models
│   ├── Editor/BufferStore.swift         # @MainActor: buffers + their NSTextStorages
│   ├── Editor/EditorTextView.swift      # NSViewRepresentable TK2 wrapper
│   ├── Editor/EditorCoordinator.swift   # delegate: edits → dirty/generation
│   ├── Features/Zen/ZenWindowController.swift
│   ├── Features/Zen/ScreenPlacement.swift   # pure placement math
│   ├── Features/Zen/HotkeyManager.swift     # RegisterEventHotKey wrapper
│   ├── Features/Settings/SettingsView.swift
│   ├── Persistence/ApplicationSupportPaths.swift
│   ├── Persistence/AtomicFileWriter.swift
│   ├── Persistence/JSONStore.swift      # versioned load/save + quarantine
│   ├── Persistence/RecoveryStore.swift  # recovery buffer files
│   ├── Persistence/SessionWriter.swift  # actor: sole session/recovery writer
│   ├── Utilities/Debouncer.swift  Utilities/Hashing.swift  Utilities/Log.swift
│   └── Resources/Assets.xcassets
└── ScratchpadTests/                     # one test file per unit, same names + "Tests"
```

---

# MILESTONE 1 — The Scratchpad (Stages 0–4)

## Stage 0 — Foundation

### Task 1: Repository Readiness

**Context:** The repo already exists at `~/Projects/Active/scratchpad` (remote: `github.com/bennettcomfort/scratchpad`) and already contains the governance docs (`AGENTS.md`, `SPEC.md`, `IMPLEMENTATION_PLAN.md`, `MASTER_CANON.md`) plus the historical planning corpus (`Project Plans/`, `markdown_workspace_release_plan_bundle/`, `ARCHITECTURAL_REVIEW_REPORT.md`, `docs/`). App code is built **in this same repo**. Never read the historical corpus — `AGENTS.md` and `SPEC.md` are your only context docs.

**Files:** Modify: `.gitignore`; Create: `README.md`, `CHANGELOG.md`

**Interfaces:** Produces the repo state every later task assumes. All later paths are relative to this root.

- [ ] **Step 1: Extend .gitignore and add README/CHANGELOG**

```bash
cd ~/Projects/Active/scratchpad
printf '*.xcodeproj\nDerivedData/\nbuild/\n.build/\n' >> .gitignore
printf '# Scratchpad\n\nScratch-first, local-first, native macOS Markdown workspace.\n\n- Product spec: SPEC.md\n- Agent rules: AGENTS.md\n- Plan: IMPLEMENTATION_PLAN.md\n- Full architecture: MASTER_CANON.md\n\n## Build\n\n    brew install xcodegen\n    xcodegen\n    xcodebuild -scheme Scratchpad -destination "platform=macOS" build\n' > README.md
printf '# Changelog\n\n## [Unreleased]\n' > CHANGELOG.md
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "chore: repo readiness — gitignore, README, changelog"
```

**Done when:** `.gitignore` covers Xcode artifacts; README and CHANGELOG exist at root; committed.

---

### Task 2: XcodeGen Project, Entitlements, Minimal App

**Files:** Create: `project.yml`, `Scratchpad/App/Scratchpad.entitlements`, `Scratchpad/App/Info.plist`, `Scratchpad/App/ScratchpadApp.swift`, `Scratchpad/Utilities/Log.swift`, `ScratchpadTests/SmokeTests.swift`

**Interfaces:** Produces the buildable app target `Scratchpad` and test target `ScratchpadTests`; produces `enum Log { static func logger(_ category: String) -> Logger }`.

- [ ] **Step 1: Write `project.yml`**

```yaml
name: Scratchpad
options:
  bundleIdPrefix: com.scratchpad
  deploymentTarget:
    macOS: "26.0"
settings:
  SWIFT_VERSION: "6.0"
  SWIFT_STRICT_CONCURRENCY: complete
  ENABLE_HARDENED_RUNTIME: YES
targets:
  Scratchpad:
    type: application
    platform: macOS
    sources: [Scratchpad]
    settings:
      CODE_SIGN_ENTITLEMENTS: Scratchpad/App/Scratchpad.entitlements
      INFOPLIST_FILE: Scratchpad/App/Info.plist
      PRODUCT_BUNDLE_IDENTIFIER: com.scratchpad.app
  ScratchpadTests:
    type: bundle.unit-test
    platform: macOS
    sources: [ScratchpadTests]
    dependencies:
      - target: Scratchpad
schemes:
  Scratchpad:
    build: { targets: { Scratchpad: all } }
    test: { targets: [ScratchpadTests] }
```

- [ ] **Step 2: Write `Scratchpad/App/Scratchpad.entitlements`** (sandbox ON, user-selected files, NO network keys)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.files.user-selected.read-write</key><true/>
  <key>com.apple.security.files.bookmarks.app-scope</key><true/>
</dict></plist>
```

- [ ] **Step 3: Write `Scratchpad/App/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Scratchpad</string>
  <key>CFBundleDisplayName</key><string>Scratchpad</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
```

- [ ] **Step 4: Write `Scratchpad/App/ScratchpadApp.swift`**

```swift
import SwiftUI

@main
struct ScratchpadApp: App {
    var body: some Scene {
        Window("Scratchpad", id: "main") {
            Text("Scratchpad")
                .frame(minWidth: 480, minHeight: 320)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

- [ ] **Step 5: Write `Scratchpad/Utilities/Log.swift`**

```swift
import os

enum Log {
    static func logger(_ category: String) -> Logger {
        Logger(subsystem: "com.scratchpad.app", category: category)
    }
}
```

- [ ] **Step 6: Write `ScratchpadTests/SmokeTests.swift`**

```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testTruth() { XCTAssertTrue(true) }
}
```

- [ ] **Step 7: Generate, build, test**

```bash
brew install xcodegen 2>/dev/null; xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
```
Expected: BUILD SUCCEEDED, TEST SUCCEEDED, zero warnings.

- [ ] **Step 8: Commit** — `git add -A && git commit -m "chore: XcodeGen project, sandbox entitlements, minimal app shell"`

**Done when:** app builds and launches showing an empty hidden-titlebar window; tests pass; `codesign -d --entitlements - <app>` shows sandbox=true and no network entitlements.

---

### Task 3: CI Workflow

**Files:** Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write workflow**

```yaml
name: CI
on: [push, pull_request]
jobs:
  build-test:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Generate project
        run: xcodegen
      - name: Build
        run: xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
      - name: Test
        run: xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
```

- [ ] **Step 2: Commit** — `git add -A && git commit -m "chore: CI build+test workflow"`

**Done when:** workflow file present; (if a GitHub remote exists, first push runs green — remote setup is the human's call).

---

### Task 4: Notarization Dry-Run Script

**Files:** Create: `scripts/build_and_notarize.sh`

- [ ] **Step 1: Write script** (env-var driven; the HUMAN runs it once now with real credentials to de-risk Stage 13 — agents never handle credentials)

```bash
#!/usr/bin/env bash
# Usage: APPLE_ID=you@x.com TEAM_ID=XXXX APP_PASSWORD=app-specific ./scripts/build_and_notarize.sh
set -euo pipefail
: "${APPLE_ID:?}" "${TEAM_ID:?}" "${APP_PASSWORD:?}"
xcodegen
xcodebuild -scheme Scratchpad -configuration Release -destination 'platform=macOS' \
  -archivePath build/Scratchpad.xcarchive archive
ditto -c -k --keepParent build/Scratchpad.xcarchive/Products/Applications/Scratchpad.app build/Scratchpad.zip
xcrun notarytool submit build/Scratchpad.zip \
  --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
xcrun stapler staple build/Scratchpad.xcarchive/Products/Applications/Scratchpad.app
echo "Notarization dry-run complete."
```

- [ ] **Step 2: `chmod +x scripts/build_and_notarize.sh`; commit** — `git commit -am "chore: notarization script (Stage-0 dry-run)"`

**Done when:** script committed. **Human action item:** run it once with real credentials; any signing problems surface now, not at release week.

---

## Stage 1 — App Shell

### Task 5: ApplicationSupportPaths (TDD)

**Files:** Create: `Scratchpad/Persistence/ApplicationSupportPaths.swift`, `ScratchpadTests/ApplicationSupportPathsTests.swift`

**Interfaces:** Produces `struct ApplicationSupportPaths { init(root: URL); let session: URL; let recovery: URL; let quarantine: URL; let logs: URL; func ensureDirectoriesExist() throws; static func standard() throws -> ApplicationSupportPaths }`. All later persistence tasks consume this.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Scratchpad

final class ApplicationSupportPathsTests: XCTestCase {
    func testDirectoryLayoutAndCreation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-test-\(UUID().uuidString)")
        let paths = ApplicationSupportPaths(root: root)
        XCTAssertEqual(paths.session.lastPathComponent, "session")
        XCTAssertEqual(paths.recovery.lastPathComponent, "recovery")
        XCTAssertEqual(paths.quarantine.lastPathComponent, "quarantine")
        try paths.ensureDirectoriesExist()
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.recovery.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `xcodebuild ... test` → FAIL: "cannot find 'ApplicationSupportPaths'".

- [ ] **Step 3: Implement**

```swift
import Foundation

struct ApplicationSupportPaths: Sendable {
    let root: URL
    var session: URL { root.appendingPathComponent("session") }
    var recovery: URL { root.appendingPathComponent("recovery") }
    var quarantine: URL { root.appendingPathComponent("quarantine") }
    var logs: URL { root.appendingPathComponent("logs") }

    init(root: URL) { self.root = root }

    func ensureDirectoriesExist() throws {
        for dir in [session, recovery, quarantine, logs] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func standard() throws -> ApplicationSupportPaths {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return ApplicationSupportPaths(root: base.appendingPathComponent("Scratchpad"))
    }
}
```

- [ ] **Step 4: Run tests** → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat: application support directory layout"`

---

### Task 6: Hidden-Titlebar Window + Menu Skeleton

**Files:** Create: `Scratchpad/App/AppModel.swift`, `Scratchpad/App/AppCommands.swift`; Modify: `Scratchpad/App/ScratchpadApp.swift`

**Interfaces:** Produces `@MainActor @Observable final class AppModel` (root object; later tasks add properties) and the command hooks `newScratchBuffer()` (stub for now).

- [ ] **Step 1: Write `AppModel.swift`**

```swift
import SwiftUI
import Observation

@MainActor @Observable
final class AppModel {
    // Populated by later tasks (BufferStore in Task 7, session in Task 15).
    func newScratchBuffer() { /* wired in Task 9 */ }
}
```

- [ ] **Step 2: Write `AppCommands.swift`**

```swift
import SwiftUI

struct AppCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Scratch Buffer") { model.newScratchBuffer() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(replacing: .printItem) { }   // frees ⌘P for quick switcher (Stage 8)
    }
}
```

- [ ] **Step 3: Modify `ScratchpadApp.swift`**

```swift
import SwiftUI

@main
struct ScratchpadApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        Window("Scratchpad", id: "main") {
            Text("Scratchpad")
                .frame(minWidth: 480, minHeight: 320)
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(model: model) }
    }
}
```

- [ ] **Step 4: Build + manual verify** — window has no title bar; File menu shows "New Scratch Buffer ⌘N"; no Print item.
- [ ] **Step 5: Commit** — `git commit -am "feat: hidden-titlebar shell, menu skeleton, AppModel root"`

---

## Stage 2 — Editor Core + Scratch Buffers

### Task 7: ScratchBuffer Model + BufferStore (TDD)

**Files:** Create: `Scratchpad/Domain/ScratchBuffer.swift`, `Scratchpad/Editor/BufferStore.swift`, `ScratchpadTests/BufferStoreTests.swift`

**Interfaces:** Produces:
- `enum SaveState: String, Codable { case clean, dirty, conflicted, deletedOnDisk, readOnly, scratch }`
- `@MainActor final class OpenBuffer: Identifiable { let id: UUID; var fileURL: URL?; var displayName: String; var saveState: SaveState; var generation: Int; var cursorLocation: Int; var scrollOffsetY: Double; let storage: NSTextStorage; var text: String { get } // read-only, reads storage; func replaceEntireContents(_ s: String); func noteEdited(); var firstLinePreview: String { get } }`
- `@MainActor @Observable final class BufferStore { private(set) var buffers: [OpenBuffer]; var activeBufferID: UUID?; func createScratchBuffer() -> OpenBuffer; func buffer(id: UUID) -> OpenBuffer?; func close(id: UUID) }`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Scratchpad

@MainActor
final class BufferStoreTests: XCTestCase {
    func testCreateScratchBuffer() {
        let store = BufferStore()
        let b = store.createScratchBuffer()
        XCTAssertEqual(b.saveState, .scratch)
        XCTAssertNil(b.fileURL)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.activeBufferID, b.id)
        XCTAssertEqual(b.generation, 0)
    }

    func testNoteEditedIncrementsGenerationAndDirties() {
        let store = BufferStore()
        let b = store.createScratchBuffer()
        b.noteEdited()
        XCTAssertEqual(b.generation, 1)
        XCTAssertEqual(b.saveState, .scratch) // scratch stays scratch, not .dirty
        b.fileURL = URL(fileURLWithPath: "/tmp/x.md"); b.saveState = .clean
        b.noteEdited()
        XCTAssertEqual(b.saveState, .dirty)
    }

    func testReplaceEntireContentsDoesNotDirty() {
        let store = BufferStore()
        let b = store.createScratchBuffer()
        b.replaceEntireContents("hello\nworld")
        XCTAssertEqual(b.text, "hello\nworld")
        XCTAssertEqual(b.generation, 1)          // restore bumps generation…
        XCTAssertEqual(b.saveState, .scratch)    // …but never marks dirty by itself
        XCTAssertEqual(b.firstLinePreview, "hello")
    }
}
```

- [ ] **Step 2: Run to verify failure** → FAIL: types not found.
- [ ] **Step 3: Implement `ScratchBuffer.swift`**

```swift
import AppKit

enum SaveState: String, Codable, Sendable {
    case clean, dirty, conflicted, deletedOnDisk, readOnly, scratch
}

@MainActor
final class OpenBuffer: Identifiable {
    let id: UUID
    var fileURL: URL?
    var displayName: String
    var saveState: SaveState
    private(set) var generation: Int = 0
    var cursorLocation: Int = 0
    var scrollOffsetY: Double = 0
    let storage: NSTextStorage

    var text: String { storage.string }
    var firstLinePreview: String {
        String(storage.string.prefix(while: { $0 != "\n" }).prefix(60))
    }

    init(id: UUID = UUID(), fileURL: URL? = nil, displayName: String = "Scratch") {
        self.id = id
        self.fileURL = fileURL
        self.displayName = displayName
        self.saveState = fileURL == nil ? .scratch : .clean
        self.storage = NSTextStorage()
    }

    /// The ONLY sanctioned whole-text write path (open / reload / restore).
    func replaceEntireContents(_ s: String) {
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: s)
        generation += 1
    }

    /// Called by the editor coordinator on every user edit.
    func noteEdited() {
        generation += 1
        if saveState == .clean { saveState = .dirty }
    }
}
```

- [ ] **Step 4: Implement `BufferStore.swift`**

```swift
import Foundation
import Observation

@MainActor @Observable
final class BufferStore {
    private(set) var buffers: [OpenBuffer] = []
    var activeBufferID: UUID?

    @discardableResult
    func createScratchBuffer() -> OpenBuffer {
        let b = OpenBuffer()
        buffers.append(b)
        activeBufferID = b.id
        return b
    }

    func buffer(id: UUID) -> OpenBuffer? { buffers.first { $0.id == id } }

    func close(id: UUID) {
        buffers.removeAll { $0.id == id }
        if activeBufferID == id { activeBufferID = buffers.last?.id }
    }
}
```

- [ ] **Step 5: Run tests** → PASS.
- [ ] **Step 6: Commit** — `git commit -am "feat: OpenBuffer + BufferStore with generation counter and save states"`

---

### Task 8: TextKit-2 Editor Bridge

**Files:** Create: `Scratchpad/Editor/EditorTextView.swift`, `Scratchpad/Editor/EditorCoordinator.swift`

**Interfaces:** Produces `struct EditorTextView: NSViewRepresentable { let buffer: OpenBuffer }` — hosts an `NSTextView` that renders/edits `buffer.storage` directly. Consumes `OpenBuffer` from Task 7.

```text
CONSTRAINT REMINDERS FOR THIS TASK (verbatim from AGENTS.md):
H1. NEVER access NSTextView.layoutManager — silent TextKit-1 downgrade.
H2. NEVER subclass NSTextStorage.
H4. NSTextStorage and all AppKit objects: main actor only.
Text ownership: the view edits buffer.storage DIRECTLY — no String copies,
no updateNSView text pushes. updateNSView must NOT write text.
```

- [ ] **Step 1: Write `EditorCoordinator.swift`**

```swift
import AppKit

@MainActor
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    let buffer: OpenBuffer
    init(buffer: OpenBuffer) { self.buffer = buffer }

    func textDidChange(_ notification: Notification) {
        buffer.noteEdited()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        buffer.cursorLocation = tv.selectedRange().location
    }
}
```

- [ ] **Step 2: Write `EditorTextView.swift`**

```swift
import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    let buffer: OpenBuffer

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator(buffer: buffer) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 2 stack, explicitly. (H1: never touch .layoutManager.)
        let textView = NSTextView(usingTextLayoutManager: true)
        assert(textView.textLayoutManager != nil, "TextKit 2 must be active")

        // Bind the view to the buffer's storage — single source of truth.
        if let contentStorage = textView.textContentStorage {
            contentStorage.textStorage = buffer.storage
        }
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true

        // Restore cursor if valid.
        let loc = min(buffer.cursorLocation, buffer.storage.length)
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Intentionally empty for text: storage IS the source of truth.
        // Theme/font updates arrive here in Stage 10.
    }
}
```

- [ ] **Step 3: Build** → zero warnings. (No unit test — AppKit view; verified via Task 9 smoke.)
- [ ] **Step 4: Commit** — `git commit -am "feat: TextKit-2 editor bridge bound directly to buffer storage"`

---

### Task 9: Launch Into a Scratch Buffer

**Files:** Create: `Scratchpad/App/MainWindowView.swift`; Modify: `Scratchpad/App/ScratchpadApp.swift`, `Scratchpad/App/AppModel.swift`

**Interfaces:** `AppModel` gains `let bufferStore = BufferStore()`; `newScratchBuffer()` now calls `bufferStore.createScratchBuffer()`. `MainWindowView` shows the active buffer's editor.

- [ ] **Step 1: Write `MainWindowView.swift`**

```swift
import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let id = model.bufferStore.activeBufferID,
               let buffer = model.bufferStore.buffer(id: id) {
                EditorTextView(buffer: buffer)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            if model.bufferStore.buffers.isEmpty {
                model.bufferStore.createScratchBuffer()
            }
        }
    }
}
```

- [ ] **Step 2: Modify `AppModel.swift`**

```swift
import SwiftUI
import Observation

@MainActor @Observable
final class AppModel {
    let bufferStore = BufferStore()
    func newScratchBuffer() { bufferStore.createScratchBuffer() }
}
```

- [ ] **Step 3: Modify `ScratchpadApp.swift`** — replace `Text("Scratchpad")…` with `MainWindowView().environment(model)`.
- [ ] **Step 4: Build + manual smoke** — launch: cursor blinking in an empty editor immediately; type; ⌘Z undoes; ⌘F opens find bar; ⌘N focuses a fresh buffer.
- [ ] **Step 5: Commit** — `git commit -am "feat: launch directly into a scratch buffer"`

**Done when:** app launches straight to typeable editor — no dialogs, no welcome UI.

---

## Stage 3 — Hot Exit

### Task 10: AtomicFileWriter (TDD)

**Files:** Create: `Scratchpad/Persistence/AtomicFileWriter.swift`, `ScratchpadTests/AtomicFileWriterTests.swift`

**Interfaces:** Produces `enum AtomicFileWriter { static func write(_ data: Data, to url: URL) throws }` — temp file in the destination's directory, then atomic replace. ALL later writes consume this (H6).

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import Scratchpad

final class AtomicFileWriterTests: XCTestCase {
    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testWritesNewFile() throws {
        let url = try tempDir().appendingPathComponent("a.json")
        try AtomicFileWriter.write(Data("hello".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
    }

    func testReplacesExistingFileCompletely() throws {
        let url = try tempDir().appendingPathComponent("a.json")
        try AtomicFileWriter.write(Data("first-longer-content".utf8), to: url)
        try AtomicFileWriter.write(Data("second".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second")
    }

    func testLeavesNoTempFilesBehind() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("a.json")
        try AtomicFileWriter.write(Data("x".utf8), to: url)
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(contents, ["a.json"])
    }
}
```

- [ ] **Step 2: Run** → FAIL (type not found).
- [ ] **Step 3: Implement**

```swift
import Foundation

enum AtomicFileWriter {
    /// I3: temp file in the destination directory, then atomic replace.
    static func write(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: [])
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }
}
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -am "feat: atomic file writer (I3)"`

---

### Task 11: JSONStore with Versioning + Quarantine (TDD)

**Files:** Create: `Scratchpad/Persistence/JSONStore.swift`, `ScratchpadTests/JSONStoreTests.swift`

**Interfaces:** Produces `struct JSONStore { init(quarantineDirectory: URL); func save<T: Encodable>(_ value: T, to url: URL) throws; func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T?; }` — `load` returns nil for missing file; on decode failure it moves the file into quarantine (I7) and returns nil, never throws for corruption.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import Scratchpad

final class JSONStoreTests: XCTestCase {
    struct Doc: Codable, Equatable { var schemaVersion = 1; var body: String }

    func makeDirs() throws -> (dir: URL, quarantine: URL) {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-\(UUID().uuidString)")
        let q = d.appendingPathComponent("quarantine")
        try FileManager.default.createDirectory(at: q, withIntermediateDirectories: true)
        return (d, q)
    }

    func testRoundTrip() throws {
        let (dir, q) = try makeDirs()
        let store = JSONStore(quarantineDirectory: q)
        let url = dir.appendingPathComponent("s.json")
        try store.save(Doc(body: "hi"), to: url)
        XCTAssertEqual(try store.load(Doc.self, from: url), Doc(body: "hi"))
    }

    func testMissingFileReturnsNil() throws {
        let (dir, q) = try makeDirs()
        let store = JSONStore(quarantineDirectory: q)
        XCTAssertNil(try store.load(Doc.self, from: dir.appendingPathComponent("nope.json")))
    }

    func testCorruptFileIsQuarantinedNotDeleted() throws {
        let (dir, q) = try makeDirs()
        let store = JSONStore(quarantineDirectory: q)
        let url = dir.appendingPathComponent("bad.json")
        try Data("{not json!".utf8).write(to: url)
        XCTAssertNil(try store.load(Doc.self, from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: q.path)
        XCTAssertEqual(quarantined.count, 1)   // I7: preserved, not deleted
    }
}
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**

```swift
import Foundation

struct JSONStore: Sendable {
    let quarantineDirectory: URL
    private let log = Log.logger("json-store")

    func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFileWriter.write(try encoder.encode(value), to: url)
    }

    func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // I7: quarantine, never delete.
            let stamp = ISO8601DateFormatter().string(from: Date())
            let dest = quarantineDirectory
                .appendingPathComponent("\(stamp)-\(url.lastPathComponent)")
            try? FileManager.default.moveItem(at: url, to: dest)
            log.error("Quarantined corrupt file \(url.lastPathComponent, privacy: .public)")
            return nil
        }
    }
}
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -am "feat: versioned JSON store with quarantine (I7)"`

---

### Task 12: Session Models + RecoveryStore (TDD)

**Files:** Create: `Scratchpad/Domain/SessionSnapshot.swift`, `Scratchpad/Persistence/RecoveryStore.swift`, `ScratchpadTests/RecoveryStoreTests.swift`

**Interfaces:** Produces:

```swift
struct RecoveryBuffer: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let bufferID: UUID
    let filePath: String?        // nil for scratch buffers
    let unsavedText: String
    let savedAt: Date
}
struct BufferRecord: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let bufferID: UUID
    let filePath: String?
    let displayName: String
    let saveStateRaw: String
    let cursorLocation: Int
    let scrollOffsetY: Double
}
struct SessionSnapshot: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var buffers: [BufferRecord]
    var activeBufferID: UUID?
    var savedAt: Date
}
struct RecoveryStore: Sendable {
    init(directory: URL, store: JSONStore)
    func write(_ buffer: RecoveryBuffer) throws
    func loadAll() throws -> [RecoveryBuffer]
    func delete(bufferID: UUID) throws
}
```

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import Scratchpad

final class RecoveryStoreTests: XCTestCase {
    func makeStore() throws -> RecoveryStore {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-\(UUID().uuidString)")
        let q = d.appendingPathComponent("q")
        try FileManager.default.createDirectory(at: q, withIntermediateDirectories: true)
        return RecoveryStore(directory: d, store: JSONStore(quarantineDirectory: q))
    }

    func testWriteLoadDeleteLifecycle() throws {
        let store = try makeStore()
        let id = UUID()
        let rb = RecoveryBuffer(bufferID: id, filePath: nil,
                                unsavedText: "draft", savedAt: Date())
        try store.write(rb)
        XCTAssertEqual(try store.loadAll().map(\.bufferID), [id])
        XCTAssertEqual(try store.loadAll().first?.unsavedText, "draft")
        try store.delete(bufferID: id)
        XCTAssertTrue(try store.loadAll().isEmpty)
    }

    func testOverwriteKeepsOneFilePerBuffer() throws {
        let store = try makeStore()
        let id = UUID()
        try store.write(RecoveryBuffer(bufferID: id, filePath: nil, unsavedText: "v1", savedAt: Date()))
        try store.write(RecoveryBuffer(bufferID: id, filePath: nil, unsavedText: "v2", savedAt: Date()))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.unsavedText, "v2")
    }
}
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (`SessionSnapshot.swift` = the structs above verbatim; `RecoveryStore.swift`:)

```swift
import Foundation

struct RecoveryStore: Sendable {
    let directory: URL
    let store: JSONStore

    private func url(for bufferID: UUID) -> URL {
        directory.appendingPathComponent("buffer-\(bufferID.uuidString).json")
    }

    func write(_ buffer: RecoveryBuffer) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try store.save(buffer, to: url(for: buffer.bufferID))
    }

    func loadAll() throws -> [RecoveryBuffer] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return names.filter { $0.hasPrefix("buffer-") && $0.hasSuffix(".json") }
            .compactMap { try? store.load(RecoveryBuffer.self,
                                          from: directory.appendingPathComponent($0)) }
    }

    func delete(bufferID: UUID) throws {
        let u = url(for: bufferID)
        if FileManager.default.fileExists(atPath: u.path) {
            try FileManager.default.removeItem(at: u)
        }
    }
}
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -am "feat: session models + recovery buffer store"`

---

### Task 13: Debouncer (TDD)

**Files:** Create: `Scratchpad/Utilities/Debouncer.swift`, `ScratchpadTests/DebouncerTests.swift`

**Interfaces:** Produces `@MainActor final class Debouncer { init(delay: Duration); func schedule(_ action: @escaping @MainActor () -> Void) }` — repeated `schedule` calls coalesce; only the last action fires after `delay` of quiet.

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import Scratchpad

@MainActor
final class DebouncerTests: XCTestCase {
    func testCoalescesRapidCalls() async throws {
        let d = Debouncer(delay: .milliseconds(50))
        var fired: [Int] = []
        d.schedule { fired.append(1) }
        d.schedule { fired.append(2) }
        d.schedule { fired.append(3) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fired, [3])
    }
}
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**

```swift
import Foundation

@MainActor
final class Debouncer {
    private let delay: Duration
    private var task: Task<Void, Never>?

    init(delay: Duration) { self.delay = delay }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -am "feat: main-actor debouncer"`

---

### Task 14: SessionWriter Actor + SessionService Wiring

**Files:** Create: `Scratchpad/Persistence/SessionWriter.swift`, `Scratchpad/App/SessionService.swift`; Modify: `Scratchpad/App/AppModel.swift`, `Scratchpad/Editor/EditorCoordinator.swift`

**Interfaces:** Produces:
- `actor SessionWriter { init(paths: ApplicationSupportPaths); func writeSession(_ s: SessionSnapshot); func writeRecovery(_ r: RecoveryBuffer); func deleteRecovery(bufferID: UUID); func loadSession() -> SessionSnapshot?; func loadRecoveries() -> [RecoveryBuffer] }` (sole writer of session/recovery files; swallows-and-logs write errors so UI never blocks).
- `@MainActor final class SessionService { init(bufferStore: BufferStore, writer: SessionWriter); func noteBufferEdited(_ b: OpenBuffer); func noteStructuralChange(); func restoreOnLaunch() async }`

Consumes: Tasks 5, 7, 11–13.

- [ ] **Step 1: Implement `SessionWriter.swift`**

```swift
import Foundation

actor SessionWriter {
    private let paths: ApplicationSupportPaths
    private let json: JSONStore
    private let recovery: RecoveryStore
    private let log = Log.logger("session-writer")

    init(paths: ApplicationSupportPaths) {
        self.paths = paths
        self.json = JSONStore(quarantineDirectory: paths.quarantine)
        self.recovery = RecoveryStore(directory: paths.recovery, store: json)
        try? paths.ensureDirectoriesExist()
    }

    private var sessionURL: URL { paths.session.appendingPathComponent("latest-session.json") }

    func writeSession(_ s: SessionSnapshot) {
        do { try json.save(s, to: sessionURL) }
        catch { log.error("session write failed: \(error, privacy: .public)") }
    }
    func writeRecovery(_ r: RecoveryBuffer) {
        do { try recovery.write(r) }
        catch { log.error("recovery write failed: \(error, privacy: .public)") }
    }
    func deleteRecovery(bufferID: UUID) {
        do { try recovery.delete(bufferID: bufferID) }
        catch { log.error("recovery delete failed: \(error, privacy: .public)") }
    }
    func loadSession() -> SessionSnapshot? {
        (try? json.load(SessionSnapshot.self, from: sessionURL)) ?? nil
    }
    func loadRecoveries() -> [RecoveryBuffer] { (try? recovery.loadAll()) ?? [] }
}
```

- [ ] **Step 2: Implement `SessionService.swift`**

```swift
import Foundation

@MainActor
final class SessionService {
    private let bufferStore: BufferStore
    private let writer: SessionWriter
    private let recoveryDebouncer = Debouncer(delay: .seconds(2))

    init(bufferStore: BufferStore, writer: SessionWriter) {
        self.bufferStore = bufferStore
        self.writer = writer
    }

    private func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            buffers: bufferStore.buffers.map {
                BufferRecord(bufferID: $0.id, filePath: $0.fileURL?.path,
                             displayName: $0.displayName, saveStateRaw: $0.saveState.rawValue,
                             cursorLocation: $0.cursorLocation, scrollOffsetY: $0.scrollOffsetY)
            },
            activeBufferID: bufferStore.activeBufferID,
            savedAt: Date())
    }

    /// Debounced 1–3 s after edits while dirty (SPEC §8).
    func noteBufferEdited(_ b: OpenBuffer) {
        let rb = RecoveryBuffer(bufferID: b.id, filePath: b.fileURL?.path,
                                unsavedText: b.text, savedAt: Date())
        recoveryDebouncer.schedule { [writer] in
            Task { await writer.writeRecovery(rb) }
        }
    }

    /// Buffer open/close/switch, window changes, terminate.
    func noteStructuralChange() {
        let s = snapshot()
        Task { await writer.writeSession(s) }
    }

    /// Silent restore — NO prompt, ever (SPEC §8).
    func restoreOnLaunch() async {
        let session = await writer.loadSession()
        let recoveries = Dictionary(uniqueKeysWithValues:
            await writer.loadRecoveries().map { ($0.bufferID, $0) })

        guard let session, !session.buffers.isEmpty else {
            if bufferStore.buffers.isEmpty { bufferStore.createScratchBuffer() }
            return
        }
        for record in session.buffers {
            let b = OpenBuffer(id: record.bufferID,
                               fileURL: record.filePath.map { URL(fileURLWithPath: $0) },
                               displayName: record.displayName)
            if let rec = recoveries[record.bufferID] {
                b.replaceEntireContents(rec.unsavedText)
                b.saveState = SaveState(rawValue: record.saveStateRaw) ?? .scratch
            }
            b.cursorLocation = record.cursorLocation
            b.scrollOffsetY = record.scrollOffsetY
            bufferStore.adopt(b)   // added in Step 3
        }
        bufferStore.activeBufferID = session.activeBufferID ?? bufferStore.buffers.last?.id
        if bufferStore.buffers.isEmpty { bufferStore.createScratchBuffer() }
    }
}
```

- [ ] **Step 3: Add `adopt(_:)` to `BufferStore`**

```swift
    /// Restore path: insert a reconstructed buffer without changing activeBufferID.
    func adopt(_ buffer: OpenBuffer) { buffers.append(buffer) }
```

- [ ] **Step 4: Wire `AppModel`** — add:

```swift
    let sessionService: SessionService
    private let sessionWriter: SessionWriter

    init() {
        let paths = (try? ApplicationSupportPaths.standard())
            ?? ApplicationSupportPaths(root: FileManager.default.temporaryDirectory
                .appendingPathComponent("Scratchpad-fallback"))
        let writer = SessionWriter(paths: paths)
        self.sessionWriter = writer
        self.sessionService = SessionService(bufferStore: bufferStore, writer: writer)
    }
```

(Keep `bufferStore` initialized before use: declare `let bufferStore = BufferStore()` above the init.)

- [ ] **Step 5: Route edits** — in `EditorCoordinator.textDidChange`, after `buffer.noteEdited()`, call the session service. Give the coordinator a closure: `var onEdit: ((OpenBuffer) -> Void)?` set from `MainWindowView` (`coordinator.onEdit = { model.sessionService.noteBufferEdited($0) }` — pass through `EditorTextView(buffer:onEdit:)`). Call `model.sessionService.noteStructuralChange()` in `BufferStore.createScratchBuffer/close` call sites (in `AppModel.newScratchBuffer` and window lifecycle).
- [ ] **Step 6: Restore on launch** — in `MainWindowView.onAppear`, replace the create-if-empty logic with `Task { await model.sessionService.restoreOnLaunch() }`.
- [ ] **Step 7: `didCloseCleanly` flag (diagnostics only — restore behavior is identical either way).** In `AppModel.init`, read then immediately clear: `let closedCleanly = UserDefaults.standard.bool(forKey: "didCloseCleanly"); UserDefaults.standard.set(false, forKey: "didCloseCleanly"); if !closedCleanly { Log.logger("session").notice("previous run did not close cleanly") }`. Add an `NSApplicationDelegateAdaptor` AppDelegate with `applicationWillTerminate` setting the flag true and calling `model.sessionService.noteStructuralChange()`.
- [ ] **Step 8: Build + tests** → all green.
- [ ] **Step 9: Commit** — `git commit -am "feat: hot exit — debounced recovery snapshots + silent session restore"`

---

### Task 15: Hot-Exit Verification (manual gate — do not skip)

**Files:** none (verification only)

- [ ] **Step 1: Clean-quit restore** — launch, type "alpha beta" into the scratch buffer, wait 3 s (debounce), ⌘Q, relaunch. Expected: text restored, cursor position restored, no dialogs.
- [ ] **Step 2: Kill-9 restore** — type "gamma delta", wait 3 s, then `pkill -9 Scratchpad`. Relaunch. Expected: text restored.
- [ ] **Step 3: Corrupt-session resilience** — quit; corrupt the file: `echo '{bad' > ~/Library/Application\ Support/Scratchpad/session/latest-session.json`; relaunch. Expected: app opens cleanly to a fresh scratch buffer; corrupt file present in `quarantine/`.
- [ ] **Step 4: Commit checklist note** — `git commit --allow-empty -m "test: manual hot-exit gate passed (quit/kill-9/quarantine)"`

**Done when:** all three scenarios pass. If any fails, fix before proceeding — this is the product's core promise.

---

## Stage 4 — Zen Summon

### Task 16: ScreenPlacement (TDD, pure logic)

**Files:** Create: `Scratchpad/Features/Zen/ScreenPlacement.swift`, `ScratchpadTests/ScreenPlacementTests.swift`

**Interfaces:** Produces `enum ScreenPlacement { static func targetFrame(mouse: CGPoint, screens: [CGRect], windowSize: CGSize) -> CGRect }` — picks the screen rect containing the mouse (falls back to first), returns a centered window frame. Task 17 consumes this.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import Scratchpad

final class ScreenPlacementTests: XCTestCase {
    let screenA = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let screenB = CGRect(x: 1600, y: 0, width: 1200, height: 800)

    func testCentersOnScreenContainingMouse() {
        let frame = ScreenPlacement.targetFrame(
            mouse: CGPoint(x: 2000, y: 300),
            screens: [screenA, screenB],
            windowSize: CGSize(width: 640, height: 400))
        XCTAssertEqual(frame.midX, screenB.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, screenB.midY, accuracy: 0.5)
        XCTAssertEqual(frame.size, CGSize(width: 640, height: 400))
    }

    func testFallsBackToFirstScreenWhenMouseOutsideAll() {
        let frame = ScreenPlacement.targetFrame(
            mouse: CGPoint(x: -5000, y: -5000),
            screens: [screenA, screenB],
            windowSize: CGSize(width: 640, height: 400))
        XCTAssertEqual(frame.midX, screenA.midX, accuracy: 0.5)
    }
}
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**

```swift
import CoreGraphics

enum ScreenPlacement {
    static func targetFrame(mouse: CGPoint, screens: [CGRect], windowSize: CGSize) -> CGRect {
        guard let screen = screens.first(where: { $0.contains(mouse) }) ?? screens.first
        else { return CGRect(origin: .zero, size: windowSize) }
        return CGRect(x: screen.midX - windowSize.width / 2,
                      y: screen.midY - windowSize.height / 2,
                      width: windowSize.width, height: windowSize.height)
    }
}
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -am "feat: zen window screen placement math"`

---

### Task 17: HotkeyManager (Carbon RegisterEventHotKey)

**Files:** Create: `Scratchpad/Features/Zen/HotkeyManager.swift`

**Interfaces:** Produces `@MainActor final class HotkeyManager { init(); func register(onPress: @escaping @MainActor () -> Void); func unregister() }` — registers `⌃⌥Space` (Carbon: keyCode 49, modifiers `controlKey | optionKey`). Sandbox-safe; NO accessibility permission; NEVER use CGEvent taps.

- [ ] **Step 1: Implement**

```swift
import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPress: (@MainActor () -> Void)?
    private let log = Log.logger("hotkey")

    func register(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in manager.onPress?() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x5350_4144), id: 1) // 'SPAD'
        let status = RegisterEventHotKey(UInt32(kVK_Space),
                                         UInt32(controlKey | optionKey),
                                         hotKeyID, GetApplicationEventTarget(),
                                         0, &hotKeyRef)
        if status != noErr { log.error("hotkey registration failed: \(status)") }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil; handlerRef = nil
    }
}
```

- [ ] **Step 2: Build** → zero warnings. (Behavior verified in Task 19 smoke.)
- [ ] **Step 3: Commit** — `git commit -am "feat: global hotkey manager (⌃⌥Space via RegisterEventHotKey)"`

---

### Task 18: ZenWindowController

**Files:** Create: `Scratchpad/Features/Zen/ZenWindowController.swift`

**Interfaces:** Produces `@MainActor final class ZenWindowController { init(model: AppModel); func summon(); func dismiss(copyToClipboard: Bool) }`. Consumes `ScreenPlacement` (T16), `BufferStore`/`OpenBuffer` (T7), `EditorTextView` (T8), `SessionService` (T14).

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI

@MainActor
final class ZenWindowController {
    private let model: AppModel
    private var window: NSWindow?
    private var currentBuffer: OpenBuffer?
    static let defaultSize = CGSize(width: 640, height: 400)

    init(model: AppModel) { self.model = model }

    func summon() {
        let buffer = model.bufferStore.createScratchBuffer()
        currentBuffer = buffer
        model.sessionService.noteStructuralChange()

        let win = window ?? makeWindow()
        window = win

        // Place on the screen containing the mouse (SPEC §9).
        let size = win.frame.size == .zero ? Self.defaultSize : win.frame.size
        let frame = ScreenPlacement.targetFrame(
            mouse: NSEvent.mouseLocation,
            screens: NSScreen.screens.map(\.frame),
            windowSize: size)

        win.contentView = NSHostingView(rootView:
            ZenContainerView(buffer: buffer, controller: self)
                .environment(model))
        win.setFrame(frame, display: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
        win.makeFirstResponder(win.contentView)
    }

    func dismiss(copyToClipboard: Bool) {
        if copyToClipboard, let text = currentBuffer?.text, !text.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
        window?.orderOut(nil)
        model.sessionService.noteStructuralChange()
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable],
            backing: .buffered, defer: false)
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.setFrameAutosaveName("ZenWindow")   // remembers user resize
        return win
    }
}

struct ZenContainerView: View {
    let buffer: OpenBuffer
    let controller: ZenWindowController
    @Environment(AppModel.self) private var model

    var body: some View {
        EditorTextView(buffer: buffer,
                       onEdit: { model.sessionService.noteBufferEdited($0) })
            .background(KeyCatcher(
                onCommandReturn: { controller.dismiss(copyToClipboard: true) },
                onEscape: {
                    let alsoCopy = UserDefaults.standard.bool(forKey: "escAlsoCopies")
                    controller.dismiss(copyToClipboard: alsoCopy)
                }))
    }
}

/// Invisible NSView that intercepts ⌘⏎ and Esc before the text view.
struct KeyCatcher: NSViewRepresentable {
    let onCommandReturn: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = KeyCatcherView()
        v.onCommandReturn = onCommandReturn
        v.onEscape = onEscape
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyCatcherView: NSView {
        var onCommandReturn: (() -> Void)?
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { false }
        override func viewDidMoveToWindow() {
            // Local monitor scoped to this window's lifetime.
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                if event.keyCode == 36, event.modifierFlags.contains(.command) { // ⌘⏎
                    self.onCommandReturn?(); return nil
                }
                if event.keyCode == 53 {                                         // Esc
                    self.onEscape?(); return nil
                }
                return event
            }
        }
    }
}
```

- [ ] **Step 2: Update `EditorTextView`** to accept the `onEdit` closure if Task 14 hasn't already: `init(buffer: OpenBuffer, onEdit: ((OpenBuffer) -> Void)? = nil)`, passed to the coordinator.
- [ ] **Step 3: Build** → zero warnings. **Step 4: Commit** — `git commit -am "feat: zen scratch window with ⌘⏎ copy-exit and Esc dismiss"`

---

### Task 19: Wire Hotkey → Zen + Manual Smoke

**Files:** Modify: `Scratchpad/App/AppModel.swift`

- [ ] **Step 1: Wire in `AppModel`** — add:

```swift
    private(set) lazy var zenController = ZenWindowController(model: self)
    private let hotkeyManager = HotkeyManager()

    func startGlobalHotkey() {
        hotkeyManager.register { [weak self] in self?.zenController.summon() }
    }
```

Call `model.startGlobalHotkey()` from `MainWindowView.onAppear` (after restore).

- [ ] **Step 2: Manual smoke (all must pass):**
  - App running in background; from another app press `⌃⌥Space` → zen window appears centered on the screen the mouse is on, cursor ready, typeable instantly.
  - Type "test draft", press `⌘⏎` → window vanishes; ⌘V elsewhere pastes "test draft".
  - Press hotkey on the *other* monitor (if available) → window appears there.
  - Press `Esc` on a new zen buffer → dismisses, clipboard untouched.
  - Quit and relaunch → zen-created buffers restored in main window.
- [ ] **Step 3: Commit** — `git commit -am "feat: global hotkey summons zen window"`

---

### Task 20: Settings Pane (launch-at-login + Esc-copies)

**Files:** Create: `Scratchpad/Features/Settings/SettingsView.swift`; Modify: `Scratchpad/App/ScratchpadApp.swift`

- [ ] **Step 1: Implement `SettingsView.swift`**

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("escAlsoCopies") private var escAlsoCopies = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enable in
                    do {
                        if enable { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        Log.logger("settings").error("login item: \(error, privacy: .public)")
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Toggle("Esc also copies zen buffer to clipboard", isOn: $escAlsoCopies)
        }
        .padding(20)
        .frame(width: 420)
    }
}
```

- [ ] **Step 2: Add scene** — in `ScratchpadApp.body`, add `Settings { SettingsView() }`.
- [ ] **Step 3: Manual verify** — `⌘,` opens settings; toggles persist across relaunch; with Esc-copies ON, Esc in zen window copies.
- [ ] **Step 4: Commit** — `git commit -am "feat: settings — launch at login, Esc-copies toggle"`

---

### Task 21: Milestone 1 Acceptance Gate

**Files:** none (verification only)

- [ ] **Step 1: Full test suite green** — `xcodebuild ... test` → all pass, zero warnings.
- [ ] **Step 2: Perf checks** — cold launch → typeable feels instant (< 400 ms; measure with `time` to first keystroke acceptance or Instruments if in doubt); hotkey → typeable < 150 ms (perceptually instant).
- [ ] **Step 3: Re-run Task 15's hot-exit gate** end-to-end including a zen buffer.
- [ ] **Step 4: Tag** — `git tag v0.4.0-scratchpad && git commit --allow-empty -m "chore: Milestone 1 gate passed"`
- [ ] **Step 5: Update `AGENTS.md` Current Stage pointer** to "Stage 5 — File open/save"; commit.

**Done when:** you can live in the app as a scratchpad, daily. **Human: start dogfooding now.**

---

# MILESTONES 2–4 — Stage Outlines

> Expanded into full bite-sized task detail (like M1 above) when each prior milestone ships. Interfaces named here are binding for the detailed plans.

## M2 — The Workspace

**Stage 5 — File open/save.** Files: `Services/FileService.swift`, `Persistence/BookmarkManager.swift` (actor), tests for both. Produces: `FileService.open(url:) -> (String, mtime: Date, hash: String)` (UTF-8 with encoding fallback, line-ending detection), `FileService.save(buffer:) throws` implementing the full pipeline: exists-check → staleness check (mtime+hash vs `lastKnownDiskMTime`/`lastSavedHash`) → UTF-8 encode preserving original line endings → `AtomicFileWriter` → re-read metadata → mark clean → `SessionWriter.deleteRecovery`. `⌘O` open panel; `⇧⌘S` Save As (converts scratch → file-backed); failed save keeps dirty + shows banner. Acceptance: edit→save→verify externally; save-fail (chmod -w) stays dirty; staleness mismatch refuses silent overwrite.

**Stage 6 — Tabs & DocumentManager.** Files: `Features/Tabs/TabBarView.swift`, `Editor/DocumentManager.swift`. Tab bar appears only at 2+ buffers (SPEC §9); text-only tabs, dirty dot, × on hover; `⌘W` close (dirty ⇒ Save/Discard/Cancel sheet; scratch buffers close without prompt — they persist via recovery); `⌘{`/`⌘}` switching; per-tab undo preserved (one NSTextStorage per buffer already guarantees this — assert it in a test). Acceptance: multi-file editing safe; switch preserves cursor/scroll.

**Stage 7 — Workspace + sidebar.** Files: `Services/WorkspaceModel.swift`, `Services/FileIndexer.swift` (actor), `Features/Sidebar/SidebarView.swift`, `Domain/FileNode.swift`. `⇧⌘O` folder panel → `BookmarkManager` security-scoped bookmark → persist → resolve on relaunch (stale ⇒ reselect prompt). Async scan on `FileIndexer`; ignore list (`.git .DS_Store node_modules .build DerivedData dist out target venv .env` + hidden); visible types `.md .markdown .mdown .txt`; folders-first sort. Sidebar slides in only when workspace open (`⌘\`); context menu: Open, Reveal in Finder, Copy Path, New File. Acceptance: relaunch restores access; 10k-file scan keeps UI interactive < 1 s.

**Stage 8 — ⌘P + recents.** Files: `Utilities/FuzzyMatcher.swift` (TDD — scoring exactly: exact 100 / prefix 80 / consecutive 60 / subsequence 40 / path-segment +15 / recent +10 / open +5), `Features/QuickSwitcher/QuickSwitcherView.swift`, `Services/RecentItemsStore.swift`. Overlay ≤ 600 pt; empty query = recents + scratch buffers ("Scratch — <first line>"); `↑/↓/⏎/⎋`; opens < 50 ms. **☆ full daily driver.**

## M3 — Fast and Beautiful

**Stage 9 — Highlighting.** Files: `Editor/MarkdownTokenizer.swift` (pure, TDD-first — no AppKit import), `Editor/HighlightApplier.swift`. Token priority: fences → frontmatter → headings → blockquotes → lists → rules → inline code → bold → italic → links. Line-oriented with carried state (in-fence, in-frontmatter); damage-range re-tokenize; debounce 100–250 ms; apply via generation protocol (capture gen → background tokenize → main-actor guard gen unchanged → setAttributes only). > 2 MB: disable + banner. Acceptance: tokenizer test suite (every token class + edge cases: nested emphasis, unclosed fence, frontmatter-not-at-top); cursor never jumps; text never mutates (assert storage.string unchanged after apply).

**Stage 10 — Themes & layout.** Files: `Domain/Theme.swift`, `Services/ThemeManager.swift`, `Resources/Themes/*.json` (4: scratch-dark hero/default, scratch-light, system, high-contrast — schema per SPEC §12), `Features/Settings/AppearanceSettingsView.swift`. Layout settings live-apply to all editors (font family/size, line-height 1.0–2.5, paragraph spacing, max width 800 + full-width toggle, alignment, wrap, line numbers off). Theme switch is instant; all UI chrome stays grayscale. Acceptance: settings persist; both windows re-theme immediately.

## M4 — Shippable

**Stage 11 — Hardening.** External-change matrix in full (SPEC §7): clean/modified → silent reload + note; dirty/modified → conflicted + 4-option flow; deleted → buffer survives + Save recreates. File watching via `DispatchSource`/FSEvents on workspace root (NOT NSFilePresenter) → sidebar refresh + open-buffer checks. Find-bar polish. Debug assertions: TK2 active; recovery-count == dirty-count post-debounce.

**Stage 12 — Polish.** Status bar (word count · line:col · save state, ~60% opacity, toggleable); error banners (non-modal); app icon; accessibility labels (sidebar rows, editor, tabs); full-screen + multi-monitor pass; Reveal in Finder / Copy Path menu items; manual QA checklist (non-release items).

**Stage 13 — Release.** Bundle ID final; version 1.0.0; Release build; sign (Developer ID) + notarize + staple via `scripts/build_and_notarize.sh`; DMG via create-dmg; `spctl -a -vv` accepted on a clean machine; full manual data-loss QA gate (SPEC §15) as release blocker; tag `v1.0.0`; release notes + CHANGELOG.

---

## Execution Notes for the Orchestrating Human

- One task in flight at a time, in order. The implementing agent reads `AGENTS.md` + Global Constraints + its single task block.
- Review every diff before merge; the review question is always: *does this violate H1–H10 or I1–I7?*
- When M1 completes, return to the planning assistant to expand M2 into full task detail against the real codebase.
