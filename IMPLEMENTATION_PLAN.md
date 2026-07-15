# Scratchpad Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Plan status:** Gates 4A–4C approved. The implementation lock in `AGENTS.md` remains ON until Gates 4D–4E and the final consistency gate are approved.

**Goal:** Replace the unsafe prototype in place with a boringly reliable, single-document native macOS prompt and Markdown editor.

**Architecture:** A SwiftUI application shell owns one observable `ApplicationModel`; one main-actor `DocumentSession` owns one `NSTextStorage`; and one AppKit TextKit 2 editor attaches to that storage. Actors isolate bookmark, recovery, and file persistence, while every write flows through `AtomicFileWriter`.

**Tech Stack:** Swift 6 with strict concurrency, SwiftUI, AppKit, TextKit 2, XCTest, XcodeGen, macOS 26+, and zero third-party runtime dependencies.

## Global Constraints

- `SPEC.md` defines behavior; `ARCHITECTURE.md` defines implementation boundaries; this file defines task order; `TRACKER.md` records current evidence.
- Work only on the current stage and task in `TRACKER.md`.
- Run a failing test or capture the specified failing baseline before implementation.
- Use the exact interfaces and paths in the current task; do not preserve broken prototype APIs.
- Build with zero warnings using `xcodegen && xcodebuild -scheme Scratchpad -destination 'platform=macOS' build`.
- Test using `xcodebuild -scheme Scratchpad -destination 'platform=macOS' test`.
- Commit each verified task independently with a conventional commit.
- Do not advance a stage without fresh tracker evidence and explicit user approval.

```text
H1. Never access NSTextView.layoutManager. Use TextKit 2 APIs only.
H2. Never subclass NSTextStorage. Attribute or edit the existing storage.
H3. Never use force unwraps or try!.
H4. All AppKit objects and every NSTextStorage are main-actor isolated.
H5. Open-document text lives only in its NSTextStorage.
H6. SwiftUI never owns or two-way binds a document String.
H7. All external persisted access is resolved through BookmarkStore.
H8. All user and internal writes go through AtomicFileWriter.
H9. A document becomes clean only after a verified successful write.
H10. Close, replacement, and termination wait for save or explicit discard.
H11. Corrupt state is quarantined and never deleted.
H12. Views communicate through typed observable state, never defaults notifications.
H13. No network code, network entitlement, or third-party runtime package.
H14. No print(); use os.Logger with subsystem com.scratchpad.app.
```

## Plan Sections

- Gate 4A: Recovery Stage 0 — Baseline and containment. Detailed below.
- Gate 4B: Recovery Stage 1 — Document and editor core. Detailed below.
- Gate 4C: Recovery Stage 2 — Sublime-style command system. Detailed below.
- Gates 4D–4E: Stages 3–5. Intentionally absent until each section is drafted and approved.
- Gate 5: Cross-document consistency review and implementation unlock.

---

# Gate 4A — Recovery Stage 0: Baseline and Containment

## Stage Goal

Preserve the last prototype code revision as evidence, prevent every deferred or unsafe subsystem from compiling into the recovery target, and establish enforceable local and CI gates for the replacement work.

Stage 0 does not repair the editor. Its independently testable deliverable is a warning-free containment app whose target contains no prototype editor, tab, sidebar, workspace, Quick Open, Zen, hotkey, highlighting, or persistence implementation.

## Stage 0 File Map

**Create**

- `docs/recovery/PROTOTYPE_BASELINE.md` — immutable audit evidence and prototype disposition.
- `docs/recovery/REGRESSION_MATRIX.md` — each known failure mapped to its future automated and manual proof.
- `Scratchpad/RecoveryBaseline/RecoveryStage.swift` — compile-time marker for the containment target.
- `Scratchpad/RecoveryBaseline/ContainmentApp.swift` — temporary buildable application entry point.
- `ScratchpadTests/RecoveryContainmentTests.swift` — target-boundary, build-policy, and entitlement assertions.

**Modify**

- `project.yml` — replace recursive source discovery with explicit Stage 0 allowlists and warnings-as-errors.
- `.github/workflows/ci.yml` — run the same generation, build, and test commands without deployment-target overrides.
- `TRACKER.md` — record task state, commands, results, commits, and the Stage 0 approval matrix.

**Preserve unchanged but remove from the active target**

- `Scratchpad/App/`
- `Scratchpad/Domain/`
- `Scratchpad/Editor/`
- `Scratchpad/Features/`
- `Scratchpad/Persistence/`
- `Scratchpad/Services/`
- `Scratchpad/Utilities/`
- all prototype tests except `ScratchpadTests/SmokeTests.swift`

The preserved tree is evidence only. Stage 1 creates the replacement files named by `ARCHITECTURE.md`; it does not reactivate the prototype source root.

## Stage 0 Interfaces

```swift
enum RecoveryStage: String, Equatable, Sendable {
    case baselineContainment

    static let current: Self
    var title: String { get }
    var explanation: String { get }
}
```

No other Stage 0 runtime interface survives into the product architecture.

### Task 0.1: Preserve the Prototype Baseline and Regression Contract

**Files:**

- Create: `docs/recovery/PROTOTYPE_BASELINE.md`
- Create: `docs/recovery/REGRESSION_MATRIX.md`
- Modify: `TRACKER.md`

**Interfaces:**

- Consumes: audited prototype code revision `a1f36f6` and the defect ledger in `TRACKER.md`.
- Produces: a stable evidence record and exact future test ownership for every known failure.

- [ ] **Step 1: Confirm the preserved code revision**

Run:

```sh
git show -s --format='%h %s' a1f36f6
```

Expected:

```text
a1f36f6 fix: Quick Open spuriously re-opening on any UserDefaults change
```

- [ ] **Step 2: Re-run the prototype baseline before containment**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
```

Expected: generation succeeds, build succeeds, and 35 prototype tests pass. A SwiftUI runtime diagnostic about publishing changes from a background thread remains known baseline evidence; it is not accepted as a green recovery result.

- [ ] **Step 3: Create `docs/recovery/PROTOTYPE_BASELINE.md`**

```markdown
# Scratchpad Prototype Baseline

> Historical evidence only. This document cannot authorize implementation.

## Preserved Revision

- Last prototype code revision: `a1f36f6`
- Recovery decision date: 2026-07-14
- Disposition: preserve source for evidence; remove it from the active target; replace the core in place.

## Observed Baseline

- XcodeGen generation: succeeded.
- macOS build: succeeded.
- XCTest: 35 tests passed.
- Runtime quality: not accepted; SwiftUI reported background publication during tests.
- Coverage quality: helper happy paths dominate; lifecycle, identity, close, recovery, bookmark, and command-routing failures are not behaviorally protected.

## Critical Findings

1. The editor coordinator remains attached to the first buffer, so tab identity and visible text can diverge.
2. Concurrent open and double-activation paths can create duplicate tabs for one URL.
3. Save-and-Close starts an asynchronous save and closes immediately through fallthrough.
4. Recovery scheduling is global, clean restoration can become empty, dirty restoration lacks complete base metadata, and termination does not await the final flush.
5. The App Sandbox is disabled and security-scoped bookmarks are not persisted.
6. Competing local key monitors bypass the responder chain and make commands unreliable.
7. The sidebar divider changes its own drag geometry while continuously publishing defaults updates.
8. Zen and global-hotkey registration have conflicting commands and weak lifecycle/error handling.
9. Global defaults notifications drive unrelated UI state.
10. Whole-document highlighting runs on the main actor and can leave stale attributes.

## Preservation Rule

Until a planned replacement task explicitly removes a prototype file, the prototype directories remain byte-for-byte unchanged from `a1f36f6`. They are excluded from the application and test source allowlists and must never be used as compatibility constraints.
```

- [ ] **Step 4: Create `docs/recovery/REGRESSION_MATRIX.md`**

```markdown
# Scratchpad Recovery Regression Matrix

> This matrix assigns proof. A scenario becomes verified only when its named automated test and manual check both have fresh evidence in `TRACKER.md`.

| Scenario | Owning stage | Automated proof | Manual proof | Current state |
|---|---:|---|---|---|
| Active editor owns exactly one document's storage | 1 | `DocumentSessionTests.testEachSessionOwnsDistinctTextStorage` and `EditorHostTests.testHostUsesCurrentSessionStorage` | Type in a document, replace it, and confirm old text cannot appear or change | pending |
| Two concurrent future opens for one URL produce one document | deferred tabs | `DocumentRegistryTests.testConcurrentOpenDeduplicatesCanonicalURL` | Double-open one file and observe one tab | pending |
| Save-and-Close waits and remains open on save failure | 3 | `DocumentDecisionCoordinatorTests.testSaveFailureDoesNotResolveClose` | Induce a write failure and confirm text remains open and dirty | pending |
| Recovery work is isolated per document identity | 3 | `RecoveryCoordinatorTests.testSchedulingOneDocumentDoesNotCancelAnother` | Covered again when multi-document returns | pending |
| Clean file restoration reads disk rather than empty recovery text | 3 | `SessionRepositoryTests.testCleanFileRecordRestoresFromDisk` | Relaunch a clean file-backed document and compare its contents | pending |
| Dirty restoration retains base hash and enters conflict flow | 3 | `SessionRepositoryTests.testDirtyRecordRestoresConflictMetadata` | Edit, terminate, change disk externally, relaunch, and resolve conflict | pending |
| Termination persists the latest keystroke | 3 | `RecoveryCoordinatorTests.testFlushAllAwaitsLatestSnapshot` | Type a unique suffix, force-quit immediately, and relaunch | pending |
| Security-scoped access survives sandboxed relaunch | 3 | `BookmarkStoreTests.testPersistedBookmarkResolvesAfterReload` | Open outside container, quit, relaunch, and save successfully | pending |
| Each editor command fires once and remains undoable | 2 | one focused test per `EditorCommand`, plus `EditorCommandRouterTests.testActionRoutesOnce` | Run the full shortcut matrix and undo every transformation | pending |
| Information metrics update without a SwiftUI text copy | 4 | `DocumentMetricsTests` and architecture invariant review | Type continuously and inspect correct counts without UI stalls | pending |
| Settings changes avoid global defaults notifications | 4 | `SettingsStoreTests.testMutationPublishesTypedStateOnly` | Change each setting and observe only its intended UI effect | pending |
| Future sidebar resizing uses native split view | deferred workspace | `WorkspaceSplitViewTests.testResizePersistsOnlyOnCommit` | Drag repeatedly with no shaking or pointer drift | pending |
| Future hotkey registration has one owner and visible failures | deferred Zen | `HotkeyManagerTests.testRegistrationFailureIsPublished` | Rebind to a conflicting shortcut and observe actionable error | pending |
| Future highlighting discards stale generations | deferred highlighting | `HighlightPipelineTests.testStaleGenerationIsDiscarded` | Paste a large document while typing and observe responsive correct styling | pending |
```

- [ ] **Step 5: Verify the evidence documents**

Run:

```sh
git diff --check
rg -n 'a1f36f6|Save-and-Close|sidebar|global hotkey|termination' docs/recovery/PROTOTYPE_BASELINE.md docs/recovery/REGRESSION_MATRIX.md
```

Expected: `git diff --check` exits 0; `rg` finds the preserved revision and all named critical scenarios.

- [ ] **Step 6: Record and commit Task 0.1**

Set Task 0.1 to `verified` in `TRACKER.md` with the three command results and the date, then run:

```sh
git add docs/recovery/PROTOTYPE_BASELINE.md docs/recovery/REGRESSION_MATRIX.md TRACKER.md
git commit -m "docs: preserve prototype recovery baseline"
```

Expected: one documentation-only commit; no application, test, project, entitlement, or workflow file changes.

### Task 0.2: Enforce the Recovery Source Boundary

**Files:**

- Create: `Scratchpad/RecoveryBaseline/RecoveryStage.swift`
- Create: `Scratchpad/RecoveryBaseline/ContainmentApp.swift`
- Create: `ScratchpadTests/RecoveryContainmentTests.swift`
- Modify: `project.yml`
- Modify: `TRACKER.md`

**Interfaces:**

- Consumes: XcodeGen target configuration and the preserved prototype directories.
- Produces: `RecoveryStage`, a buildable containment entry point, and an explicit source allowlist that later stages extend deliberately.

- [ ] **Step 1: Write the failing containment tests**

Create `ScratchpadTests/RecoveryContainmentTests.swift`:

```swift
import Foundation
import XCTest
@testable import Scratchpad

final class RecoveryContainmentTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testRuntimeDeclaresBaselineContainmentStage() {
        XCTAssertEqual(RecoveryStage.current, .baselineContainment)
    }

    func testProjectUsesExplicitRecoveryAllowlists() throws {
        let projectURL = repositoryRoot.appendingPathComponent("project.yml")
        let project = try String(contentsOf: projectURL, encoding: .utf8)

        XCTAssertFalse(project.contains("sources: [Scratchpad]"))
        XCTAssertFalse(project.contains("sources: [ScratchpadTests]"))
        XCTAssertTrue(project.contains("- path: Scratchpad/RecoveryBaseline"))
        XCTAssertTrue(project.contains("- path: Scratchpad/Assets.xcassets"))
        XCTAssertTrue(project.contains("- ScratchpadTests/SmokeTests.swift"))
        XCTAssertTrue(project.contains("- ScratchpadTests/RecoveryContainmentTests.swift"))
    }
}
```

- [ ] **Step 2: Run the focused test and observe failure**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/RecoveryContainmentTests test
```

Expected: test compilation fails with `cannot find 'RecoveryStage' in scope`. Record that failure in `TRACKER.md`; do not weaken the test.

- [ ] **Step 3: Create `Scratchpad/RecoveryBaseline/RecoveryStage.swift`**

```swift
enum RecoveryStage: String, Equatable, Sendable {
    case baselineContainment

    static let current: Self = .baselineContainment

    var title: String {
        "Scratchpad Recovery"
    }

    var explanation: String {
        "The unsafe prototype is contained while its editor core is rebuilt."
    }
}
```

- [ ] **Step 4: Create `Scratchpad/RecoveryBaseline/ContainmentApp.swift`**

```swift
import SwiftUI

@main
struct ContainmentApp: App {
    var body: some Scene {
        Window(RecoveryStage.current.title, id: "main") {
            VStack(spacing: 12) {
                Text(RecoveryStage.current.title)
                    .font(.headline)
                Text(RecoveryStage.current.explanation)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(minWidth: 480, minHeight: 320)
        }
        .windowResizability(.contentMinSize)
    }
}
```

- [ ] **Step 5: Replace recursive target discovery in `project.yml`**

Replace the file with:

```yaml
name: Scratchpad
options:
  bundleIdPrefix: com.scratchpad
  deploymentTarget:
    macOS: "26.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
  configs:
    Debug:
      ENABLE_HARDENED_RUNTIME: NO
    Release:
      ENABLE_HARDENED_RUNTIME: YES
targets:
  Scratchpad:
    type: application
    platform: macOS
    sources:
      - path: Scratchpad/RecoveryBaseline
      - path: Scratchpad/Assets.xcassets
    settings:
      CODE_SIGN_ENTITLEMENTS: Scratchpad/App/Scratchpad.entitlements
      INFOPLIST_FILE: Scratchpad/App/Info.plist
      PRODUCT_BUNDLE_IDENTIFIER: com.scratchpad.app
  ScratchpadTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - ScratchpadTests/SmokeTests.swift
      - ScratchpadTests/RecoveryContainmentTests.swift
    settings:
      GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: Scratchpad
schemes:
  Scratchpad:
    build: { targets: { Scratchpad: all } }
    test: { targets: [ScratchpadTests] }
```

- [ ] **Step 6: Generate and run the focused tests**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/RecoveryContainmentTests test
```

Expected: both `RecoveryContainmentTests` tests pass.

- [ ] **Step 7: Verify the generated project excludes prototype sources**

Run:

```sh
rg 'AppModel.swift|BufferStore.swift|SidebarView.swift|TabBarView.swift|ZenWindowController.swift|MarkdownTokenizer.swift|SessionWriter.swift' Scratchpad.xcodeproj/project.pbxproj
```

Expected: no matches and exit status 1. The generated project contains only `RecoveryBaseline`, the asset catalog, and the two allowlisted tests.

Run:

```sh
git diff --exit-code a1f36f6 -- Scratchpad/App Scratchpad/Domain Scratchpad/Editor Scratchpad/Features Scratchpad/Persistence Scratchpad/Services Scratchpad/Utilities
```

Expected: no output and exit status 0, proving the prototype implementation remains unchanged.

- [ ] **Step 8: Build, test, and manually launch**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -derivedDataPath /tmp/ScratchpadStage0 build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
open /tmp/ScratchpadStage0/Build/Products/Debug/Scratchpad.app
```

Expected: warning-free build; 3 tests pass; the app shows one native window containing “Scratchpad Recovery” and the containment explanation. It exposes no editor, tab bar, sidebar, Quick Open, settings, Zen window, or hotkey.

- [ ] **Step 9: Record and commit Task 0.2**

Set Task 0.2 to `verified` in `TRACKER.md` with the failing test, passing test, source-boundary checks, build, test, and manual launch evidence, then run:

```sh
git add project.yml Scratchpad/RecoveryBaseline ScratchpadTests/RecoveryContainmentTests.swift TRACKER.md
git commit -m "refactor: contain prototype source target"
```

Expected: the commit contains only the explicit files above. Prototype source remains present and unmodified.

### Task 0.3: Enforce Warning, Dependency, Entitlement, and CI Policy

**Files:**

- Modify: `ScratchpadTests/RecoveryContainmentTests.swift`
- Modify: `project.yml`
- Modify: `.github/workflows/ci.yml`
- Modify: `TRACKER.md`

**Interfaces:**

- Consumes: the Stage 0 source allowlist from Task 0.2.
- Produces: executable policy tests and one local/CI command contract for every replacement task.

- [ ] **Step 1: Replace `ScratchpadTests/RecoveryContainmentTests.swift` with the complete policy suite**

```swift
import Foundation
import XCTest
@testable import Scratchpad

final class RecoveryContainmentTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(at relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testRuntimeDeclaresBaselineContainmentStage() {
        XCTAssertEqual(RecoveryStage.current, .baselineContainment)
    }

    func testProjectUsesExplicitRecoveryAllowlists() throws {
        let project = try contents(at: "project.yml")

        XCTAssertFalse(project.contains("sources: [Scratchpad]"))
        XCTAssertFalse(project.contains("sources: [ScratchpadTests]"))
        XCTAssertTrue(project.contains("- path: Scratchpad/RecoveryBaseline"))
        XCTAssertTrue(project.contains("- path: Scratchpad/Assets.xcassets"))
        XCTAssertTrue(project.contains("- ScratchpadTests/SmokeTests.swift"))
        XCTAssertTrue(project.contains("- ScratchpadTests/RecoveryContainmentTests.swift"))
    }

    func testProjectTreatsSwiftWarningsAsErrors() throws {
        let project = try contents(at: "project.yml")
        XCTAssertTrue(project.contains("SWIFT_TREAT_WARNINGS_AS_ERRORS: YES"))
    }

    func testProjectDeclaresNoRuntimePackages() throws {
        let project = try contents(at: "project.yml")
        XCTAssertFalse(project.contains("\npackages:"))
    }

    func testEntitlementsDeclareNoNetworkAccess() throws {
        let entitlements = try contents(at: "Scratchpad/App/Scratchpad.entitlements")
        XCTAssertFalse(entitlements.contains("com.apple.security.network.client"))
        XCTAssertFalse(entitlements.contains("com.apple.security.network.server"))
    }

    func testCIUsesProjectDeploymentTargetWithoutOverride() throws {
        let workflow = try contents(at: ".github/workflows/ci.yml")
        XCTAssertFalse(workflow.contains("MACOSX_DEPLOYMENT_TARGET"))
        XCTAssertTrue(workflow.contains("xcodebuild -scheme Scratchpad -destination 'platform=macOS' build"))
        XCTAssertTrue(workflow.contains("xcodebuild -scheme Scratchpad -destination 'platform=macOS' test"))
    }
}
```

- [ ] **Step 2: Run the new warning and CI policy tests and observe failure**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/RecoveryContainmentTests/testProjectTreatsSwiftWarningsAsErrors -only-testing:ScratchpadTests/RecoveryContainmentTests/testCIUsesProjectDeploymentTargetWithoutOverride test
```

Expected: both selected tests fail. `project.yml` lacks `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES`, and CI contains `MACOSX_DEPLOYMENT_TARGET=15.0`.

- [ ] **Step 3: Make Swift warnings fatal in `project.yml`**

Add this exact setting under `settings.base`, alongside the Swift version and concurrency settings:

```yaml
    SWIFT_TREAT_WARNINGS_AS_ERRORS: YES
```

- [ ] **Step 4: Replace `.github/workflows/ci.yml`**

```yaml
name: CI
on: [push, pull_request]
jobs:
  build-test:
    runs-on: macos-latest
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

- [ ] **Step 5: Run the focused policy suite**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/RecoveryContainmentTests test
```

Expected: all 6 containment and policy tests pass.

- [ ] **Step 6: Run the full Stage 0 verification**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
git diff --check
```

Expected: generation succeeds; build succeeds with warnings treated as errors; all 7 tests pass; whitespace validation exits 0.

- [ ] **Step 7: Record and commit Task 0.3**

Set Task 0.3 to `verified` in `TRACKER.md` with the two failing tests, focused passing suite, full build, full test, and whitespace evidence, then run:

```sh
git add project.yml .github/workflows/ci.yml ScratchpadTests/RecoveryContainmentTests.swift TRACKER.md
git commit -m "chore: enforce recovery build policy"
```

Expected: one policy commit; no prototype implementation file changes.

## Stage 0 Approval Gate

After Tasks 0.1–0.3 are verified, stop. Do not begin Stage 1. Present this matrix with fresh evidence from the execution commits:

| Acceptance check | Required result |
|---|---|
| Prototype preservation | `a1f36f6` is documented; the prototype implementation directories have no diff from that revision |
| Active source boundary | Generated project contains `RecoveryBaseline` and no prototype implementation source |
| Deferred surface removal | Launched app exposes no tabs, sidebar, workspace, Quick Open, Zen, hotkey, highlighting, or settings |
| Warning policy | `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES`; local build succeeds |
| Test policy | 7 Stage 0 tests pass |
| Dependency policy | no XcodeGen `packages` declaration and no third-party runtime dependency |
| Network policy | no client or server network entitlement |
| CI parity | CI invokes the same build and test commands without overriding deployment target |
| Working tree | `git status --short` is empty after the three task commits |

The user must explicitly approve Stage 0 before `AGENTS.md` and `TRACKER.md` advance to Recovery Stage 1.

---

# Gate 4B — Recovery Stage 1: Document and Editor Core

## Stage Goal

Build one observable `DocumentSession` that exclusively owns one `NSTextStorage`, attach it once to an `NSTextView` running TextKit 2, and prove text identity, dirty state, generation, selection, scroll, native editing, and undo before adding custom commands or persistence.

Stage 1 deliberately has no New, Open, Save, recovery, settings, metrics, custom commands, or visual polish. Its deliverable is a single untitled editor whose native text-system behavior is trustworthy.

## Stage 1 File Map

**Create**

- `Scratchpad/App/ApplicationModel.swift` — root observable state with exactly one document.
- `Scratchpad/Document/DocumentState.swift` — save, line-ending, replacement-source, and selection values.
- `Scratchpad/Document/DocumentSnapshot.swift` — immutable cross-actor text snapshot.
- `Scratchpad/Document/DocumentSession.swift` — sole owner of live `NSTextStorage` and document metadata.
- `Scratchpad/Editor/EditorHost.swift` — SwiftUI/AppKit construction and identity boundary.
- `Scratchpad/Editor/ScratchTextView.swift` — native text view subclass and future responder-action home.
- `Scratchpad/Files/FileModels.swift` — stable external-file identifier required by document metadata.
- `ScratchpadTests/App/ApplicationModelTests.swift`
- `ScratchpadTests/Document/DocumentStateTests.swift`
- `ScratchpadTests/Document/DocumentSessionTests.swift`
- `ScratchpadTests/Editor/EditorHostTests.swift`
- `ScratchpadTests/Editor/EditorCoordinatorTests.swift`
- `ScratchpadTests/RecoveryProjectPolicyTests.swift`

**Replace**

- `Scratchpad/App/ScratchpadApp.swift`
- `Scratchpad/App/MainWindowView.swift`
- `Scratchpad/Editor/EditorCoordinator.swift`

**Delete after their replacements pass**

- `Scratchpad/RecoveryBaseline/`
- `Scratchpad/App/AppModel.swift`
- `Scratchpad/App/AppCommands.swift`
- `Scratchpad/App/AppDelegate.swift`
- `Scratchpad/App/SessionService.swift`
- `Scratchpad/Editor/BufferStore.swift`
- `Scratchpad/Editor/EditorTextView.swift`
- `Scratchpad/Editor/HighlightApplier.swift`
- `Scratchpad/Editor/MarkdownTokenizer.swift`
- `ScratchpadTests/RecoveryContainmentTests.swift`

**Modify**

- `project.yml` — extend the explicit allowlists only with Stage 1 files.
- `TRACKER.md` — record task and approval evidence.

## Stage 1 Interfaces

```swift
@MainActor
@Observable
final class DocumentSession {
    let id: UUID
    let storage: NSTextStorage
    private(set) var fileReference: ExternalFileReference?
    private(set) var displayName: String
    private(set) var saveState: DocumentSaveState
    private(set) var generation: Int
    private(set) var lastSavedHash: String?
    private(set) var lastKnownDiskMTime: Date?
    private(set) var lineEnding: LineEnding
    private(set) var selection: TextSelection
    private(set) var scrollOffsetY: Double

    func replaceEntireContents(
        _ text: String,
        source: WholeTextReplacementSource,
        selection: TextSelection?
    )
    func noteUserEdit()
    func updateSelection(_ selection: TextSelection)
    func updateScrollOffset(_ offset: Double)
    func snapshot() -> DocumentSnapshot
}

@MainActor
struct EditorHost: NSViewRepresentable {
    let document: DocumentSession
    var onEdit: @MainActor (DocumentSession) -> Void
}
```

### Task 1.1: Define Document Values and Snapshot Boundaries

**Files:**

- Create: `Scratchpad/Document/DocumentState.swift`
- Create: `Scratchpad/Document/DocumentSnapshot.swift`
- Create: `Scratchpad/Files/FileModels.swift`
- Create: `ScratchpadTests/Document/DocumentStateTests.swift`
- Modify: `project.yml`
- Modify: `TRACKER.md`

**Interfaces:**

- Consumes: only Foundation value types.
- Produces: `DocumentSaveState`, `LineEnding`, `WholeTextReplacementSource`, `TextSelection`, `ExternalFileReference`, and `DocumentSnapshot` with the exact signatures used by all later stages.

- [ ] **Step 1: Add the test path to the test allowlist and write the failing tests**

Add this source under `ScratchpadTests.sources` in `project.yml`:

```yaml
      - ScratchpadTests/Document/DocumentStateTests.swift
```

Create `ScratchpadTests/Document/DocumentStateTests.swift`:

```swift
import Foundation
import XCTest
@testable import Scratchpad

final class DocumentStateTests: XCTestCase {
    func testSelectionClampsToUTF16Bounds() {
        let selection = TextSelection(location: 1, length: 20)
        XCTAssertEqual(
            selection.clamped(toUTF16Length: 2),
            TextSelection(location: 1, length: 1)
        )
        XCTAssertEqual(
            TextSelection(location: -4, length: -2).clamped(toUTF16Length: 2),
            TextSelection(location: 0, length: 0)
        )
    }

    func testPersistedDocumentValuesRoundTrip() throws {
        let reference = ExternalFileReference(
            bookmarkID: UUID(),
            pathHint: "/Users/example/prompt.md"
        )
        let encoded = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(ExternalFileReference.self, from: encoded)

        XCTAssertEqual(decoded, reference)
        XCTAssertEqual(DocumentSaveState.edited.rawValue, "edited")
        XCTAssertEqual(LineEnding.crlf.rawValue, "crlf")
    }
}
```

- [ ] **Step 2: Run the focused test and observe failure**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/DocumentStateTests test
```

Expected: compilation fails because `TextSelection`, `ExternalFileReference`, `DocumentSaveState`, and `LineEnding` do not exist.

- [ ] **Step 3: Create `Scratchpad/Document/DocumentState.swift`**

```swift
import Foundation

enum DocumentSaveState: String, Codable, Equatable, Sendable {
    case untitled
    case edited
    case clean
    case conflicted
    case deleted
    case readOnly
}

enum LineEnding: String, Codable, Equatable, Sendable {
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

    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    func clamped(toUTF16Length textLength: Int) -> Self {
        let safeTextLength = max(0, textLength)
        let safeLocation = min(max(0, location), safeTextLength)
        let remainingLength = safeTextLength - safeLocation
        let safeLength = min(max(0, length), remainingLength)
        return Self(location: safeLocation, length: safeLength)
    }
}
```

- [ ] **Step 4: Create `Scratchpad/Files/FileModels.swift`**

```swift
import Foundation

struct ExternalFileReference: Codable, Equatable, Sendable {
    let bookmarkID: UUID
    let pathHint: String
}
```

- [ ] **Step 5: Create `Scratchpad/Document/DocumentSnapshot.swift`**

```swift
import Foundation

struct DocumentSnapshot: Sendable {
    let documentID: UUID
    let generation: Int
    let text: String
    let fileReference: ExternalFileReference?
    let saveState: DocumentSaveState
    let selection: TextSelection
    let scrollOffsetY: Double
    let lineEnding: LineEnding
    let lastSavedHash: String?
    let lastKnownDiskMTime: Date?
}
```

- [ ] **Step 6: Add the value sources to the app allowlist**

Add these entries under `Scratchpad.sources` in `project.yml`:

```yaml
      - path: Scratchpad/Document/DocumentState.swift
      - path: Scratchpad/Document/DocumentSnapshot.swift
      - path: Scratchpad/Files/FileModels.swift
```

- [ ] **Step 7: Run focused and full verification**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/DocumentStateTests test
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
```

Expected: 2 focused tests pass; the warning-free containment build and all 9 tests pass.

- [ ] **Step 8: Record and commit Task 1.1**

```sh
git add project.yml Scratchpad/Document Scratchpad/Files/FileModels.swift ScratchpadTests/Document/DocumentStateTests.swift TRACKER.md
git commit -m "feat: define document state boundaries"
```

### Task 1.2: Implement Single-Owner DocumentSession

**Files:**

- Create: `Scratchpad/Document/DocumentSession.swift`
- Create: `ScratchpadTests/Document/DocumentSessionTests.swift`
- Modify: `project.yml`
- Modify: `TRACKER.md`

**Interfaces:**

- Consumes: all Task 1.1 values.
- Produces: the sole live-text owner, sanctioned whole-text replacement, edit transitions, validated selection/scroll metadata, and immutable snapshots.

- [ ] **Step 1: Add the test path and write the failing session tests**

Add `ScratchpadTests/Document/DocumentSessionTests.swift` to the test allowlist, then create it:

```swift
import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class DocumentSessionTests: XCTestCase {
    func testEachSessionOwnsDistinctTextStorage() {
        let first = DocumentSession(text: "first")
        let second = DocumentSession(text: "second")

        XCTAssertFalse(first.storage === second.storage)
        first.storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "changed")
        XCTAssertEqual(first.storage.string, "changed")
        XCTAssertEqual(second.storage.string, "second")
    }

    func testUserEditIncrementsGenerationOnceAndMarksEditableStatesEdited() {
        let untitled = DocumentSession(text: "draft")
        untitled.noteUserEdit()
        XCTAssertEqual(untitled.generation, 1)
        XCTAssertEqual(untitled.saveState, .edited)

        let conflicted = DocumentSession(text: "draft", saveState: .conflicted)
        conflicted.noteUserEdit()
        XCTAssertEqual(conflicted.generation, 1)
        XCTAssertEqual(conflicted.saveState, .conflicted)
    }

    func testWholeReplacementIsSanctionedAndClampsSelection() {
        let document = DocumentSession(text: "long text", saveState: .edited)
        document.replaceEntireContents(
            "hi",
            source: .confirmedDiskReload,
            selection: TextSelection(location: 8, length: 4)
        )

        XCTAssertEqual(document.storage.string, "hi")
        XCTAssertEqual(document.generation, 1)
        XCTAssertEqual(document.saveState, .clean)
        XCTAssertEqual(document.selection, TextSelection(location: 2, length: 0))
        XCTAssertFalse(document.isPerformingWholeTextReplacement)
    }

    func testSnapshotCopiesTextAndMetadata() {
        let id = UUID()
        let document = DocumentSession(
            id: id,
            text: "snapshot",
            displayName: "Prompt",
            saveState: .edited,
            generation: 7,
            lineEnding: .crlf,
            selection: TextSelection(location: 2, length: 3),
            scrollOffsetY: 44
        )

        let snapshot = document.snapshot()
        document.storage.append(NSAttributedString(string: " changed"))

        XCTAssertEqual(snapshot.documentID, id)
        XCTAssertEqual(snapshot.text, "snapshot")
        XCTAssertEqual(snapshot.generation, 7)
        XCTAssertEqual(snapshot.selection, TextSelection(location: 2, length: 3))
        XCTAssertEqual(snapshot.scrollOffsetY, 44)
        XCTAssertEqual(snapshot.lineEnding, .crlf)
    }
}
```

- [ ] **Step 2: Run the focused test and observe failure**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/DocumentSessionTests test
```

Expected: compilation fails because `DocumentSession` does not exist.

- [ ] **Step 3: Create `Scratchpad/Document/DocumentSession.swift`**

```swift
import AppKit
import Observation

@MainActor
@Observable
final class DocumentSession {
    let id: UUID
    let storage: NSTextStorage

    private(set) var fileReference: ExternalFileReference?
    private(set) var displayName: String
    private(set) var saveState: DocumentSaveState
    private(set) var generation: Int
    private(set) var lastSavedHash: String?
    private(set) var lastKnownDiskMTime: Date?
    private(set) var lineEnding: LineEnding
    private(set) var selection: TextSelection
    private(set) var scrollOffsetY: Double
    private(set) var isPerformingWholeTextReplacement = false

    init(
        id: UUID = UUID(),
        text: String = "",
        fileReference: ExternalFileReference? = nil,
        displayName: String = "Untitled",
        saveState: DocumentSaveState = .untitled,
        generation: Int = 0,
        lastSavedHash: String? = nil,
        lastKnownDiskMTime: Date? = nil,
        lineEnding: LineEnding = .lf,
        selection: TextSelection = TextSelection(location: 0, length: 0),
        scrollOffsetY: Double = 0
    ) {
        self.id = id
        self.storage = NSTextStorage(string: text)
        self.fileReference = fileReference
        self.displayName = displayName
        self.saveState = saveState
        self.generation = generation
        self.lastSavedHash = lastSavedHash
        self.lastKnownDiskMTime = lastKnownDiskMTime
        self.lineEnding = lineEnding
        self.selection = selection.clamped(toUTF16Length: self.storage.length)
        self.scrollOffsetY = max(0, scrollOffsetY)
    }

    func replaceEntireContents(
        _ text: String,
        source: WholeTextReplacementSource,
        selection replacementSelection: TextSelection?
    ) {
        isPerformingWholeTextReplacement = true
        defer { isPerformingWholeTextReplacement = false }

        storage.beginEditing()
        storage.replaceCharacters(
            in: NSRange(location: 0, length: storage.length),
            with: text
        )
        storage.endEditing()
        generation += 1
        selection = (replacementSelection ?? selection)
            .clamped(toUTF16Length: storage.length)

        switch source {
        case .initialUntitled:
            fileReference = nil
            displayName = "Untitled"
            saveState = .untitled
            lastSavedHash = nil
            lastKnownDiskMTime = nil
        case .fileOpen, .confirmedDiskReload:
            saveState = .clean
        case .sessionRestore:
            break
        }
    }

    func noteUserEdit() {
        generation += 1
        if saveState == .untitled || saveState == .clean {
            saveState = .edited
        }
    }

    func updateSelection(_ newSelection: TextSelection) {
        selection = newSelection.clamped(toUTF16Length: storage.length)
    }

    func updateScrollOffset(_ offset: Double) {
        scrollOffsetY = max(0, offset)
    }

    func snapshot() -> DocumentSnapshot {
        DocumentSnapshot(
            documentID: id,
            generation: generation,
            text: storage.string,
            fileReference: fileReference,
            saveState: saveState,
            selection: selection,
            scrollOffsetY: scrollOffsetY,
            lineEnding: lineEnding,
            lastSavedHash: lastSavedHash,
            lastKnownDiskMTime: lastKnownDiskMTime
        )
    }
}
```

- [ ] **Step 4: Add `DocumentSession.swift` to the app allowlist**

```yaml
      - path: Scratchpad/Document/DocumentSession.swift
```

- [ ] **Step 5: Run focused and full verification**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/DocumentSessionTests test
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
```

Expected: 4 session tests pass; warning-free build; all 13 tests pass.

- [ ] **Step 6: Record and commit Task 1.2**

```sh
git add project.yml Scratchpad/Document/DocumentSession.swift ScratchpadTests/Document/DocumentSessionTests.swift TRACKER.md
git commit -m "feat: add single-owner document session"
```

### Task 1.3: Attach Document Storage to TextKit 2 Exactly Once

**Files:**

- Create: `Scratchpad/Editor/EditorHost.swift`
- Create: `Scratchpad/Editor/ScratchTextView.swift`
- Replace: `Scratchpad/Editor/EditorCoordinator.swift`
- Create: `ScratchpadTests/Editor/EditorHostTests.swift`
- Modify: `project.yml`
- Modify: `TRACKER.md`

**Interfaces:**

- Consumes: `DocumentSession.storage` and `DocumentSession.id`.
- Produces: an identity-checked TextKit 2 assembly. `NSTextContentStorage.textStorage` is the only attachment point; neither implementation nor tests evaluate `layoutManager`.

- [ ] **Step 1: Add the test path and write failing TextKit 2 integration tests**

Create `ScratchpadTests/Editor/EditorHostTests.swift`:

```swift
import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class EditorHostTests: XCTestCase {
    private func textView(in scrollView: NSScrollView) throws -> ScratchTextView {
        guard let textView = scrollView.documentView as? ScratchTextView else {
            throw EditorHostTestError.missingTextView
        }
        return textView
    }

    func testHostUsesTextKit2AndSessionStorage() throws {
        let document = DocumentSession(text: "alpha")
        let coordinator = EditorCoordinator(document: document, onEdit: { _ in })
        let scrollView = EditorHost.makeScrollView(
            document: document,
            coordinator: coordinator
        )
        let textView = try textView(in: scrollView)

        XCTAssertNotNil(textView.textLayoutManager)
        XCTAssertTrue(textView.textStorage === document.storage)
        XCTAssertEqual(textView.string, "alpha")
    }

    func testSeparateHostsCannotShareOrCrossEditStorage() throws {
        let first = DocumentSession(text: "first")
        let second = DocumentSession(text: "second")
        let firstView = try textView(in: EditorHost.makeScrollView(
            document: first,
            coordinator: EditorCoordinator(document: first, onEdit: { _ in })
        ))
        let secondView = try textView(in: EditorHost.makeScrollView(
            document: second,
            coordinator: EditorCoordinator(document: second, onEdit: { _ in })
        ))

        firstView.insertText("!", replacementRange: NSRange(location: 5, length: 0))

        XCTAssertTrue(firstView.textStorage === first.storage)
        XCTAssertTrue(secondView.textStorage === second.storage)
        XCTAssertEqual(first.storage.string, "first!")
        XCTAssertEqual(second.storage.string, "second")
    }
}

private enum EditorHostTestError: Error {
    case missingTextView
}
```

Add the test file to the explicit test allowlist.

- [ ] **Step 2: Run the focused tests and observe failure**

Expected: compilation fails because `ScratchTextView`, the new `EditorCoordinator` initializer, and `EditorHost.makeScrollView` do not exist.

- [ ] **Step 3: Create `Scratchpad/Editor/ScratchTextView.swift`**

```swift
import AppKit

@MainActor
final class ScratchTextView: NSTextView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            window.makeFirstResponder(self)
        }
    }
}
```

- [ ] **Step 4: Replace `Scratchpad/Editor/EditorCoordinator.swift` with the identity shell**

```swift
import AppKit

@MainActor
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    let documentID: UUID
    private weak var document: DocumentSession?
    private let onEdit: @MainActor (DocumentSession) -> Void

    init(
        document: DocumentSession,
        onEdit: @escaping @MainActor (DocumentSession) -> Void
    ) {
        self.documentID = document.id
        self.document = document
        self.onEdit = onEdit
    }
}
```

- [ ] **Step 5: Create `Scratchpad/Editor/EditorHost.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
struct EditorHost: NSViewRepresentable {
    let document: DocumentSession
    var onEdit: @MainActor (DocumentSession) -> Void = { _ in }

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(document: document, onEdit: onEdit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(document: document, coordinator: context.coordinator)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        precondition(context.coordinator.documentID == document.id)
        guard let textView = scrollView.documentView as? ScratchTextView else {
            preconditionFailure("EditorHost lost its ScratchTextView")
        }
        precondition(textView.textLayoutManager != nil)
        precondition(textView.textStorage === document.storage)
    }

    static func makeScrollView(
        document: DocumentSession,
        coordinator: EditorCoordinator
    ) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = ScratchTextView(usingTextLayoutManager: true)
        guard let contentStorage = textView.textContentStorage else {
            preconditionFailure("TextKit 2 content storage is unavailable")
        }
        guard let textContainer = textView.textContainer else {
            preconditionFailure("TextKit 2 text container is unavailable")
        }

        contentStorage.textStorage = document.storage
        precondition(textView.textLayoutManager != nil)
        precondition(textView.textStorage === document.storage)

        textView.delegate = coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.frame = scrollView.contentView.bounds
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: .greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(
            width: 0,
            height: .greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }
}
```

- [ ] **Step 6: Add only the three new editor files to the app allowlist**

```yaml
      - path: Scratchpad/Editor/EditorCoordinator.swift
      - path: Scratchpad/Editor/EditorHost.swift
      - path: Scratchpad/Editor/ScratchTextView.swift
```

Do not add the `Scratchpad/Editor` directory recursively; it still contains excluded prototype files at this task boundary.

- [ ] **Step 7: Run focused tests and the TextKit 1 forbidden-access scan**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/EditorHostTests test
```

Then run:

```sh
rg '\.layoutManager' Scratchpad/Editor/EditorHost.swift Scratchpad/Editor/ScratchTextView.swift Scratchpad/Editor/EditorCoordinator.swift
```

Expected: 2 editor-host tests pass. The scan finds no matches and exits 1.

- [ ] **Step 8: Run full verification and commit**

Expected: warning-free build; all 15 tests pass.

```sh
git add project.yml Scratchpad/Editor/EditorCoordinator.swift Scratchpad/Editor/EditorHost.swift Scratchpad/Editor/ScratchTextView.swift ScratchpadTests/Editor/EditorHostTests.swift TRACKER.md
git commit -m "feat: attach document storage to TextKit 2"
```

### Task 1.4: Synchronize Native Edits, Selection, Scroll, and Undo

**Files:**

- Modify: `Scratchpad/Editor/EditorCoordinator.swift`
- Modify: `Scratchpad/Editor/EditorHost.swift`
- Create: `ScratchpadTests/Editor/EditorCoordinatorTests.swift`
- Modify: `project.yml`
- Modify: `TRACKER.md`

**Interfaces:**

- Consumes: the fixed document identity and TextKit 2 assembly from Tasks 1.2–1.3.
- Produces: one metadata update per native edit, selection and scroll capture, programmatic-replacement suppression, and native undo evidence.

- [ ] **Step 1: Add the test path and write failing coordinator tests**

Create `ScratchpadTests/Editor/EditorCoordinatorTests.swift`:

```swift
import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class EditorCoordinatorTests: XCTestCase {
    private func assembly(
        text: String = "alpha",
        onEdit: @escaping @MainActor (DocumentSession) -> Void
    ) throws -> (DocumentSession, EditorCoordinator, NSWindow, NSScrollView, ScratchTextView) {
        let document = DocumentSession(text: text)
        let coordinator = EditorCoordinator(document: document, onEdit: onEdit)
        let scrollView = EditorHost.makeScrollView(
            document: document,
            coordinator: coordinator
        )
        guard let textView = scrollView.documentView as? ScratchTextView else {
            throw EditorCoordinatorTestError.missingTextView
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        return (document, coordinator, window, scrollView, textView)
    }

    func testNativeEditNotifiesOnceAndParticipatesInUndo() throws {
        var editCount = 0
        let (document, _, _, _, textView) = try assembly { _ in editCount += 1 }

        textView.insertText("!", replacementRange: NSRange(location: 5, length: 0))

        XCTAssertEqual(document.storage.string, "alpha!")
        XCTAssertEqual(document.generation, 1)
        XCTAssertEqual(document.saveState, .edited)
        XCTAssertEqual(editCount, 1)
        guard let undoManager = textView.undoManager else {
            XCTFail("NSTextView must provide an undo manager")
            return
        }
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        XCTAssertEqual(document.storage.string, "alpha")
    }

    func testSelectionAndScrollAreCapturedAndClamped() throws {
        let (document, coordinator, _, scrollView, textView) = try assembly { _ in }
        textView.setSelectedRange(NSRange(location: 2, length: 2))
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 42))
        coordinator.clipViewBoundsDidChange(
            Notification(name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        )

        XCTAssertEqual(document.selection, TextSelection(location: 2, length: 2))
        XCTAssertEqual(document.scrollOffsetY, 42)
    }

    func testWholeReplacementDoesNotEmitUserEditCallback() throws {
        var editCount = 0
        let (document, _, _, _, _) = try assembly { _ in editCount += 1 }

        document.replaceEntireContents(
            "restored",
            source: .sessionRestore,
            selection: TextSelection(location: 3, length: 0)
        )

        XCTAssertEqual(document.generation, 1)
        XCTAssertEqual(document.selection, TextSelection(location: 3, length: 0))
        XCTAssertEqual(editCount, 0)
    }
}

private enum EditorCoordinatorTestError: Error {
    case missingTextView
}
```

- [ ] **Step 2: Run focused tests and observe failure**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/EditorCoordinatorTests test
```

Expected: compilation fails because `clipViewBoundsDidChange` and the coordinator delegate behavior do not exist; if compilation proceeds, edit-count and metadata assertions fail.

- [ ] **Step 3: Replace `Scratchpad/Editor/EditorCoordinator.swift`**

```swift
import AppKit

@MainActor
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    let documentID: UUID
    private weak var document: DocumentSession?
    private let onEdit: @MainActor (DocumentSession) -> Void

    init(
        document: DocumentSession,
        onEdit: @escaping @MainActor (DocumentSession) -> Void
    ) {
        self.documentID = document.id
        self.document = document
        self.onEdit = onEdit
    }

    func attach(to scrollView: NSScrollView, textView: ScratchTextView) {
        textView.delegate = self
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    func detach() {
        NotificationCenter.default.removeObserver(self)
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              let document,
              textView.textStorage === document.storage else { return }

        document.updateSelection(TextSelection(textView.selectedRange()))
        guard !document.isPerformingWholeTextReplacement else { return }
        document.noteUserEdit()
        onEdit(document)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              let document,
              textView.textStorage === document.storage else { return }
        document.updateSelection(TextSelection(textView.selectedRange()))
    }

    @objc
    func clipViewBoundsDidChange(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView,
              let document else { return }
        document.updateScrollOffset(clipView.bounds.origin.y)
    }
}
```

- [ ] **Step 4: Update the EditorHost lifecycle**

In `makeScrollView`, replace `textView.delegate = coordinator` with:

```swift
        coordinator.attach(to: scrollView, textView: textView)
        textView.setSelectedRange(document.selection.nsRange)
        scrollView.contentView.scroll(
            to: NSPoint(x: 0, y: document.scrollOffsetY)
        )
```

Add this method to `EditorHost`:

```swift
    static func dismantleNSView(
        _ scrollView: NSScrollView,
        coordinator: EditorCoordinator
    ) {
        coordinator.detach()
        if let textView = scrollView.documentView as? ScratchTextView {
            textView.delegate = nil
        }
    }
```

- [ ] **Step 5: Run focused tests**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/EditorCoordinatorTests test
```

Expected: all 3 coordinator tests pass, including native undo and exactly one callback for the insertion.

- [ ] **Step 6: Run full verification and commit**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
rg '\.layoutManager' Scratchpad/Editor/EditorHost.swift Scratchpad/Editor/ScratchTextView.swift Scratchpad/Editor/EditorCoordinator.swift
```

Expected: warning-free build; all 18 tests pass; the `.layoutManager` scan has no matches and exits 1.

```sh
git add project.yml Scratchpad/Editor/EditorCoordinator.swift Scratchpad/Editor/EditorHost.swift ScratchpadTests/Editor/EditorCoordinatorTests.swift TRACKER.md
git commit -m "feat: synchronize native editor state"
```

### Task 1.5: Replace the Containment Shell with the Single Editor

**Files:**

- Create: `Scratchpad/App/ApplicationModel.swift`
- Replace: `Scratchpad/App/MainWindowView.swift`
- Replace: `Scratchpad/App/ScratchpadApp.swift`
- Create: `ScratchpadTests/App/ApplicationModelTests.swift`
- Create: `ScratchpadTests/RecoveryProjectPolicyTests.swift`
- Delete: the obsolete Stage 0 and prototype files listed in the Stage 1 file map.
- Modify: `project.yml`
- Modify: `TRACKER.md`

**Interfaces:**

- Consumes: `DocumentSession` and `EditorHost`.
- Produces: one native application window keyed by `document.id`, one root observable model, and an active target containing only replacement sources.

- [ ] **Step 1: Write the failing root-model test**

Create `ScratchpadTests/App/ApplicationModelTests.swift`:

```swift
import XCTest
@testable import Scratchpad

@MainActor
final class ApplicationModelTests: XCTestCase {
    func testModelOwnsExactlyTheInjectedDocument() {
        let document = DocumentSession(text: "owned")
        let model = ApplicationModel(document: document)

        XCTAssertTrue(model.document === document)
        XCTAssertEqual(model.document.storage.string, "owned")
    }
}
```

Add the test path to the allowlist and run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/ApplicationModelTests test
```

Expected: compilation fails because `ApplicationModel` does not exist.

- [ ] **Step 2: Create `Scratchpad/App/ApplicationModel.swift`**

```swift
import Observation

@MainActor
@Observable
final class ApplicationModel {
    private(set) var document: DocumentSession

    init(document: DocumentSession = DocumentSession()) {
        self.document = document
    }
}
```

- [ ] **Step 3: Replace `Scratchpad/App/MainWindowView.swift`**

```swift
import SwiftUI

struct MainWindowView: View {
    @Environment(ApplicationModel.self) private var model

    var body: some View {
        EditorHost(document: model.document)
            .id(model.document.id)
            .frame(minWidth: 480, minHeight: 320)
    }
}
```

- [ ] **Step 4: Replace `Scratchpad/App/ScratchpadApp.swift`**

```swift
import SwiftUI

@main
struct ScratchpadApp: App {
    @State private var model = ApplicationModel()

    var body: some Scene {
        Window("Untitled", id: "main") {
            MainWindowView()
                .environment(model)
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
    }
}
```

- [ ] **Step 5: Replace the containment policy test with the Stage 1 policy test**

Create `ScratchpadTests/RecoveryProjectPolicyTests.swift`:

```swift
import Foundation
import XCTest

final class RecoveryProjectPolicyTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func testProjectUsesExplicitReplacementSources() throws {
        let project = try contents(at: "project.yml")
        XCTAssertFalse(project.contains("sources: [Scratchpad]"))
        XCTAssertFalse(project.contains("Scratchpad/RecoveryBaseline"))
        XCTAssertTrue(project.contains("Scratchpad/App/ApplicationModel.swift"))
        XCTAssertTrue(project.contains("Scratchpad/Document/DocumentSession.swift"))
        XCTAssertTrue(project.contains("Scratchpad/Editor/EditorHost.swift"))
    }

    func testProjectTreatsSwiftWarningsAsErrors() throws {
        XCTAssertTrue(
            try contents(at: "project.yml")
                .contains("SWIFT_TREAT_WARNINGS_AS_ERRORS: YES")
        )
    }

    func testProjectDeclaresNoRuntimePackages() throws {
        XCTAssertFalse(try contents(at: "project.yml").contains("\npackages:"))
    }

    func testEntitlementsDeclareNoNetworkAccess() throws {
        let entitlements = try contents(at: "Scratchpad/App/Scratchpad.entitlements")
        XCTAssertFalse(entitlements.contains("com.apple.security.network.client"))
        XCTAssertFalse(entitlements.contains("com.apple.security.network.server"))
    }

    func testCIUsesProjectDeploymentTargetWithoutOverride() throws {
        let workflow = try contents(at: ".github/workflows/ci.yml")
        XCTAssertFalse(workflow.contains("MACOSX_DEPLOYMENT_TARGET"))
    }
}
```

Delete `ScratchpadTests/RecoveryContainmentTests.swift` only after this replacement suite passes.

- [ ] **Step 6: Replace `project.yml` source allowlists**

Keep the Stage 0 project settings, app metadata settings, dependency, and scheme. Replace only both `sources` lists with:

```yaml
    sources:
      - path: Scratchpad/App/ApplicationModel.swift
      - path: Scratchpad/App/MainWindowView.swift
      - path: Scratchpad/App/ScratchpadApp.swift
      - path: Scratchpad/Document/DocumentSession.swift
      - path: Scratchpad/Document/DocumentSnapshot.swift
      - path: Scratchpad/Document/DocumentState.swift
      - path: Scratchpad/Editor/EditorCoordinator.swift
      - path: Scratchpad/Editor/EditorHost.swift
      - path: Scratchpad/Editor/ScratchTextView.swift
      - path: Scratchpad/Files/FileModels.swift
      - path: Scratchpad/Assets.xcassets
```

Use this complete test allowlist:

```yaml
    sources:
      - ScratchpadTests/SmokeTests.swift
      - ScratchpadTests/RecoveryProjectPolicyTests.swift
      - ScratchpadTests/App/ApplicationModelTests.swift
      - ScratchpadTests/Document/DocumentStateTests.swift
      - ScratchpadTests/Document/DocumentSessionTests.swift
      - ScratchpadTests/Editor/EditorHostTests.swift
      - ScratchpadTests/Editor/EditorCoordinatorTests.swift
```

- [ ] **Step 7: Delete the superseded files**

Delete exactly the paths listed under “Delete after their replacements pass” in the Stage 1 file map. Preserve `Scratchpad/App/Info.plist`, `Scratchpad/App/Scratchpad.entitlements`, the asset catalog, and all prototype sources not explicitly listed for deletion.

- [ ] **Step 8: Run automated Stage 1 verification**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
rg '\.layoutManager' Scratchpad/Editor/EditorHost.swift Scratchpad/Editor/ScratchTextView.swift Scratchpad/Editor/EditorCoordinator.swift
rg 'AppModel.swift|BufferStore.swift|EditorTextView.swift|HighlightApplier.swift|MarkdownTokenizer.swift|RecoveryBaseline' Scratchpad.xcodeproj/project.pbxproj
git diff --check
```

Expected: warning-free build; all 18 tests pass; each `rg` command finds no matches and exits 1; whitespace check exits 0.

- [ ] **Step 9: Run the Stage 1 manual matrix**

Launch a deterministic build:

```sh
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -derivedDataPath /tmp/ScratchpadStage1 build
open /tmp/ScratchpadStage1/Build/Products/Debug/Scratchpad.app
```

Verify:

1. One 820 × 640 window opens with one empty editor and no containment message or deferred surface.
2. The insertion point is active without clicking.
3. Type `alpha`, select `ph`, copy, paste, undo, and redo using native commands.
4. Enter marked text with an installed input method if available; composition remains native.
5. Open the native find bar with `⌘F`, search for `alpha`, and close it.
6. Paste at least 200 lines, scroll, select text, and continue typing without selection jumps.
7. Resize to the 480 × 320 minimum and back; text wraps and scroll remains stable.
8. No tab bar, sidebar, line numbers, syntax highlighting, Quick Open, Zen window, hotkey, or settings UI appears.

- [ ] **Step 10: Record and commit Task 1.5**

Record the root-model failure, passing suite, both forbidden-source scans, build, tests, and all eight manual results in `TRACKER.md`, then commit:

```sh
git add -A
git commit -m "feat: replace containment shell with editor core"
```

Review the staged diff before committing; it must contain only the files enumerated by Task 1.5.

## Stage 1 Approval Gate

After Tasks 1.1–1.5 are `verified`, stop. Do not start custom keybindings. Present fresh evidence for:

| Acceptance check | Required result |
|---|---|
| Text ownership | one `DocumentSession` owns one distinct `NSTextStorage`; SwiftUI owns no text copy |
| TextKit engine | `textLayoutManager` is non-nil and active editor files contain no `.layoutManager` access |
| Editor identity | host coordinator ID and attached storage match the current document ID |
| Native editing | typing, marked text, movement, selection, clipboard, find, undo, and redo remain native |
| Edit accounting | each native edit increments generation and invokes the edit callback exactly once |
| Replacement suppression | file/restore-style whole replacements do not masquerade as user edits |
| Selection and scroll | both update, clamp safely, and remain stable through typing and resize |
| Source boundary | generated project contains replacement files and no deleted prototype/containment source |
| Automated gate | warning-free build and 18 passing tests |
| Manual gate | all eight Stage 1 checks recorded as passing |

The user must explicitly approve Stage 1 before `AGENTS.md` and `TRACKER.md` advance to Recovery Stage 2.

---

# Gate 4C — Recovery Stage 2: Sublime-Style Command System

## Stage Goal

Implement the ten fixed Sublime-style macOS commands as pure UTF-16 transformations, apply them through AppKit's validated text-edit path, and expose them through native responder-chain menu actions. Every text command must fire once, preserve a valid selection, create one undo operation, and do nothing when the editor is not first responder.

Stage 2 adds no event monitor, custom shortcut preferences, keybinding file, command palette, Zen command, or global hotkey.

## Stage 2 File Map

**Create**

- `Scratchpad/Editor/EditorCommand.swift` — command, context, mutation, edit, and outcome values.
- `Scratchpad/Editor/LineTable.swift` — pure CRLF/LF-aware UTF-16 line geometry.
- `Scratchpad/Editor/EditorCommandRouter.swift` — pure command transformations.
- `Scratchpad/App/AppCommands.swift` — fixed menu items and keyboard shortcuts.
- `ScratchpadTests/Editor/LineTableTests.swift`
- `ScratchpadTests/Editor/EditorCommandRouterTests.swift`
- `ScratchpadTests/Editor/ScratchTextViewCommandTests.swift`
- `ScratchpadTests/App/AppCommandsTests.swift`

**Modify**

- `Scratchpad/Editor/ScratchTextView.swift` — responder actions and validated mutation application.
- `Scratchpad/Editor/EditorHost.swift` — provide document line-ending command context.
- `Scratchpad/App/ScratchpadApp.swift` — install `AppCommands`.
- `project.yml` — extend only the explicit Stage 2 allowlists.
- `TRACKER.md` — record task and approval evidence.

## Corrected Command Result Contract

Stage 2 uses the corrected architecture contract:

```swift
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

`selectLine` is selection-only and cannot dirty the document. Multi-line indent, outdent, and join use narrow non-overlapping mutations, preserving attributes on unchanged characters. Mutations are stored in ascending range order and applied in reverse order.

### Task 2.1: Define Command Values and UTF-16 Line Geometry

**Files:** Create `Scratchpad/Editor/EditorCommand.swift`, `Scratchpad/Editor/LineTable.swift`, and `ScratchpadTests/Editor/LineTableTests.swift`; modify `project.yml` and `TRACKER.md`.

**Interfaces:** Produces `EditorCommand`, `EditorCommandContext`, `TextMutation`, `TextEdit`, `EditorCommandOutcome`, `LineRecord`, and `LineTable` for Task 2.2.

- [ ] **Step 1: Add and write the failing line-table tests**

```swift
import Foundation
import XCTest
@testable import Scratchpad

final class LineTableTests: XCTestCase {
    func testParsesLFAndTrailingEmptyLine() {
        let table = LineTable("one\ntwo\n")
        XCTAssertEqual(table.lines.count, 3)
        XCTAssertEqual(table.lines[0].content, NSRange(location: 0, length: 3))
        XCTAssertEqual(table.lines[0].terminator, NSRange(location: 3, length: 1))
        XCTAssertEqual(table.lines[2].full, NSRange(location: 8, length: 0))
    }

    func testTreatsCRLFAsOneTerminator() {
        let table = LineTable("one\r\ntwo")
        XCTAssertEqual(table.lines.count, 2)
        XCTAssertEqual(table.lines[0].terminator, NSRange(location: 3, length: 2))
        XCTAssertEqual(table.lines[1].content, NSRange(location: 5, length: 3))
    }

    func testSelectionEndingAtNextLineStartDoesNotSelectNextLine() {
        let table = LineTable("one\ntwo\nthree")
        XCTAssertEqual(
            table.lineIndices(intersecting: NSRange(location: 0, length: 4)),
            0 ... 0
        )
        XCTAssertEqual(
            table.lineIndices(intersecting: NSRange(location: 1, length: 5)),
            0 ... 1
        )
    }
}
```

Add the test path to `ScratchpadTests.sources`, then run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/LineTableTests test
```

Expected: compilation fails because `LineTable` does not exist.

- [ ] **Step 2: Create `Scratchpad/Editor/EditorCommand.swift`**

```swift
import Foundation

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

struct EditorCommandContext: Equatable, Sendable {
    let lineEnding: LineEnding
    let indentationUnit: String
    let tabWidth: Int
    let keepsIndentation: Bool

    static func defaults(lineEnding: LineEnding) -> Self {
        Self(
            lineEnding: lineEnding,
            indentationUnit: "\t",
            tabWidth: 4,
            keepsIndentation: true
        )
    }

    var newline: String {
        lineEnding == .crlf ? "\r\n" : "\n"
    }
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

- [ ] **Step 3: Create `Scratchpad/Editor/LineTable.swift`**

```swift
import Foundation

struct LineRecord: Equatable, Sendable {
    let content: NSRange
    let terminator: NSRange

    var full: NSRange {
        NSRange(
            location: content.location,
            length: content.length + terminator.length
        )
    }
}

struct LineTable: Sendable {
    let source: String
    let lines: [LineRecord]
    private let utf16Length: Int

    init(_ source: String) {
        self.source = source
        let text = source as NSString
        self.utf16Length = text.length
        var records: [LineRecord] = []
        var lineStart = 0
        var cursor = 0

        while cursor < text.length {
            let unit = text.character(at: cursor)
            guard unit == 10 || unit == 13 else {
                cursor += 1
                continue
            }
            let terminatorLength = unit == 13
                && cursor + 1 < text.length
                && text.character(at: cursor + 1) == 10 ? 2 : 1
            records.append(LineRecord(
                content: NSRange(location: lineStart, length: cursor - lineStart),
                terminator: NSRange(location: cursor, length: terminatorLength)
            ))
            cursor += terminatorLength
            lineStart = cursor
        }

        records.append(LineRecord(
            content: NSRange(location: lineStart, length: text.length - lineStart),
            terminator: NSRange(location: text.length, length: 0)
        ))
        self.lines = records
    }

    func clamped(_ range: NSRange) -> NSRange {
        let location = min(max(0, range.location), utf16Length)
        let length = min(max(0, range.length), utf16Length - location)
        return NSRange(location: location, length: length)
    }

    func lineIndex(containing location: Int) -> Int {
        let safeLocation = min(max(0, location), utf16Length)
        for (index, line) in lines.enumerated() {
            if safeLocation < NSMaxRange(line.full)
                || line.full.length == 0 && safeLocation == line.full.location {
                return index
            }
        }
        return max(0, lines.count - 1)
    }

    func lineIndices(intersecting range: NSRange) -> ClosedRange<Int> {
        let selection = clamped(range)
        let first = lineIndex(containing: selection.location)
        let endProbe = selection.length == 0
            ? selection.location
            : NSMaxRange(selection) - 1
        return first ... lineIndex(containing: endProbe)
    }

    func substring(_ range: NSRange) -> String {
        (source as NSString).substring(with: range)
    }

    func leadingIndentation(at index: Int) -> String {
        let content = substring(lines[index].content) as NSString
        var length = 0
        while length < content.length {
            let unit = content.character(at: length)
            guard unit == 9 || unit == 32 else { break }
            length += 1
        }
        return content.substring(with: NSRange(location: 0, length: length))
    }
}
```

- [ ] **Step 4: Add both editor sources and run verification**

Add the two source paths to `Scratchpad.sources`, then run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/LineTableTests test
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
```

Expected: 3 focused tests and all 21 tests pass with zero warnings.

- [ ] **Step 5: Record and commit**

```sh
git add project.yml Scratchpad/Editor/EditorCommand.swift Scratchpad/Editor/LineTable.swift ScratchpadTests/Editor/LineTableTests.swift TRACKER.md
git commit -m "feat: define editor command geometry"
```

### Task 2.2: Implement and Prove Pure Command Transformations

**Files:** Create `Scratchpad/Editor/EditorCommandRouter.swift` and `ScratchpadTests/Editor/EditorCommandRouterTests.swift`; modify `project.yml` and `TRACKER.md`.

**Interfaces:** Consumes Task 2.1 values. Produces `EditorCommandRouter.outcome(for:text:selection:context:) -> EditorCommandOutcome?`. Returning `nil` means a valid no-op, such as moving the first line up.

- [ ] **Step 1: Write the failing table of all ten commands**

Create tests with this shared helper:

```swift
import Foundation
import XCTest
@testable import Scratchpad

final class EditorCommandRouterTests: XCTestCase {
    private let lf = EditorCommandContext.defaults(lineEnding: .lf)

    private func result(
        _ command: EditorCommand,
        text: String,
        selection: NSRange,
        context: EditorCommandContext? = nil
    ) throws -> (String, NSRange) {
        guard let outcome = EditorCommandRouter.outcome(
            for: command,
            text: text,
            selection: selection,
            context: context ?? lf
        ) else { throw RouterTestError.noOutcome }
        let value: (String, NSRange)
        switch outcome {
        case .selection(let range):
            value = (text, range)
        case .edit(let edit):
            let transformed = NSMutableString(string: text)
            for mutation in edit.mutations.reversed() {
                transformed.replaceCharacters(in: mutation.range, with: mutation.replacementText)
            }
            value = (transformed as String, edit.resultingSelection)
        }
        XCTAssertGreaterThanOrEqual(value.1.location, 0)
        XCTAssertGreaterThanOrEqual(value.1.length, 0)
        XCTAssertLessThanOrEqual(NSMaxRange(value.1), value.0.utf16.count)
        return value
    }

    func testDuplicateLineAndSelection() throws {
        XCTAssertEqual(
            try result(.duplicateLine, text: "one\ntwo", selection: NSRange(location: 1, length: 0)).0,
            "one\none\ntwo"
        )
        XCTAssertEqual(
            try result(.duplicateLine, text: "abc", selection: NSRange(location: 1, length: 1)).0,
            "abbc"
        )
    }

    func testDeleteLineIncludingFinalLineSeparator() throws {
        XCTAssertEqual(
            try result(.deleteLine, text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0)).0,
            "one\nthree"
        )
        XCTAssertEqual(
            try result(.deleteLine, text: "one\ntwo", selection: NSRange(location: 5, length: 0)).0,
            "one"
        )
    }

    func testMoveLinesUp() throws {
        let value = try result(.moveLinesUp, text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(value.0, "two\none\nthree")
        XCTAssertEqual(value.1, NSRange(location: 1, length: 0))
    }

    func testMoveLinesDown() throws {
        let value = try result(.moveLinesDown, text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(value.0, "one\nthree\ntwo")
        XCTAssertEqual(value.1, NSRange(location: 11, length: 0))
    }

    func testSelectLineDoesNotChangeText() throws {
        let value = try result(.selectLine, text: "one\ntwo", selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(value.0, "one\ntwo")
        XCTAssertEqual(value.1, NSRange(location: 4, length: 3))
    }

    func testJoinLinesRemovesNewlineAndLeadingIndentation() throws {
        let value = try result(.joinLines, text: "one\n  two", selection: NSRange(location: 1, length: 0))
        XCTAssertEqual(value.0, "one two")
        XCTAssertEqual(value.1, NSRange(location: 4, length: 0))
    }

    func testIndentUsesNarrowInsertions() throws {
        guard let outcome = EditorCommandRouter.outcome(
            for: .indent,
            text: "a\nb",
            selection: NSRange(location: 0, length: 3),
            context: lf
        ), case .edit(let edit) = outcome else { throw RouterTestError.noOutcome }
        XCTAssertEqual(edit.mutations.map(\.range), [
            NSRange(location: 0, length: 0),
            NSRange(location: 2, length: 0)
        ])
        XCTAssertEqual(try result(.indent, text: "a\nb", selection: NSRange(location: 0, length: 3)).0, "\ta\n\tb")
    }

    func testOutdentRemovesOneTabOrUpToTabWidthSpaces() throws {
        XCTAssertEqual(
            try result(.outdent, text: "\ta\n    b", selection: NSRange(location: 0, length: 8)).0,
            "a\nb"
        )
    }

    func testInsertLineAfterCarriesIndentation() throws {
        let value = try result(.insertLineAfter, text: "  one", selection: NSRange(location: 3, length: 0))
        XCTAssertEqual(value.0, "  one\n  ")
        XCTAssertEqual(value.1, NSRange(location: 8, length: 0))
    }

    func testInsertLineBeforeCarriesIndentation() throws {
        let value = try result(.insertLineBefore, text: "  one", selection: NSRange(location: 3, length: 0))
        XCTAssertEqual(value.0, "  \n  one")
        XCTAssertEqual(value.1, NSRange(location: 2, length: 0))
    }

    func testCRLFCommandsPreserveCRLF() throws {
        let crlf = EditorCommandContext.defaults(lineEnding: .crlf)
        XCTAssertEqual(
            try result(.insertLineAfter, text: "one", selection: NSRange(location: 1, length: 0), context: crlf).0,
            "one\r\n"
        )
    }
}

private enum RouterTestError: Error { case noOutcome }
```

Add the test path, then run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/EditorCommandRouterTests test
```

Expected: compilation fails because the router does not exist.

- [ ] **Step 2: Create `Scratchpad/Editor/EditorCommandRouter.swift`**

Implement the following complete command dispatch and helpers; each handler returns mutations in ascending range order:

```swift
import Foundation

enum EditorCommandRouter {
    static func outcome(
        for command: EditorCommand,
        text: String,
        selection: NSRange,
        context: EditorCommandContext
    ) -> EditorCommandOutcome? {
        let table = LineTable(text)
        let safeSelection = table.clamped(selection)
        switch command {
        case .duplicateLine: return duplicate(table, safeSelection, context)
        case .deleteLine: return delete(table, safeSelection)
        case .moveLinesUp: return move(table, safeSelection, context, direction: -1)
        case .moveLinesDown: return move(table, safeSelection, context, direction: 1)
        case .selectLine:
            let indices = table.lineIndices(intersecting: safeSelection)
            return .selection(covering(indices, in: table))
        case .joinLines: return join(table, safeSelection)
        case .indent: return indent(table, safeSelection, context)
        case .outdent: return outdent(table, safeSelection, context)
        case .insertLineAfter: return insertLine(table, safeSelection, context, before: false)
        case .insertLineBefore: return insertLine(table, safeSelection, context, before: true)
        }
    }

    private static func duplicate(
        _ table: LineTable,
        _ selection: NSRange,
        _ context: EditorCommandContext
    ) -> EditorCommandOutcome? {
        if selection.length > 0 {
            let selected = table.substring(selection)
            return edit(
                [TextMutation(
                    range: NSRange(location: NSMaxRange(selection), length: 0),
                    replacementText: selected
                )],
                NSRange(location: selection.location + selection.length, length: selection.length)
            )
        }
        let index = table.lineIndex(containing: selection.location)
        let line = table.lines[index]
        let column = selection.location - line.content.location
        if line.terminator.length > 0 {
            let original = table.substring(line.full)
            return edit(
                [TextMutation(
                    range: NSRange(location: NSMaxRange(line.full), length: 0),
                    replacementText: original
                )],
                NSRange(location: selection.location + line.full.length, length: 0)
            )
        }
        let content = table.substring(line.content)
        let insertionLocation = NSMaxRange(line.content)
        let replacement = context.newline + content
        let location = insertionLocation
            + context.newline.utf16.count + min(column, line.content.length)
        return edit(
            [TextMutation(
                range: NSRange(location: insertionLocation, length: 0),
                replacementText: replacement
            )],
            NSRange(location: location, length: 0)
        )
    }

    private static func delete(
        _ table: LineTable,
        _ selection: NSRange
    ) -> EditorCommandOutcome? {
        let indices = table.lineIndices(intersecting: selection)
        var range = covering(indices, in: table)
        if range.length == 0 { return nil }
        let last = table.lines[indices.upperBound]
        if indices.upperBound == table.lines.count - 1,
           last.terminator.length == 0,
           indices.lowerBound > 0 {
            let previousTerminator = table.lines[indices.lowerBound - 1].terminator
            range = NSRange(
                location: previousTerminator.location,
                length: NSMaxRange(range) - previousTerminator.location
            )
        }
        return edit(
            [TextMutation(range: range, replacementText: "")],
            NSRange(location: range.location, length: 0)
        )
    }

    private static func move(
        _ table: LineTable,
        _ selection: NSRange,
        _ context: EditorCommandContext,
        direction: Int
    ) -> EditorCommandOutcome? {
        let selected = table.lineIndices(intersecting: selection)
        let neighbor = direction < 0 ? selected.lowerBound - 1 : selected.upperBound + 1
        guard table.lines.indices.contains(neighbor) else { return nil }
        let affected = direction < 0
            ? neighbor ... selected.upperBound
            : selected.lowerBound ... neighbor
        var contents = affected.map { table.substring(table.lines[$0].content) }
        if direction < 0 {
            let first = contents.removeFirst()
            contents.append(first)
        } else {
            let last = contents.removeLast()
            contents.insert(last, at: 0)
        }
        let affectedRange = covering(affected, in: table)
        let hasTrailingTerminator = table.lines[affected.upperBound].terminator.length > 0
        let replacement = contents.joined(separator: context.newline)
            + (hasTrailingTerminator ? context.newline : "")
        let neighborWidth = table.lines[neighbor].content.length + context.newline.utf16.count
        let shiftedLocation = selection.location + (direction < 0 ? -neighborWidth : neighborWidth)
        return edit(
            [TextMutation(range: affectedRange, replacementText: replacement)],
            NSRange(location: max(0, shiftedLocation), length: selection.length)
        )
    }

    private static func join(
        _ table: LineTable,
        _ selection: NSRange
    ) -> EditorCommandOutcome? {
        var indices = table.lineIndices(intersecting: selection)
        if indices.lowerBound == indices.upperBound {
            guard indices.upperBound + 1 < table.lines.count else { return nil }
            indices = indices.lowerBound ... indices.upperBound + 1
        }
        var mutations: [TextMutation] = []
        for index in indices.lowerBound ..< indices.upperBound {
            let current = table.lines[index]
            let next = table.lines[index + 1]
            let indentation = table.leadingIndentation(at: index + 1).utf16.count
            mutations.append(TextMutation(
                range: NSRange(
                    location: current.content.location + current.content.length,
                    length: current.terminator.length + indentation
                ),
                replacementText: " "
            ))
            _ = next
        }
        let caret = table.lines[indices.lowerBound].content.location
            + table.lines[indices.lowerBound].content.length + 1
        return edit(mutations, NSRange(location: caret, length: 0))
    }

    private static func indent(
        _ table: LineTable,
        _ selection: NSRange,
        _ context: EditorCommandContext
    ) -> EditorCommandOutcome? {
        guard !context.indentationUnit.isEmpty else { return nil }
        let indices = table.lineIndices(intersecting: selection)
        let width = context.indentationUnit.utf16.count
        let mutations = indices.map {
            TextMutation(
                range: NSRange(location: table.lines[$0].content.location, length: 0),
                replacementText: context.indentationUnit
            )
        }
        let start = mapInsertionPosition(selection.location, mutations: mutations, width: width)
        let end = mapInsertionPosition(NSMaxRange(selection), mutations: mutations, width: width)
        return edit(mutations, NSRange(location: start, length: max(0, end - start)))
    }

    private static func outdent(
        _ table: LineTable,
        _ selection: NSRange,
        _ context: EditorCommandContext
    ) -> EditorCommandOutcome? {
        let text = table.source as NSString
        let indices = table.lineIndices(intersecting: selection)
        var mutations: [TextMutation] = []
        for index in indices {
            let start = table.lines[index].content.location
            guard table.lines[index].content.length > 0 else { continue }
            var length = 0
            if text.character(at: start) == 9 {
                length = 1
            } else {
                while length < min(context.tabWidth, table.lines[index].content.length),
                      text.character(at: start + length) == 32 {
                    length += 1
                }
            }
            if length > 0 {
                mutations.append(TextMutation(
                    range: NSRange(location: start, length: length),
                    replacementText: ""
                ))
            }
        }
        guard !mutations.isEmpty else { return nil }
        let start = mapRemovalPosition(selection.location, mutations: mutations)
        let end = mapRemovalPosition(NSMaxRange(selection), mutations: mutations)
        return edit(mutations, NSRange(location: start, length: max(0, end - start)))
    }

    private static func insertLine(
        _ table: LineTable,
        _ selection: NSRange,
        _ context: EditorCommandContext,
        before: Bool
    ) -> EditorCommandOutcome? {
        let index = table.lineIndex(containing: selection.location)
        let line = table.lines[index]
        let indentation = context.keepsIndentation ? table.leadingIndentation(at: index) : ""
        if before {
            return edit(
                [TextMutation(range: NSRange(location: line.full.location, length: 0), replacementText: indentation + context.newline)],
                NSRange(location: line.full.location + indentation.utf16.count, length: 0)
            )
        }
        if line.terminator.length > 0 {
            return edit(
                [TextMutation(range: NSRange(location: NSMaxRange(line.full), length: 0), replacementText: indentation + context.newline)],
                NSRange(location: NSMaxRange(line.full) + indentation.utf16.count, length: 0)
            )
        }
        return edit(
            [TextMutation(range: NSRange(location: NSMaxRange(line.content), length: 0), replacementText: context.newline + indentation)],
            NSRange(location: NSMaxRange(line.content) + context.newline.utf16.count + indentation.utf16.count, length: 0)
        )
    }

    private static func covering(
        _ indices: ClosedRange<Int>,
        in table: LineTable
    ) -> NSRange {
        let start = table.lines[indices.lowerBound].full.location
        let end = NSMaxRange(table.lines[indices.upperBound].full)
        return NSRange(location: start, length: end - start)
    }

    private static func edit(
        _ mutations: [TextMutation],
        _ selection: NSRange
    ) -> EditorCommandOutcome {
        .edit(TextEdit(mutations: mutations, resultingSelection: selection))
    }

    private static func mapInsertionPosition(
        _ position: Int,
        mutations: [TextMutation],
        width: Int
    ) -> Int {
        position + mutations.filter { $0.range.location <= position }.count * width
    }

    private static func mapRemovalPosition(
        _ position: Int,
        mutations: [TextMutation]
    ) -> Int {
        position - mutations.reduce(0) { total, mutation in
            total + min(max(0, position - mutation.range.location), mutation.range.length)
        }
    }
}
```

- [ ] **Step 3: Run focused and full verification**

Add the router source and test paths, then run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/EditorCommandRouterTests test
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
```

Expected: 11 router tests and all 32 tests pass with zero warnings.

- [ ] **Step 4: Record and commit**

```sh
git add project.yml Scratchpad/Editor/EditorCommandRouter.swift ScratchpadTests/Editor/EditorCommandRouterTests.swift TRACKER.md
git commit -m "feat: implement Sublime text transformations"
```

### Task 2.3: Apply Commands Through One Undoable AppKit Transaction

**Files:** Modify `Scratchpad/Editor/ScratchTextView.swift` and `Scratchpad/Editor/EditorHost.swift`; create `ScratchpadTests/Editor/ScratchTextViewCommandTests.swift`; modify `project.yml` and `TRACKER.md`.

**Interfaces:** Consumes `EditorCommandOutcome`. Produces ten Objective-C responder actions and `apply(_:)`, which validates all mutations together, applies them in reverse range order, calls `didChangeText()` once, and restores selection.

- [ ] **Step 1: Write four failing AppKit integration tests**

Create `ScratchpadTests/Editor/ScratchTextViewCommandTests.swift`:

```swift
import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class ScratchTextViewCommandTests: XCTestCase {
    private func assembly(
        text: String,
        saveState: DocumentSaveState = .untitled,
        onEdit: @escaping @MainActor (DocumentSession) -> Void = { _ in }
    ) throws -> (DocumentSession, NSWindow, ScratchTextView) {
        let document = DocumentSession(text: text, saveState: saveState)
        let coordinator = EditorCoordinator(document: document, onEdit: onEdit)
        let scrollView = EditorHost.makeScrollView(document: document, coordinator: coordinator)
        guard let textView = scrollView.documentView as? ScratchTextView else {
            throw ScratchCommandTestError.missingTextView
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        return (document, window, textView)
    }

    func testDuplicateActionFiresOnceAndUndoesAsOneOperation() throws {
        var editCount = 0
        let (document, _, textView) = try assembly(text: "one") { _ in editCount += 1 }
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        textView.scratchpadDuplicateLine(nil)

        XCTAssertEqual(document.storage.string, "one\none")
        XCTAssertEqual(document.generation, 1)
        XCTAssertEqual(editCount, 1)
        guard let undoManager = textView.undoManager else {
            XCTFail("window-backed editor requires undo manager")
            return
        }
        undoManager.undo()
        XCTAssertEqual(document.storage.string, "one")
    }

    func testMultiLineIndentPreservesAttributesAndUndoesOnce() throws {
        let attribute = NSAttributedString.Key("ScratchpadCommandTest")
        let (document, _, textView) = try assembly(text: "a\nb")
        document.storage.addAttribute(
            attribute,
            value: true,
            range: NSRange(location: 0, length: document.storage.length)
        )
        textView.setSelectedRange(NSRange(location: 0, length: 3))

        textView.scratchpadIndent(nil)

        XCTAssertEqual(document.storage.string, "\ta\n\tb")
        XCTAssertNotNil(document.storage.attribute(attribute, at: 1, effectiveRange: nil))
        XCTAssertNotNil(document.storage.attribute(attribute, at: 4, effectiveRange: nil))
        guard let undoManager = textView.undoManager else {
            XCTFail("window-backed editor requires undo manager")
            return
        }
        undoManager.undo()
        XCTAssertEqual(document.storage.string, "a\nb")
        XCTAssertFalse(undoManager.canUndo)
    }

    func testSelectLineChangesSelectionWithoutDirtyingDocument() throws {
        let (document, _, textView) = try assembly(text: "one\ntwo", saveState: .clean)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.scratchpadSelectLine(nil)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 3))
        XCTAssertEqual(document.storage.string, "one\ntwo")
        XCTAssertEqual(document.generation, 0)
        XCTAssertEqual(document.saveState, .clean)
        XCTAssertFalse(textView.undoManager?.canUndo ?? false)
    }

    func testEveryTextChangingCommandUndoesInOneOperation() throws {
        let cases: [(String, NSRange, @MainActor (ScratchTextView) -> Void)] = [
            ("one", NSRange(location: 1, length: 0), { $0.scratchpadDuplicateLine(nil) }),
            ("one\ntwo", NSRange(location: 1, length: 0), { $0.scratchpadDeleteLine(nil) }),
            ("one\ntwo", NSRange(location: 5, length: 0), { $0.scratchpadMoveLinesUp(nil) }),
            ("one\ntwo", NSRange(location: 1, length: 0), { $0.scratchpadMoveLinesDown(nil) }),
            ("one\ntwo", NSRange(location: 1, length: 0), { $0.scratchpadJoinLines(nil) }),
            ("one\ntwo", NSRange(location: 0, length: 7), { $0.scratchpadIndent(nil) }),
            ("\tone", NSRange(location: 1, length: 0), { $0.scratchpadOutdent(nil) }),
            ("  one", NSRange(location: 3, length: 0), { $0.scratchpadInsertLineAfter(nil) }),
            ("  one", NSRange(location: 3, length: 0), { $0.scratchpadInsertLineBefore(nil) })
        ]

        for (text, selection, invoke) in cases {
            let (document, _, textView) = try assembly(text: text)
            textView.setSelectedRange(selection)
            invoke(textView)
            XCTAssertNotEqual(document.storage.string, text)
            guard let undoManager = textView.undoManager else {
                XCTFail("window-backed editor requires undo manager")
                return
            }
            undoManager.undo()
            XCTAssertEqual(document.storage.string, text)
            XCTAssertFalse(undoManager.canUndo)
        }
    }
}

private enum ScratchCommandTestError: Error { case missingTextView }
```

The tests invoke actual responder actions and retain their windows for the lifetime of each assertion.

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/ScratchTextViewCommandTests test
```

Expected: compilation fails because the actions do not exist.

- [ ] **Step 2: Replace `Scratchpad/Editor/ScratchTextView.swift` with responder actions**

```swift
import AppKit

@MainActor
final class ScratchTextView: NSTextView {
    var commandContext = EditorCommandContext.defaults(lineEnding: .lf)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { window.makeFirstResponder(self) }
    }

    @objc func scratchpadDuplicateLine(_ sender: Any?) { perform(.duplicateLine) }
    @objc func scratchpadDeleteLine(_ sender: Any?) { perform(.deleteLine) }
    @objc func scratchpadMoveLinesUp(_ sender: Any?) { perform(.moveLinesUp) }
    @objc func scratchpadMoveLinesDown(_ sender: Any?) { perform(.moveLinesDown) }
    @objc func scratchpadSelectLine(_ sender: Any?) { perform(.selectLine) }
    @objc func scratchpadJoinLines(_ sender: Any?) { perform(.joinLines) }
    @objc func scratchpadIndent(_ sender: Any?) { perform(.indent) }
    @objc func scratchpadOutdent(_ sender: Any?) { perform(.outdent) }
    @objc func scratchpadInsertLineAfter(_ sender: Any?) { perform(.insertLineAfter) }
    @objc func scratchpadInsertLineBefore(_ sender: Any?) { perform(.insertLineBefore) }

    private func perform(_ command: EditorCommand) {
        guard let outcome = EditorCommandRouter.outcome(
            for: command,
            text: string,
            selection: selectedRange(),
            context: commandContext
        ) else { return }
        switch outcome {
        case .selection(let selection):
            setSelectedRange(selection)
        case .edit(let edit):
            apply(edit)
        }
    }

    private func apply(_ edit: TextEdit) {
        let ranges = edit.mutations.map { NSValue(range: $0.range) }
        let replacements = edit.mutations.map(\.replacementText)
        guard shouldChangeText(
            inRanges: ranges,
            replacementStrings: replacements
        ) else { return }

        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        for mutation in edit.mutations.reversed() {
            replaceCharacters(in: mutation.range, with: mutation.replacementText)
        }
        setSelectedRange(edit.resultingSelection)
        didChangeText()
    }
}
```

- [ ] **Step 3: Set command context during host construction and update**

In `makeScrollView`, set:

```swift
textView.commandContext = .defaults(lineEnding: document.lineEnding)
```

In `updateNSView`, after identity assertions, set the same value. Stage 4 replaces this default context with values from `SettingsStore`.

- [ ] **Step 4: Run focused and full verification**

Add the test path, then run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/ScratchTextViewCommandTests test
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
```

Expected: 4 focused tests and all 36 tests pass; each text action produces one notification and one undo group, and every text-changing command is restored by one Undo.

- [ ] **Step 5: Record and commit**

```sh
git add project.yml Scratchpad/Editor/ScratchTextView.swift Scratchpad/Editor/EditorHost.swift ScratchpadTests/Editor/ScratchTextViewCommandTests.swift TRACKER.md
git commit -m "feat: apply editor commands through AppKit"
```

### Task 2.4: Route Fixed Shortcuts Through the First Responder

**Files:** Create `Scratchpad/App/AppCommands.swift` and `ScratchpadTests/App/AppCommandsTests.swift`; modify `Scratchpad/App/ScratchpadApp.swift`, `project.yml`, and `TRACKER.md`.

**Interfaces:** Produces native menu commands whose action target is always `nil`, forcing AppKit to begin at the key window's first responder. No command calls a document or storage object directly.

- [ ] **Step 1: Write failing responder-chain tests**

Create `ScratchpadTests/App/AppCommandsTests.swift`:

```swift
import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class AppCommandsTests: XCTestCase {
    private func assembly() throws -> (DocumentSession, NSWindow, ScratchTextView) {
        let document = DocumentSession(text: "one")
        let coordinator = EditorCoordinator(document: document, onEdit: { _ in })
        let scrollView = EditorHost.makeScrollView(document: document, coordinator: coordinator)
        guard let textView = scrollView.documentView as? ScratchTextView else {
            throw AppCommandsTestError.missingTextView
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        return (document, window, textView)
    }

    func testResponderActionReachesFocusedScratchTextViewExactlyOnce() throws {
        let _ = AppCommands()
        let (document, window, textView) = try assembly()
        defer { window.close() }
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(window.makeFirstResponder(textView))

        let handled = NSApp.sendAction(
            #selector(ScratchTextView.scratchpadDuplicateLine(_:)),
            to: nil,
            from: nil
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(document.storage.string, "one\none")
        XCTAssertEqual(document.generation, 1)
    }

    func testResponderActionDoesNotEditWithNonEditorFirstResponder() throws {
        let _ = AppCommands()
        let (document, window, _) = try assembly()
        defer { window.close() }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        window.contentView?.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))

        let handled = NSApp.sendAction(
            #selector(ScratchTextView.scratchpadDuplicateLine(_:)),
            to: nil,
            from: nil
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(document.storage.string, "one")
        XCTAssertEqual(document.generation, 0)
    }
}

private enum AppCommandsTestError: Error { case missingTextView }
```

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/AppCommandsTests test
```

Expected: compilation fails because `AppCommands` does not exist.

- [ ] **Step 2: Create `Scratchpad/App/AppCommands.swift`**

```swift
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
            command("Join Lines", #selector(ScratchTextView.scratchpadJoinLines(_:)), "j", .command)
            command("Indent", #selector(ScratchTextView.scratchpadIndent(_:)), "]", .command)
            command("Outdent", #selector(ScratchTextView.scratchpadOutdent(_:)), "[", .command)
            command("Insert Line After", #selector(ScratchTextView.scratchpadInsertLineAfter(_:)), .return, .command)
            command("Insert Line Before", #selector(ScratchTextView.scratchpadInsertLineBefore(_:)), .return, [.command, .shift])
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
```

- [ ] **Step 3: Install commands in `ScratchpadApp`**

Add:

```swift
.commands { AppCommands() }
```

to the `Window` scene after `.windowResizability(.contentMinSize)`.

- [ ] **Step 4: Add allowlist paths and run automated verification**

Add `AppCommands.swift` and `AppCommandsTests.swift` to their explicit source lists. Run focused tests, build, full tests, and:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -only-testing:ScratchpadTests/AppCommandsTests test
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
rg 'addLocalMonitorForEvents|addGlobalMonitorForEvents|keyDown\(' Scratchpad/App Scratchpad/Editor
```

Expected: 2 focused tests; all 38 tests pass; warning-free build; scan finds no event-monitor or general key interception and exits 1.

- [ ] **Step 5: Run the manual shortcut and undo matrix**

For every shortcut in `SPEC.md`, record: initial text/selection, one invocation, resulting text/selection, one Undo, and restored original. Also verify `⌘Delete`, Option-arrow movement, Option-delete, clipboard, marked-text input, `⌘F`, and Services remain native. Focus a button or menu before invoking each custom menu action and confirm it cannot edit the document.

- [ ] **Step 6: Record and commit**

```sh
git add project.yml Scratchpad/App/AppCommands.swift Scratchpad/App/ScratchpadApp.swift ScratchpadTests/App/AppCommandsTests.swift TRACKER.md
git commit -m "feat: route fixed shortcuts through responders"
```

## Stage 2 Approval Gate

After Tasks 2.1–2.4 are `verified`, stop before recovery or file work. Present fresh evidence for:

| Acceptance check | Required result |
|---|---|
| Command coverage | all ten fixed commands have pure transformation tests |
| Line correctness | LF, CRLF, final lines, empty lines, multi-line selections, and boundary selections pass |
| Selection-only behavior | Select Line changes no text, generation, dirty state, or undo stack |
| Attribute safety | multi-line prefix/join operations touch only their narrow mutation ranges |
| AppKit transaction | all ranges validated together, reverse-applied, one `didChangeText`, one undo group |
| Responder routing | focused editor handles once; non-editor focus handles zero times |
| Native compatibility | native movement, deletion, clipboard, marked text, find, and Services remain intact |
| Monitor prohibition | no local/global monitor or general `keyDown` interception exists |
| Automated gate | warning-free build and 38 passing tests |
| Manual gate | every shortcut result and one-step Undo recorded as passing |

The user must explicitly approve Stage 2 before `AGENTS.md` and `TRACKER.md` advance to Recovery Stage 3.
