# Scratchpad Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Plan status:** Gate 4A approved. The implementation lock in `AGENTS.md` remains ON until Gates 4B–4E and the final consistency gate are approved.

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
- Gates 4B–4E: Stages 1–5. Intentionally absent until each section is drafted and approved.
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
