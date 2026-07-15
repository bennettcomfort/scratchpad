# Coordinated Conditional Save Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Task 3.4 with a normal-Save transaction that detects an external mutation at the final coordinated replacement boundary and never returns a false success.

**Architecture:** `AtomicFileWriter` remains the only mutation primitive. Its new conditional operation holds the existing destination lock while an injected `AtomicFileSystem` performs an `NSFileCoordinator` `.forReplacing` comparison, atomic replacement, and exact read-back verification. `FileService` keeps an early conflict check for fast errors, then maps the conditional writer's late result into immutable service results without touching `DocumentSession`.

**Tech Stack:** Swift 6, Foundation `NSFileCoordinator`, CryptoKit SHA-256 through `ContentHash`, XCTest, XcodeGen, macOS App Sandbox.

## Global Constraints

- Work only on Recovery Stage 3 Task 3.4; do not begin Task 3.5.
- Preserve all `AGENTS.md` invariants H1–H14.
- No force unwraps, `try!`, `print`, network code, new entitlement, or runtime package.
- Every user-file mutation goes through `AtomicFileWriter`.
- External destinations come only from a live `ScopedAccessToken`; `pathHint` is never converted into a URL.
- A post-token branch awaits `endAccess` exactly once before returning or throwing.
- Production code follows RED → GREEN; no implementation change precedes its failing regression.

---

### Task 1: Correct and Verify Task 3.4

**Files:**
- Modify: `Scratchpad/Persistence/AtomicFileWriter.swift`
- Modify: `ScratchpadTests/Persistence/AtomicFileWriterTests.swift`
- Create: `Scratchpad/Files/FileResults.swift`
- Create: `Scratchpad/Files/FileService.swift`
- Create: `ScratchpadTests/Files/FileServiceTests.swift`
- Modify: `project.yml`
- Modify: `AGENTS.md`
- Modify: `TRACKER.md`
- Update ignored evidence: `.superpowers/sdd/task-3.4-report.md`

**Interfaces:**
- Consumes: `BookmarkAccessing`, `ScopedAccessToken`, `DocumentSnapshot`, `ContentHash`, the existing unconditional `AtomicFileWriting.write`, and the existing per-destination transaction lock.
- Produces: `AtomicFileVersion`, `ConditionalWriteResult`, `AtomicFileWriting.write(_:to:ifUnchangedFrom:)`, `FileOpenResult`, `FileSaveResult`, `ExternalFileStatus`, `FileServiceError`, and `FileServicing`.

- [ ] **Step 1: Restore the tracker gate before implementation**

Require `AGENTS.md` and `TRACKER.md` to identify Task 3.4 as current and `in progress`. Task 3.5 remains `pending`.

- [ ] **Step 2: Add conditional-writer RED tests**

Add these tests to `AtomicFileWriterTests.swift`:

```swift
func testConditionalWriteRejectsChangedLiveFileWithoutReplacing() async throws
func testConditionalWriteReplacesUnchangedLiveFileAndReturnsVerifiedVersion() async throws
```

The changed test creates a real temporary destination with version A, captures `AtomicFileVersion(A)`, writes version B externally, then requests candidate C with expected A. Assert `.conflict(B)` and exact B bytes remain. The unchanged test requests B with expected A and asserts `.written(B)`, exact B bytes, returned mtime, and no `.scratchpad-*.tmp` files.

- [ ] **Step 3: Run the conditional-writer tests and verify RED**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -derivedDataPath /tmp/ScratchpadTask34Conditional -only-testing:ScratchpadTests/AtomicFileWriterTests/testConditionalWriteRejectsChangedLiveFileWithoutReplacing -only-testing:ScratchpadTests/AtomicFileWriterTests/testConditionalWriteReplacesUnchangedLiveFileAndReturnsVerifiedVersion test
```

Expected: compilation fails because `AtomicFileVersion`, `ConditionalWriteResult`, and the conditional `write` overload do not exist.

- [ ] **Step 4: Add the conditional persistence contract**

Add exactly:

```swift
struct AtomicFileVersion: Equatable, Sendable {
    let contentHash: String
    let modificationDate: Date
}

enum ConditionalWriteResult: Equatable, Sendable {
    case written(AtomicFileVersion)
    case conflict(AtomicFileVersion)
    case missing
    case readOnly
}

protocol AtomicFileWriting: Sendable {
    func write(_ data: Data, to destination: URL) async throws
    func write(
        _ data: Data,
        to destination: URL,
        ifUnchangedFrom expected: AtomicFileVersion
    ) async throws -> ConditionalWriteResult
    func removeIfPresent(_ url: URL) async throws
    func quarantine(_ source: URL, as destination: URL) async throws
}
```

Extend the injected filesystem seam with one operation that receives candidate bytes, destination, generated same-directory temporary URL, and expected version. The live implementation owns `NSFileCoordinator.coordinate(writingItemAt:options:.forReplacing,error:byAccessor:)`; inside its accessor it reads bytes/resource values, returns non-writing `.missing`, `.readOnly`, or `.conflict`, otherwise writes/synchronizes the temporary file, atomically replaces, re-reads, and returns `.written` only for exact candidate bytes and SHA-256.

Use this exact filesystem requirement:

```swift
func replaceIfUnchanged(
    _ data: Data,
    destination: URL,
    temporaryURL: URL,
    expected: AtomicFileVersion
) throws -> ConditionalWriteResult
```

Add `AtomicFileWriterError.conditionalWriteUnavailable(destination:)` and `.verificationFailed(destination:)`. A protocol-extension default for the conditional `AtomicFileWriting.write` overload throws `.conditionalWriteUnavailable`; this keeps persistence-only spies source-compatible, while the FileService writer spy and `AtomicFileWriter` implement the operation explicitly.

`AtomicFileWriter` acquires the existing symlink-resolved destination key before invoking the filesystem operation and releases it afterward. On thrown failure it removes only its generated temporary URL and throws a typed `AtomicFileWriterError`.

- [ ] **Step 5: Run all AtomicFileWriter tests to GREEN**

Run:

```sh
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -derivedDataPath /tmp/ScratchpadTask34Conditional -only-testing:ScratchpadTests/AtomicFileWriterTests test
```

Expected: all prior 15 tests plus the two conditional tests pass with zero failures.

- [ ] **Step 6: Add FileService late-race and live-filesystem RED tests**

Add these exact tests to `FileServiceTests.swift`:

```swift
func testSaveRejectsMutationAfterPreflightBeforeReplacement() async throws
func testLiveFileSystemReadsBytesModificationDateAndWritability() async throws
func testLiveFileSystemMapsMissingAndNonRegularFiles() async throws
```

For the race test, the injected file reader returns expected base A during preflight. The conditional-writer spy then returns `.conflict(B)`. Assert `FileServiceError.conflict` contains B, no unconditional writer call occurs, no `FileSaveResult` exists, and the exact acquired token ends once.

The live tests use one temporary regular file and one directory. Assert real bytes, a non-nil mtime, expected writable state, `.missing` for an absent path, and `.readFailed` for the non-regular path.

- [ ] **Step 7: Expand the exact scoped-access matrix and verify RED**

Keep the required name `testEveryExitPathEndsScopedAccessExactlyOnce`. Make it table-driven across:

```text
open: success, invalid UTF-8, missing, read failure
inspect: unchanged, changed, missing, read-only
save: success, early conflict, late conflict, read-only, write failure,
      read-back missing, read-back failure, byte mismatch
saveAs: new, existing, read-only, write failure,
        read-back missing, read-back failure, byte mismatch
```

Each row gets a unique `ScopedAccessToken.id`. Assert acquired IDs equal ended IDs exactly, with no duplicate ends. Run the focused FileService suite and confirm the late-race test fails because normal Save still calls unconditional `write` after preflight; confirm newly added branch rows fail where cleanup or error mapping is incomplete.

- [ ] **Step 8: Route normal Save through the conditional writer**

Normal Save constructs:

```swift
let expected = AtomicFileVersion(
    contentHash: baseHash,
    modificationDate: baseModificationDate
)
```

After early preflight and UTF-8/line-ending encoding, call:

```swift
let outcome = try await writer.write(
    requestedBytes,
    to: token.url,
    ifUnchangedFrom: expected
)
```

Map `.conflict(version)` to `.conflict(contentHash:modificationDate:)`, `.missing` to `.missing`, `.readOnly` to `.readOnly`, and `.written(version)` to `FileSaveResult`. Do not call the unconditional writer or perform a second mutation. Save As retains unconditional `write` plus read-back verification.

Use explicit `do/catch` blocks so every branch after token acquisition awaits `bookmarks.endAccess(token)` before returning or rethrowing. Preserve `.accessRequiresReselection`, `.accessFailed`, `.readFailed`, `.writeFailed`, and `.verificationFailed` distinctions.

- [ ] **Step 9: Run focused GREEN and repeat the race**

Run:

```sh
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -derivedDataPath /tmp/ScratchpadTask34Conditional -only-testing:ScratchpadTests/FileServiceTests test
```

Expected: all 13 FileService tests pass with zero failures. Together with the two new AtomicFileWriter conditional tests, Task 3.4 has 15 focused tests.

Then run the late-race test five times. Expected each run: one typed conflict, zero unconditional writes, zero successful results, and exact one-token end accounting.

- [ ] **Step 10: Run full verification**

Run:

```sh
xcodegen
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -derivedDataPath /tmp/ScratchpadStage3 SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
xcodebuild -scheme Scratchpad -destination 'platform=macOS' -derivedDataPath /tmp/ScratchpadStage3 test
git diff --check
```

Expected: warning-as-error build succeeds; 93 cumulative tests pass; no whitespace errors. Scan the scoped diff for H1–H14, direct `pathHint` URL construction, `DocumentSession` mutation, unstructured `Task`, network entitlement, and any user-file mutation outside `AtomicFileWriter`.

- [ ] **Step 11: Controller review and evidence**

Update `.superpowers/sdd/task-3.4-report.md` with initial RED, controller RED, conditional-writer RED/GREEN, 15/15 focused results, five race repetitions, 93/93 full results, warning-free build, scope scans, and the explicit `NSFileCoordinator` threat-model limitation.

Keep Task 3.4 `in progress` until an independent controller reports no Critical, Important, or Minor findings. The signed-app manual external-edit scenario is recorded for the Stage 3 integration gate after ApplicationModel Save wiring exists.

- [ ] **Step 12: Commit the verified task**

Only after clean controller review, update `AGENTS.md`/`TRACKER.md` to Task 3.5 and commit:

```sh
git add AGENTS.md Scratchpad/Persistence/AtomicFileWriter.swift ScratchpadTests/Persistence/AtomicFileWriterTests.swift Scratchpad/Files/FileResults.swift Scratchpad/Files/FileService.swift ScratchpadTests/Files/FileServiceTests.swift project.yml TRACKER.md
git commit -m "feat: add verified sandbox file service"
```
