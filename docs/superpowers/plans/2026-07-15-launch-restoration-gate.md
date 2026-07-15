# Launch Restoration Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Recovery Task 3.5 with ordered latest-text persistence and a production launch gate that exposes the editor only after safe restoration and an unclean-session write.

**Architecture:** `ApplicationServices` is the live composition root; `ApplicationModel` owns idempotent launch attempts and the observable gate; `MainWindowView` constructs `EditorHost` only for the ready state. `RecoveryCoordinator` uses per-document generation identity and FIFO write serialization so an older uncancellable write cannot finish last.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, AppKit/TextKit 2, XCTest, XcodeGen, actor-backed persistence.

## Global Constraints

- Work only on Recovery Stage 3, Task 3.5; do not begin Task 3.6.
- Preserve `SPEC.md`, `ARCHITECTURE.md`, and H1-H14 as authority.
- No force unwraps, `try!`, `print()`, network capability, package, tab, workspace, sidebar, or other deferred feature.
- User text remains only in `NSTextStorage`; restoration uses `replaceEntireContents`.
- Every persistence write goes through the approved repository/writer boundaries.
- Use virtual clocks and suspended fakes; no wall-clock sleeps in tests.
- Keep all unverified Task 3.5 implementation changes uncommitted until the complete corrected task passes review.

---

### Task 1: Correct and Verify Recovery Task 3.5

**Files:**
- Create: `Scratchpad/App/ApplicationServices.swift`
- Create: `Scratchpad/Persistence/RecoveryCoordinator.swift` (already present uncommitted; correct in place)
- Create: `ScratchpadTests/Persistence/RecoveryCoordinatorTests.swift` (already present uncommitted; expand in place)
- Modify: `Scratchpad/App/ApplicationModel.swift`
- Modify: `Scratchpad/App/ScratchpadApp.swift`
- Modify: `Scratchpad/App/MainWindowView.swift`
- Modify: `Scratchpad/Document/DocumentSession.swift`
- Modify: `ScratchpadTests/App/ApplicationModelTests.swift`
- Modify: `ScratchpadTests/RecoveryProjectPolicyTests.swift`
- Modify: `project.yml`
- Modify: `TRACKER.md`

**Interfaces:**
- Consumes: `SessionPersisting`, `BookmarkAccessing`, `FileServicing`, `AtomicFileWriting`, `RecoveryClock`, `DocumentSession.recoverySnapshot(savedAt:)`, and `DocumentSession.sessionRecord(windowFrame:didCloseCleanly:savedAt:)`.
- Produces: `ApplicationServices.live() throws -> ApplicationServices`, `ApplicationModel.live() -> ApplicationModel`, `LaunchState`, `requestLaunchRetry()`, `restoreCurrentLaunchAttempt(windowFrame:) async`, ordered `RecoveryCoordinator`, and `RestoreSource`.

- [ ] **Step 1: Preserve the initial GREEN evidence and add the two failing write-order tests**

Keep the seven approved test names. Add:

```swift
func testRescheduledDebounceWaitsForInFlightWriteAndPersistsNewestGeneration() async throws
func testExplicitFlushWaitsForInFlightWriteAndFinishesNewest() async throws
```

Extend the fake repository with a deterministic suspended-write queue. Each intercepted call records entry, waits on a continuation, ignores cancellation, then appends the completed record. In the first test, let `"old"` enter persistence, edit to `"new"`, reschedule and advance the virtual clock, release `"old"`, then require completed texts `["old", "new"]` and final text `"new"`. In the second, suspend `"old"`, edit to `"flushed"`, start explicit flush, release `"old"`, and require `"flushed"` final.

- [ ] **Step 2: Run the write-order tests and capture RED**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test \
  -only-testing:ScratchpadTests/RecoveryCoordinatorTests/testRescheduledDebounceWaitsForInFlightWriteAndPersistsNewestGeneration \
  -only-testing:ScratchpadTests/RecoveryCoordinatorTests/testExplicitFlushWaitsForInFlightWriteAndFinishesNewest
```

Expected: at least one assertion shows stale final text or the old task clearing/reordering the replacement. Record the exact failure in `TRACKER.md` before implementation.

- [ ] **Step 3: Implement generation-safe FIFO persistence**

Use focused private state in `RecoveryCoordinator`:

```swift
private struct PendingRecovery {
    let token: UUID
    let task: Task<Void, Never>
}

private var pendingRecoveries: [UUID: PendingRecovery] = [:]
private var activeWriteDocumentIDs: Set<UUID> = []
private var writeWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
```

`scheduleRecovery` creates a token, captures only the document ID, sleeps for two virtual seconds, snapshots through `documentProvider`, acquires that document's FIFO gate, checks cancellation, and calls `repository.writeRecovery`. Its success path clears only when `pendingRecoveries[id]?.token == token`. `flushRecovery` removes/cancels the timer, snapshots immediately, acquires the same gate, checks cancellation with `Task.checkCancellation()`, writes, and returns only after persistence. `defer` releases the gate on every branch. Never share a gate across IDs.

- [ ] **Step 4: Run the original and write-order recovery tests GREEN**

Run the original seven tests plus both write-order tests. Expected: 9 passed without wall-clock sleeps.

- [ ] **Step 5: Add failing source-authority regressions**

Add:

```swift
func testRecoveryUsesRecoveryBookmarkWhenSessionBookmarkDiffers() async throws
func testNonemptyUntitledRecoveryRestoresEditedAndUnsaved() async throws
```

For divergent bookmarks, provide different session/recovery IDs and references, restore, then assert `model.document.fileReference == recoveryReference`. For untitled recovery, set empty file association and nonempty text while session metadata says clean; assert exact text, `.edited`, and `hasUnsavedChanges == true`.

Run both tests before changing restore code. Expected: each reproduces the controller finding against the pre-correction implementation or preserve the already-captured RED evidence if the uncommitted correction is present. Do not weaken assertions to manufacture a RED.

- [ ] **Step 6: Apply the minimal restore-source corrections**

When `.recovery` wins, resolve `RecoveryRecord.fileReferenceID`, never `SessionRecord.fileReferenceID`. Build the recovered `DocumentSession` with recovery base metadata. Treat nonempty recovery text as preservation-required: `hasUnsavedChanges` is true, and an untitled recovered document is `.edited`. Apply all text only with:

```swift
restoredDocument.replaceEntireContents(
    recovery.unsavedText,
    source: .sessionRestore,
    selection: recovery.selection
)
```

Run all recovery tests. Expected: 11 passed, 0 failed.

- [ ] **Step 7: Add failing launch-gate model tests**

In `ApplicationModelTests`, add:

```swift
func testLaunchGateRemainsClosedUntilUncleanSessionWriteCompletes() async throws
func testLaunchFailureKeepsGateClosedAndRetrySucceeds() async throws
```

Inject a service factory and repository fake. Suspend `writeSession`, start the current attempt, and assert `.restoring` before releasing it and `.ready` afterward. Then make the first write throw, assert `.failed`, call `requestLaunchRetry()`, make the fake succeed, restore the new attempt, and assert `.ready`. Also assert every launch-written session has `didCloseCleanly == false`.

- [ ] **Step 8: Run launch-gate tests and capture RED**

Run the two exact tests. Expected: compile failure because `LaunchState`, live/injected service composition, attempt/retry state, or `restoreCurrentLaunchAttempt` does not yet exist. Record the failure in `TRACKER.md`.

- [ ] **Step 9: Implement the live composition boundary**

Create `ApplicationServices.swift` with immutable protocol-backed members:

```swift
struct ApplicationServices: Sendable {
    let repository: any SessionPersisting
    let bookmarks: any BookmarkAccessing
    let files: any FileServicing
    let recoveryClock: any RecoveryClock

    @MainActor
    static func live() throws -> ApplicationServices
}
```

`live()` resolves `.applicationSupportDirectory`, appends `Scratchpad`, creates all `ApplicationSupportPaths` directories, constructs one `LiveAtomicFileSystem` and one shared `AtomicFileWriter`, then creates `SessionRepository`, `BookmarkStore(client: LiveSecurityScopedBookmarkClient(), now: { Date() })`, `FileService`, and `ContinuousRecoveryClock`. It returns no URL or writable service to a view.

- [ ] **Step 10: Implement idempotent model launch attempts**

Add:

```swift
enum LaunchState: Equatable {
    case restoring
    case ready
    case failed(message: String)
}
```

The existing test initializer remains `.ready`. `ApplicationModel.live()` stores a retryable live factory and begins `.restoring`. Track the active attempt so duplicate calls for the same `launchAttempt` return without another read/write. `requestLaunchRetry()` is valid only from `.failed`, increments the attempt, and sets `.restoring`. Each attempt creates or reuses services, retains a `RecoveryCoordinator` whose provider returns only the current matching document, calls the existing restore pipeline, then sets `.ready` only after `flushSession(...didCloseCleanly: false)` succeeds. Map failure to stable copy such as `"Scratchpad couldn't restore this session safely."`; do not expose persistence details in the UI. Cancellation must leave the gate closed.

- [ ] **Step 11: Add and run the production-root policy RED**

Add:

```swift
func testProductionLaunchUsesLiveServicesAndConstructsEditorOnlyWhenReady() throws
```

The source policy must require `ApplicationModel.live()` in `ScratchpadApp`, `.task(id: model.launchAttempt)` in `MainWindowView`, a `.ready` switch branch, and `EditorHost` text occurring within that ready-branch slice rather than the restoring/failed slices. Run it before production view edits. Expected: FAIL because the app currently constructs `ApplicationModel()` and always constructs `EditorHost`.

- [ ] **Step 12: Gate the production editor**

Change `ScratchpadApp` to create the live model. In `MainWindowView`, use:

```swift
Group {
    switch model.launchState {
    case .restoring:
        ProgressView()
    case .failed(let message):
        launchFailureView(message: message)
    case .ready:
        EditorHost(document: model.document)
            .id(model.document.id)
    }
}
.task(id: model.launchAttempt) {
    await model.restoreCurrentLaunchAttempt(windowFrame: currentWindowFrame)
}
```

Retry calls only `model.requestLaunchRetry()`. Use the actual key-window frame when valid and the approved 820 x 640 default otherwise. Keep the existing 480 x 320 minimum. Do not create an editor in a background, overlay, opacity, or disabled branch.

- [ ] **Step 13: Run the complete focused Task 3.5 suite**

Run the 14 exact Task 3.5 tests. Expected: 14 passed, 0 failed. Re-run each suspended-repository race five times to expose nondeterministic ordering.

- [ ] **Step 14: Run mandatory automated verification**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' build -warnings-as-errors
xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
git diff --check
```

Expected: warning-free build and 110/110 tests. Scan changed production sources for `layoutManager`, `NSTextStorage` subclasses, force unwraps, `try!`, `print(`, notifications/defaults signaling, network code, and deferred feature sources. Confirm `project.yml` contains only the amended files.

- [ ] **Step 15: Perform manual launch acceptance**

Seed a nonempty untitled recovery record, launch the built app, and verify recovered text is the first editable content—there is no editable empty flash. Repeat with a clean file-backed session whose disk text differs from stale recovery, and verify disk text is first. The injected model test is the acceptance evidence for the failure/Retry branch. Record date, build commit candidate, and exact observations in `TRACKER.md`.

- [ ] **Step 16: Review, commit once, and stop**

Review the complete diff against the design, `SPEC.md`, `ARCHITECTURE.md`, H1-H14, data-loss cases, and Task 3.5 scope. Obtain independent code review and resolve every blocker with new regression evidence. Then update `TRACKER.md` to `verified`, advance `AGENTS.md` current task to 3.6 without implementing it, and create the single task commit:

```sh
git add AGENTS.md SPEC.md ARCHITECTURE.md IMPLEMENTATION_PLAN.md TRACKER.md \
  Scratchpad/App/ApplicationServices.swift \
  Scratchpad/App/ApplicationModel.swift \
  Scratchpad/App/ScratchpadApp.swift \
  Scratchpad/App/MainWindowView.swift \
  Scratchpad/Document/DocumentSession.swift \
  Scratchpad/Persistence/RecoveryCoordinator.swift \
  ScratchpadTests/App/ApplicationModelTests.swift \
  ScratchpadTests/Persistence/RecoveryCoordinatorTests.swift \
  ScratchpadTests/RecoveryProjectPolicyTests.swift \
  project.yml
git commit -m "feat: restore and flush latest recovery state"
```

Stop before Task 3.6 and request the user's next approval.
