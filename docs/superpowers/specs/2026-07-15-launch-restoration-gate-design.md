# Launch Restoration Gate Design

**Status:** Approved

**Date:** 2026-07-15

**Scope:** Correct Task 3.5 so recovery is ordered, production launch actually restores persisted state, and no editable surface appears before the restored session is marked unclean.

## 1. Outcome

Scratchpad must not present an editable `NSTextView` until it has selected and applied exactly one launch source and durably written the active session with `didCloseCleanly == false`. The launch source is recovery text when unsaved work exists, current disk contents for a clean file-backed session, or a new empty document when neither can be restored safely.

Recovery writes for one document must finish in source order. A canceled write that has already entered persistence may complete, but it can never overwrite a newer recovery record as the final value or clear a newer pending debounce entry.

This is a correction to the approved Task 3.5 design, not a new product feature. It does not add tabs, workspaces, a sidebar, or any other deferred surface.

## 2. Live Dependency Assembly

Add `Scratchpad/App/ApplicationServices.swift` as the single live-composition boundary. It constructs:

- the canonical `~/Library/Application Support/Scratchpad/` paths and required directories;
- one `AtomicFileWriter` shared by internal repositories and user-file persistence;
- `SessionRepository`, `BookmarkStore`, and `FileService`; and
- one continuous recovery clock.

`ScratchpadApp` creates an `ApplicationModel` through a non-throwing live factory. Construction failure becomes a closed launch gate with a concise retryable error state; it must never fall back to a fresh editable document. Tests may continue to inject protocol-backed services directly and must not touch live Application Support.

No view constructs repositories, bookmarks, writers, or file services. No persisted URL bypasses `ApplicationSupportPaths`, `BookmarkStore`, or `AtomicFileWriter`.

## 3. Launch State and Editor Gate

`ApplicationModel` owns an explicit observable launch state:

```swift
enum LaunchState: Equatable {
    case restoring
    case ready
    case failed(message: String)
}
```

It also owns a monotonically increasing launch-attempt identifier. `MainWindowView` uses SwiftUI `.task(id:)` to ask the model to restore the current attempt. Incrementing the identifier is the retry mechanism; the view does not create an unstructured task.

The state transitions are:

```text
restoring -> source selected -> document replaced -> unclean session write verified -> ready
restoring -> any failure ----------------------------------------------------------> failed
failed -> user Retry --------------------------------------------------------------> restoring
```

While restoring, `MainWindowView` shows a native indeterminate `ProgressView`. On failure it shows a short failure message and Retry button. `EditorHost` is constructed only in `.ready`; hiding or disabling an already-created editor is insufficient because it could accept input or publish editor state before restoration finishes.

The restore operation is idempotent per attempt. Duplicate `.task` evaluation for the same attempt does not perform a second restore or session write. A retry reuses an already-created live service graph; if composition itself failed, it reruns the live factory. It then re-reads persistence and performs a new complete attempt. Cancellation caused by removal of the window does not open the gate.

## 4. Restore Source Rules

Launch restoration preserves the approved source policy:

1. A matching recovery record wins when the session reports unsaved changes.
2. A nonempty recovery record wins for an untitled session even if stale session metadata incorrectly says it is clean.
3. A clean file-backed session reopens current disk bytes through `FileService`.
4. Otherwise Scratchpad creates a new empty document without deleting or rewriting unreadable/orphan recovery data.

Recovered text enters the existing `NSTextStorage` only through `DocumentSession.replaceEntireContents`. Recovery metadata, not stale session metadata, is authoritative for the recovered record's `fileReferenceID` and path hint. A nonempty untitled recovery is restored as edited and unsaved.

After applying the source, and before setting launch state to `.ready`, the model writes a fresh `SessionRecord` with `didCloseCleanly == false`. If that write fails, the restored document remains owned by the model but the editor gate stays closed and the user receives Retry; Scratchpad must not silently expose a session it failed to mark active.

## 5. Ordered Recovery Persistence

`RecoveryCoordinator` keeps one pending debounce entry per document containing both a unique generation token and its task. Completion removes the entry only when its token still matches the dictionary entry. Therefore an older task cannot erase a replacement task.

Writes are serialized per document through a small FIFO async gate owned by the main-actor coordinator. The gate spans the repository call, not the two-second debounce delay:

- different document IDs remain independent;
- a rescheduled debounce cancels only the old timer;
- if the old task is already writing, the newer task waits and writes afterward;
- explicit flush cancels the pending timer, snapshots current text immediately, waits for any in-flight write for that document, then persists its newer snapshot; and
- failure is propagated by explicit flush and never converted into a successful clean/session transition.

Repository cancellation is not assumed. Correctness comes from ordering and generation identity even when an injected repository deliberately ignores task cancellation while suspended.

## 6. File Changes

Task 3.5 scope is amended to include:

- create `Scratchpad/App/ApplicationServices.swift`;
- modify `Scratchpad/App/ScratchpadApp.swift`;
- modify `Scratchpad/App/MainWindowView.swift`;
- modify the already-approved Task 3.5 files; and
- expand `ScratchpadTests/Persistence/RecoveryCoordinatorTests.swift` plus focused application launch-gate tests and source-policy checks.

`SPEC.md`, `ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md`, `TRACKER.md`, and `project.yml` are amended only as required to make this contract authoritative and build the added files.

## 7. Verification

TDD must demonstrate these additional failures before implementation is accepted:

- a rescheduled debounce while the older repository write is suspended leaves the newest record persisted and the replacement generation intact;
- an explicit flush while an older repository write is suspended finishes with the flushed text as the final record;
- divergent session and recovery bookmark IDs restore the recovery bookmark association;
- nonempty untitled recovery restores as edited and unsaved;
- launch state remains `.restoring` while the unclean session write is suspended and becomes `.ready` only after it succeeds;
- a launch failure never exposes the editor gate, and Retry can complete a fresh attempt; and
- a production-root policy test proves `ScratchpadApp` uses live composition and `MainWindowView` constructs `EditorHost` only in the ready branch.

Focused recovery and launch-gate suites, a warning-as-error build, the complete test suite, invariant/scope scans, and independent code review are required. No manual editor acceptance is credited until a live launch visibly restores recovery or disk content without first flashing an editable empty document.

## 8. Error and Logging Policy

The launch UI presents stable, nontechnical copy and a Retry action. Persistence details remain in typed errors. Task 3.5 does not add ad hoc `print()` calls or a new logging subsystem; the existing H14 rule remains in force, and broader diagnostics stay in their planned stage.

The gate fails closed for directory creation, repository decoding, bookmark resolution, file access, recovery application, and unclean-session persistence errors. Corrupt state follows the repository quarantine rules and is never deleted.

## 9. Alternatives Considered

### Model-owned launch gate with SwiftUI `.task(id:)` — selected

This keeps persistence orchestration in typed observable state, makes the editor-construction boundary explicit, provides structured cancellation, and supports deterministic injected tests.

### Dedicated bootstrap window/controller subsystem — rejected

It would duplicate window and state ownership for a one-window app and enlarge Task 3.5 without improving the persistence invariant.

### Show the editor and replace its text when restore finishes — rejected

The user could type into an empty document before restoration, producing ambiguous ownership and possible loss when recovered text replaces it. It also violates the requirement to mark the session unclean before accepting input.

### Trust task cancellation to stop stale writes — rejected

An actor or repository may already be executing and may not honor cancellation. Only per-document serialization plus generation identity guarantees the newest write finishes last.

### Use session bookmark metadata for recovered text — rejected

Recovery is the authoritative snapshot of the unsaved document. Borrowing a stale session association can direct a later Save at the wrong external file.

## 10. Documentation Amendments

After written-spec approval:

- `SPEC.md` will require the fail-closed launch gate and ordered latest-recovery guarantee;
- `ARCHITECTURE.md` will define live dependency composition, launch ownership, source authority, and per-document write serialization;
- `IMPLEMENTATION_PLAN.md` Task 3.5 will list the amended files, exact RED tests, verification counts, and manual launch check;
- `TRACKER.md` will record the approved correction while remaining on Task 3.5; and
- `AGENTS.md` will remain on Recovery Stage 3, Task 3.5 until the amended task is verified and committed.
