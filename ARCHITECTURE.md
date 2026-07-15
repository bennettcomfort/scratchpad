# ARCHITECTURE.md — Scratchpad Recovery Milestone

> **Authority:** This file defines implementation boundaries, ownership, data flow, concurrency, persistence, and extension seams for the recovery milestone. `SPEC.md` defines product behavior. `IMPLEMENTATION_PLAN.md` defines task order. Work stops when these documents disagree.

## 1. Architectural Goal

Build one boringly reliable native macOS document editor before restoring multi-document or workspace behavior.

The recovery architecture removes ambiguity from four load-bearing paths:

1. One `DocumentSession` owns one `NSTextStorage`.
2. One `EditorHost` attaches one TextKit 2 editor to that storage.
3. One recovery pipeline snapshots the latest document state and can be awaited.
4. One file pipeline owns external access, conflict checks, atomic writes, and verified state transitions.

The current prototype is a source of regression cases, not an architectural base to preserve.

## 2. Hard Invariants

```text
H1. Never access NSTextView.layoutManager. Use TextKit 2 APIs only.
H2. Never subclass NSTextStorage. Attribute or edit the existing storage.
H3. Never use force unwraps or try!.
H4. All AppKit objects and every NSTextStorage are main-actor isolated.
H5. Open-document text lives only in its NSTextStorage.
H6. SwiftUI never owns or two-way binds a document String.
H7. All external persisted access is resolved through BookmarkStore.
H8. All user-file and internal JSON writes go through AtomicFileWriter. Scalar preferences write only through SettingsStore.
H9. A document becomes clean only after a verified successful write.
H10. Close, replacement, and termination wait for save or explicit discard.
H11. Corrupt state is quarantined and never deleted.
H12. Views communicate through typed observable state, never defaults notifications.
H13. No network code, network entitlement, or third-party runtime package.
H14. No print(); use os.Logger with subsystem com.scratchpad.app.
```

Violating an invariant is a defect even if the visible feature appears to work.

## 3. Target Source Layout

```text
Scratchpad/
  App/
    ScratchpadApp.swift
    AppDelegate.swift
    ApplicationModel.swift
    AppCommands.swift
    DocumentDecisionCoordinator.swift
    FilePanelProvider.swift
    MainWindowView.swift
  Document/
    DocumentSession.swift
    DocumentState.swift
    DocumentSnapshot.swift
    DocumentMetrics.swift
    MetricsCoordinator.swift
  Editor/
    EditorHost.swift
    ScratchTextView.swift
    EditorCoordinator.swift
    EditorCommand.swift
    EditorCommandRouter.swift
  Files/
    FileService.swift
    FileModels.swift
    FileResults.swift
    ExternalChangeMonitor.swift
  Persistence/
    ApplicationSupportPaths.swift
    AtomicFileWriter.swift
    BookmarkStore.swift
    PersistenceRecords.swift
    SessionRepository.swift
    RecoveryCoordinator.swift
  Settings/
    SettingsStore.swift
    SettingsView.swift
    ThemeDefinition.swift
    LaunchAtLoginService.swift
    FontPanelCoordinator.swift
  UI/
    DocumentTitleView.swift
    InformationBarView.swift
    ErrorBannerView.swift
    ThemePreviewView.swift
    WindowChromeConfigurator.swift
  Utilities/
    ContentHash.swift
    Log.swift
    PerformanceProbe.swift

ScratchpadTests/
  Document/
  Editor/
  Files/
  Persistence/
  Settings/
  UI/
```

Files are grouped by behavior that changes together. Deferred feature folders are removed from the active target during Stage 0; they are not renamed into speculative abstractions.

## 4. Component Ownership

| Component | Isolation | Owns | Does not own |
|---|---|---|---|
| `ApplicationModel` | `@MainActor @Observable` | Current document, settings, banner, app-level operations | Document text or file I/O |
| `DocumentDecisionCoordinator` | `@MainActor` | Save/Discard/Cancel and conflict decision serialization | Text storage or disk I/O |
| `FilePanelProvider` | `@MainActor` | Async native Open/Save panel presentation and URL selection | Bookmark persistence or document mutation |
| `DocumentSession` | `@MainActor @Observable` | `NSTextStorage`, identity, save metadata, generation, selection, scroll | Persistence scheduling or panels |
| `EditorHost` | `@MainActor` | AppKit view construction and style updates | Document switching or text copies |
| `ScratchTextView` | `@MainActor` | Responder actions and applying one editor transaction | Application state or persistence |
| `EditorCommandRouter` | Pure `Sendable` logic | Transforming text snapshot + selection into `TextEdit` | AppKit objects |
| `RecoveryCoordinator` | `@MainActor` | Per-document debounce task and lifecycle flush requests | Disk writes |
| `SessionRepository` | `actor` | Session/recovery JSON reads, writes, quarantine | UI or text storage |
| `BookmarkStore` | `actor` | Bookmark persistence, resolution, scoped-access accounting | User-document contents |
| `FileService` | `actor` | External reads, conflict checks, atomic saves | UI state transitions |
| `ExternalChangeMonitor` | `@MainActor` | One polling task and delivery of typed disk-status changes | File contents or document mutation |
| `SettingsStore` | `@MainActor @Observable` | Typed scalar preferences | Document text |
| `DocumentMetricsCalculator` | Pure `Sendable` logic | Character, word, line, token estimate values | AppKit or persistence |
| `MetricsCoordinator` | `@MainActor` | Debounce, document/generation capture, and accepted metrics | Mutable document text or AppKit layout |
| `LaunchAtLoginService` | `@MainActor` | `SMAppService.mainApp` registration and status | UserDefaults or view state |
| `FontPanelCoordinator` | `@MainActor` | Shared font-panel target/action lifetime | Editor text or settings persistence |
| `WindowChromeConfigurator` | `@MainActor` | Minimum/default/restored frame and title-region window configuration | Document state transitions |

No component may reach around these boundaries because a call is convenient.

## 5. Core Types

### 5.1 Document identity and state

```swift
enum DocumentSaveState: String, Codable, Sendable {
    case untitled
    case edited
    case clean
    case conflicted
    case deleted
    case readOnly
}

enum LineEnding: String, Codable, Sendable {
    case lf
    case crlf
}

enum WholeTextReplacementSource: Sendable {
    case initialUntitled
    case fileOpen
    case sessionRestore
    case confirmedDiskReload
}

struct TextSelection: Codable, Equatable, Sendable {
    var location: Int
    var length: Int
}
```

`DocumentSaveState` remains free of associated values so it can be persisted and observed predictably. Conflict details and user-facing errors are separate typed values.

### 5.2 Document session

```swift
@MainActor
@Observable
final class DocumentSession {
    let id: UUID
    let storage: NSTextStorage

    private(set) var fileReference: ExternalFileReference?
    private(set) var displayName: String
    private(set) var saveState: DocumentSaveState
    private(set) var hasUnsavedChanges: Bool
    private(set) var generation: Int
    private(set) var lastSavedHash: String?
    private(set) var lastKnownDiskMTime: Date?
    private(set) var lineEnding: LineEnding

    var selection: TextSelection
    var scrollOffsetY: Double
}
```

Only these operations replace or reinterpret the full text:

- initial untitled creation;
- file open;
- session restore;
- confirmed Reload from Disk; and
- undo/redo performed by the text system.

The single sanctioned whole-document method is:

```swift
func replaceEntireContents(
    _ text: String,
    source: WholeTextReplacementSource,
    selection: TextSelection?
)
```

User edits arrive through `EditorCoordinator.textDidChange`. `DocumentSession.noteUserEdit()` increments generation exactly once, sets `hasUnsavedChanges = true`, transitions untitled or clean state to edited, and requests metrics/recovery work through `ApplicationModel` callbacks. `hasUnsavedChanges` is separate because `readOnly` and `deleted` can describe either previously clean or edited text; replacement, close, recovery, and title decisions never infer preservation needs from `saveState` alone.

### 5.3 Sendable snapshots and file results

```swift
struct DocumentSnapshot: Sendable {
    let documentID: UUID
    let generation: Int
    let text: String
    let fileReference: ExternalFileReference?
    let saveState: DocumentSaveState
    let hasUnsavedChanges: Bool
    let selection: TextSelection
    let scrollOffsetY: Double
    let lineEnding: LineEnding
    let lastSavedHash: String?
    let lastKnownDiskMTime: Date?
}

struct FileOpenResult: Equatable, Sendable {
    let reference: ExternalFileReference
    let text: String
    let displayName: String
    let contentHash: String
    let modificationDate: Date
    let lineEnding: LineEnding
}

struct FileSaveResult: Equatable, Sendable {
    let documentID: UUID
    let initiatingGeneration: Int
    let reference: ExternalFileReference
    let displayName: String
    let contentHash: String
    let modificationDate: Date
    let lineEnding: LineEnding
}
```

Snapshots cross actor boundaries; `NSTextStorage` and other AppKit objects never do.

## 6. Text-System Boundary

### 6.1 Construction

`EditorHost.makeNSView` creates `NSTextView(usingTextLayoutManager: true)`, asserts `textLayoutManager != nil`, obtains `textContentStorage`, and assigns the session's existing `NSTextStorage`.

The editor is configured once with:

- plain-text mode;
- undo enabled;
- native find bar;
- smart quote/dash substitution from settings;
- spelling behavior from settings;
- wrapping from settings;
- text-container padding; and
- typing attributes from the selected fixed theme and font.

The representable is keyed with `.id(document.id)` at its SwiftUI call site. `updateNSView` may change appearance and editor settings, but it must assert that the attached session ID still equals the coordinator's session ID. It never silently swaps storage.

### 6.2 Edit notifications

The coordinator receives one `textDidChange` callback for each completed native or custom transaction. That callback:

1. updates selection metadata;
2. calls `DocumentSession.noteUserEdit()` once;
3. requests a recovery snapshot;
4. requests a metrics calculation; and
5. performs no synchronous file I/O.

Programmatic whole-text replacement suppresses dirty transitions for the duration of the sanctioned replacement method.

### 6.3 Custom editor commands

`EditorCommandRouter` is a pure transformation layer:

```swift
enum EditorCommand: Sendable {
    case duplicateLine
    case deleteLine
    case moveLinesUp
    case moveLinesDown
    case selectLine
    case joinLines
    case indent
    case outdent
    case insertLineAfter
    case insertLineBefore
}

struct TextMutation: Equatable, Sendable {
    let range: NSRange
    let replacementText: String
}

struct TextEdit: Equatable, Sendable {
    let mutations: [TextMutation]
    let resultingSelection: NSRange
}

enum EditorCommandOutcome: Equatable, Sendable {
    case selection(NSRange)
    case edit(TextEdit)
}
```

`EditorCommandOutcome.selection` handles `selectLine` without creating a fake text edit. Text-changing commands return one or more non-overlapping `TextMutation` values in ascending range order. Multiple narrow mutations let indentation and line joining preserve attributes on unchanged characters.

`ScratchTextView` exposes responder actions for these commands. Application menu commands send actions through the first-responder chain. There is no editor-wide `NSEvent.addLocalMonitorForEvents` hook.

Applying a `TextEdit` validates all ranges together, applies mutations from highest location to lowest inside one undo group, restores the resulting selection, and produces one change notification. Undo integration tests—not assumptions about `NSTextStorage`—select the final AppKit mutation API.

Native commands not listed above pass through untouched.

## 7. Observable State and SwiftUI

`ApplicationModel` is the root environment value:

```swift
@MainActor
@Observable
final class ApplicationModel {
    private(set) var document: DocumentSession
    let settings: SettingsStore
    var banner: ErrorBanner?
    var pendingDecision: DocumentDecision?
}
```

`OpenBuffer`-style unobservable nested reference state does not return. SwiftUI reads observable document metadata and immutable metrics. AppKit renders text directly from storage.

Menus call typed `ApplicationModel` operations. They do not write signaling keys into `UserDefaults`. Settings views bind to `SettingsStore`, which updates memory first and persists its scalar value once.

## 8. Edit and Metrics Flow

```text
Keystroke / responder command
    -> NSTextView transaction
    -> EditorCoordinator.textDidChange
    -> DocumentSession generation += 1 and state = edited
    -> RecoveryCoordinator.schedule(documentID)
    -> Metrics task captures (documentID, generation, text snapshot)
    -> pure background calculation
    -> main actor applies only if documentID and generation still match
```

`DocumentMetricsCalculator` implements the exact definitions in `SPEC.md`. The estimate is intentionally model-agnostic and carries an `isEstimate` flag so the UI cannot accidentally omit `~`.

```swift
struct DocumentMetrics: Equatable, Sendable {
    let characters: Int
    let words: Int
    let lines: Int
    let estimatedTokens: Int
    let isEstimate: Bool
}
```

## 9. Persistence Architecture

### 9.1 Application Support layout

```text
~/Library/Application Support/Scratchpad/
  session/latest-session.json
  recovery/document-<uuid>.json
  bookmarks/bookmarks.json
  quarantine/<timestamp>-<original-name>
  logs/
```

Every JSON root carries `schemaVersion: Int`. Version 1 is the only accepted recovery-milestone schema. An unsupported or undecodable schema is quarantined before startup continues with recoverable alternatives.

### 9.2 Records

```swift
struct SessionRecord: Codable, Sendable {
    let schemaVersion: Int
    let documentID: UUID
    let fileReferenceID: UUID?
    let displayName: String
    let saveState: DocumentSaveState
    let hasUnsavedChanges: Bool
    let selection: TextSelection
    let scrollOffsetY: Double
    let lineEnding: LineEnding
    let lastSavedHash: String?
    let lastKnownDiskMTime: Date?
    let windowFrame: CGRect
    let didCloseCleanly: Bool
    let savedAt: Date
}

struct RecoveryRecord: Codable, Sendable {
    let schemaVersion: Int
    let documentID: UUID
    let fileReferenceID: UUID?
    let filePathHint: String?
    let unsavedText: String
    let baseDiskHash: String?
    let baseDiskMTime: Date?
    let lineEnding: LineEnding
    let selection: TextSelection
    let scrollOffsetY: Double
    let savedAt: Date
}

struct BookmarkRecord: Codable, Sendable {
    let id: UUID
    let bookmarkData: Data
    let pathHint: String
    let updatedAt: Date
}

struct BookmarkCollection: Codable, Sendable {
    let schemaVersion: Int
    let records: [BookmarkRecord]
}
```

`SessionRecord.didCloseCleanly` is written false at launch and true only in the final session write after an awaited successful termination flush. It is diagnostic; restore behavior does not depend on it.

### 9.3 Atomic writes and quarantine

`AtomicFileWriter` writes a uniquely named temporary file in the destination directory, flushes it, then atomically replaces or creates the destination. Failure removes only the temporary file.

`SessionRepository` is the sole session/recovery JSON writer. It serializes writes, validates schema versions on load, and moves corrupt inputs to quarantine through `AtomicFileWriter`-compatible same-volume operations.

If quarantine fails, the original remains untouched and the error is surfaced. Load does not repeatedly overwrite or delete the corrupt input.

## 10. Recovery Scheduling and Lifecycle

`RecoveryCoordinator` is main-actor isolated because it captures `DocumentSession` snapshots. It owns a dictionary of pending debounce tasks keyed by document ID even though recovery initially exposes one document. This prevents a return to the prototype's single-global-debouncer defect.

```swift
@MainActor
final class RecoveryCoordinator {
    func scheduleRecovery(for document: DocumentSession)
    func flushRecovery(for document: DocumentSession) async throws
    func flushSession(
        for document: DocumentSession,
        windowFrame: CGRect,
        didCloseCleanly: Bool
    ) async throws
    func cancelRecovery(documentID: UUID)
}
```

The two-second debounce closure captures only document identity. When it fires on the main actor, it creates a fresh snapshot of the latest text and sends the `RecoveryRecord` to `SessionRepository`.

### 10.1 Termination handshake

`AppDelegate.applicationShouldTerminate` returns `.terminateLater` and starts one main-actor termination task. The task:

1. resolves Save / Discard / Cancel when required;
2. flushes current recovery state;
3. flushes session and window metadata;
4. writes the final session record with `didCloseCleanly = true` only after successful recovery writes; and
5. calls `NSApp.reply(toApplicationShouldTerminate:)` with the result.

Write failure replies `false`, keeps the app and document open, and shows an error banner. Repeated termination requests join the existing task rather than starting concurrent flushes.

Window close and New/Open replacement use the same `DocumentDecisionCoordinator`; no view implements its own save-and-close fallthrough.

`AppDelegate.applicationDidResignActive` requests a recovery and session flush with `didCloseCleanly = false`. If that background flush fails, recovery remains pending and the application surfaces the failure when it becomes active again.

## 11. Bookmark and External File Access

```swift
struct ExternalFileReference: Codable, Equatable, Sendable {
    let bookmarkID: UUID
    let pathHint: String
}

struct ScopedAccessToken: Sendable {
    let id: UUID
    let url: URL
}
```

`BookmarkStore` provides:

```swift
actor BookmarkStore {
    func storeSelection(_ url: URL) async throws -> ExternalFileReference
    func reference(for bookmarkID: UUID) async throws -> ExternalFileReference?
    func beginAccess(_ reference: ExternalFileReference) async throws -> ScopedAccessToken
    func endAccess(_ token: ScopedAccessToken) async
    func refresh(_ token: ScopedAccessToken) async throws
    func forget(_ reference: ExternalFileReference) async throws
}
```

The store persists bookmark data atomically and tracks active tokens. `FileService` obtains a token before every external read or write and ends it with `defer`. A stale bookmark is refreshed and persisted. An unresolvable bookmark produces a typed reselect-required error; direct path fallback is forbidden under the sandbox.

Open-panel and Save-panel selections are converted into `ExternalFileReference` values before application state adopts them.

`FilePanelProvider` wraps `NSOpenPanel.begin` and `NSSavePanel.begin` with checked continuations. Open accepts exactly `.md`, `.markdown`, `.mdown`, and `.txt`, allows one file, and allows no directory selection. Panel cancellation returns `nil` and changes no bookmark, operation, document, or recovery state. `BookmarkStore.storeSelection` reuses the existing bookmark ID for the same standardized file URL.

Clean-session restoration resolves `SessionRecord.fileReferenceID` through `BookmarkStore.reference(for:)`. The path hint comes from the persisted `BookmarkRecord`; it is display and diagnostic metadata only and is never converted into a direct-access URL.

## 12. File Service and State Transitions

`FileService` accepts immutable values and returns immutable results:

```swift
actor FileService {
    func open(_ reference: ExternalFileReference) async throws -> FileOpenResult
    func save(_ snapshot: DocumentSnapshot) async throws -> FileSaveResult
    func saveAs(_ snapshot: DocumentSnapshot, to reference: ExternalFileReference) async throws -> FileSaveResult
    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus
}
```

```swift
enum ExternalFileStatus: Equatable, Sendable {
    case unchanged
    case changed(contentHash: String, modificationDate: Date)
    case missing
    case readOnly
    case accessRequiresReselection
}
```

It never mutates `DocumentSession`. `ApplicationModel` applies a successful result on the main actor only when the document ID and generation still match the initiating operation.

### 12.1 Save pipeline

```text
main actor captures DocumentSnapshot
    -> FileService begins scoped access
    -> verify file existence and writability
    -> compare current disk hash + mtime with snapshot base
    -> return typed conflict before writing on mismatch
    -> encode UTF-8 with stored line-ending convention
    -> AtomicFileWriter writes
    -> re-read bytes and metadata
    -> verify bytes/hash
    -> return FileSaveResult
    -> main actor checks document identity + generation
    -> update base metadata and mark clean
    -> SessionRepository deletes superseded recovery
```

If generation changed while saving, the successful disk write becomes the new base but the document remains edited and immediately receives a new recovery snapshot. No keystroke is marked clean accidentally.

### 12.2 Open and replacement serialization

`ApplicationModel` owns one `DocumentOperationState` (`idle`, `opening`, `saving`, `closing`, or `terminating`). Operations that would replace or close the document serialize through that state. A duplicate open request for the same `ExternalFileReference` joins or ignores the in-flight operation.

```swift
enum DocumentOperationState: Equatable, Sendable {
    case idle
    case opening(ExternalFileReference)
    case saving(UUID)
    case closing
    case terminating
}
```

`DocumentDecisionCoordinator` owns at most one pending destructive decision. New, Open, Close, Quit, and conflict resolution all call it rather than presenting independent sheets from views.

### 12.3 External-change monitoring

`ExternalChangeMonitor` owns one cancellable polling task for the current file-backed document. Once per second while a file is open, it captures document ID, generation, file reference, and known disk metadata, then asks `FileService.inspect` for a typed `ExternalFileStatus`.

The main actor discards results for a replaced document. It serializes a relevant result with any active open/save/close operation and applies the matrix from `SPEC.md`:

- clean + changed reloads through the sanctioned whole-text replacement path;
- edited + changed enters conflicted state without replacing text;
- missing enters deleted state; and
- denied access enters read-only or reselect-required state.

The monitor never reads `NSTextStorage`, never writes files, and stops before the document reference is replaced. Save-time staleness checks remain mandatory even when monitoring is active.

## 13. Errors and Decisions

Services throw typed errors with no UI strings. `ApplicationModel` maps them into:

```swift
struct ErrorBanner: Identifiable, Equatable {
    let id: UUID
    let message: String
    let actions: [BannerAction]
}

enum BannerAction: Equatable {
    case dismiss
    case retry
    case saveAs
    case reselectFile
    case openRecoveryFolder
}

enum PendingReplacement: Equatable, Sendable {
    case newUntitled
    case open(ExternalFileReference)
}

struct ConflictContext: Equatable, Sendable {
    let documentID: UUID
    let initiatingGeneration: Int
    let fileReference: ExternalFileReference
    let baseHash: String?
    let diskHash: String
    let diskModificationDate: Date
}

enum DocumentDecision {
    case replaceCurrentDocument(PendingReplacement)
    case closeWindow
    case terminateApplication
    case resolveConflict(ConflictContext)
    case recreateDeletedFile
}

enum DocumentDecisionResolution: Equatable {
    case save
    case discard
    case cancel
    case overwrite
    case reloadFromDisk
    case saveAs
    case recreate
}

@MainActor
@Observable
final class DocumentDecisionCoordinator {
    private(set) var pending: DocumentDecision?

    func request(_ decision: DocumentDecision) async -> DocumentDecisionResolution
    func resolvePending(with resolution: DocumentDecisionResolution)
}
```

Only decisions capable of discarding or overwriting text use modal sheets. Routine failures use `ErrorBannerView`. A log entry accompanies the visible error with private file paths and public error categories.

## 14. Settings and Themes

`SettingsStore` declares one typed property per setting in `SPEC.md`. It accepts an injected `UserDefaults` suite for tests. Defaults are registered centrally; views never duplicate default literals.

Font selection persists a font descriptor archive or stable family/postscript name plus point size. If the saved font is unavailable, the store falls back to SF Mono 15 pt without deleting the preference.

`ThemeDefinition` is a fixed value type for System, Light, and Dark. System resolves to Light or Dark from the current effective appearance. Themes define editor background/foreground, caret, selection, title-region, separator, information-bar, and banner colors. No theme JSON loader exists in recovery.

High-frequency editor updates consume a snapshot of settings; they do not read `UserDefaults` directly.

`MetricsCoordinator` captures immutable `(documentID, generation, text, countWhitespace)` input on the main actor, computes with `DocumentMetricsCalculator` off-main, and publishes only an exact identity/generation match. It never stores document text.

The recovery window uses a hidden native title bar with a dedicated 44-point title region, native traffic-light controls, and SwiftUI's window-background drag behavior. `WindowChromeConfigurator` applies the 820 × 640 default, 480 × 320 minimum, and the last validated session frame. No toolbar, tab strip, sidebar, line numbers, or syntax layer is present.

## 15. Concurrency Topology

```text
@MainActor
  SwiftUI views
  AppDelegate lifecycle coordination
  ApplicationModel
  DocumentSession and NSTextStorage
  EditorHost / ScratchTextView / EditorCoordinator
  ExternalChangeMonitor
  RecoveryCoordinator snapshot capture
  SettingsStore

actors
  SessionRepository
  BookmarkStore
  FileService

background pure work
  DocumentMetricsCalculator
```

Async work returning to a document uses the generation protocol:

1. Capture `(documentID, generation, immutable input)` on the main actor.
2. Compute or perform I/O without AppKit objects.
3. Return to the main actor.
4. Reject a result for a different document.
5. Apply generation-sensitive results only under the rule defined for that operation.

Metrics require an exact generation match. Save results use the special rule in §12.1 so an intervening edit remains dirty.

Detached tasks never capture `DocumentSession`, `NSTextStorage`, `NSFont`, `NSColor`, or closures isolated to the main actor.

## 16. Testing Seams

The architecture requires dependency injection at boundaries:

- `ApplicationSupportPaths` accepts a temporary root.
- `SettingsStore` accepts a dedicated `UserDefaults` suite.
- `ApplicationModel` accepts file, persistence, bookmark, and lifecycle protocols.
- Time-based recovery accepts a controllable clock or scheduler.
- File metadata inspection is isolated behind `FileService` methods.
- Pure command routing accepts strings and `NSRange` values.
- Metrics calculation is a pure function.

Tests are divided into:

- pure unit tests for commands, metrics, schemas, hashing, and state transitions;
- temporary-directory integration tests for atomic writes, persistence, recovery, and file conflicts;
- main-actor AppKit integration tests for storage attachment, selection, responder actions, and undo;
- application-model tests for operation serialization and close/termination ordering; and
- manual sandbox, crash, accessibility, and visual gates from `SPEC.md`.

The test host must not start the full production application model as an incidental side effect. Unit tests construct only the subject and injected dependencies they require.

## 17. Prototype Disposition

| Current area | Recovery action |
|---|---|
| `AtomicFileWriter`, `ApplicationSupportPaths`, `ContentHash`, `PersistenceRecords`, `Log` | Replace or retain only through the new edge-case-tested Stage 3 contracts |
| `AppModel`, `SessionService`, `ScratchBuffer`, `BufferStore` | Replace with `ApplicationModel`, `DocumentSession`, and recovery services |
| `EditorTextView`, current `EditorCoordinator` | Replace with identity-safe editor boundary and responder command system |
| `BookmarkManager`, current `FileService` | Replace with persistent bookmark and actor-based file pipelines |
| Current theme/settings/status views | Replace with typed settings, fixed themes, and information bar |
| Tabs, workspace, sidebar, Quick Open | Remove from active target; preserve history for later specifications |
| Zen/global hotkey | Remove from active target until its post-recovery stage |
| Markdown tokenizer/highlighter | Remove from active target until incremental-highlighting stage |
| Existing helper tests | Keep only tests that still express approved behavior; do not preserve obsolete assertions for compatibility |

The plan must delete or exclude obsolete source in the same task that replaces its responsibility. Two active implementations of a subsystem are forbidden.

## 18. Deferred Extension Contracts

Deferred features may return only through these seams:

- **Tabs:** introduce a `DocumentCollection` above independent `DocumentSession` instances. Each editor host is keyed by document ID. In-flight opens are deduplicated before file I/O begins.
- **Workspace/sidebar:** use native `NSSplitViewController` or an equivalently stable native split-view bridge. Width persists after drag completion, never on every pointer event through global defaults notifications.
- **Quick Open:** sends one typed open request through `ApplicationModel`; Return has one activation path.
- **Zen/global hotkey:** uses the same document and command systems. Global registration has one owner, reports registration failure visibly, and unregisters deterministically.
- **Highlighting:** consumes immutable text snapshots, computes incrementally off-main, and applies attributes only after document ID/generation validation.

These seams are constraints, not permission to scaffold deferred code now.

## 19. Dependency and Build Rules

- `project.yml` remains the project source of truth.
- The App Sandbox entitlement is present in every app configuration.
- The recovery target includes no deferred feature sources.
- Swift strict concurrency remains `complete`.
- The minimum deployment target remains macOS 26.
- CI runs generation, build, and tests without lowering the deployment target.
- A source warning, concurrency warning, runtime publishing warning, or test-host side effect fails the relevant stage gate.

## 20. Architectural Acceptance

The architecture is implemented only when repository evidence shows:

- one storage owner and one editor attachment;
- one observable application state path;
- one command route without local key monitors;
- one serialized recovery writer and an awaited lifecycle flush;
- persistent bookmarks under the actual sandbox;
- one conflict-aware atomic file pipeline;
- typed settings without defaults notifications;
- no active deferred subsystem; and
- automated and manual evidence required by `SPEC.md`.

Passing tests that do not exercise these boundaries do not satisfy architectural acceptance.
