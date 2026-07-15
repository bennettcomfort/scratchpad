# Scratchpad Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Plan status:** Gates 4A–4B approved. The implementation lock in `AGENTS.md` remains ON until Gates 4C–4E and the final consistency gate are approved.

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
- Gates 4C–4E: Stages 2–5. Intentionally absent until each section is drafted and approved.
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
