# Coordinated Conditional Save Design

**Status:** Approved
**Date:** 2026-07-15
**Scope:** Correct Task 3.4's external-edit race without expanding the recovery milestone beyond one document.

## 1. Outcome

A normal Save must not replace a file merely because an earlier preflight matched the document's saved base. The final comparison and replacement become one coordinated persistence operation owned by `AtomicFileWriter`.

If the destination's bytes or modification date differ from the expected base when the coordinated write begins, Scratchpad returns a typed conflict and performs no replacement. A successful result is returned only after the requested bytes have been written atomically and verified.

Save As remains an unconditional atomic replacement because the native save panel or explicit conflict action already confirms replacement. Internal JSON writes continue using the existing unconditional atomic-write path.

## 2. Threat Model

`NSFileCoordinator` serializes Scratchpad's critical section with other processes that participate in macOS file coordination. The coordinated block performs the final hash-and-mtime comparison immediately before replacement, closing the check/write gap for cooperating document applications.

macOS provides no universal content-hash compare-and-swap primitive for arbitrary uncoordinated raw filesystem writers. That limitation is explicit rather than hidden. Scratchpad still performs post-write byte/hash verification and never reports success when verification observes different bytes. Stage 3's manual external-edit gate remains required.

## 3. Architecture

`AtomicFileWriting` gains a conditional user-file operation and immutable value types:

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

The live conditional operation is implemented below `AtomicFileWriter` through an injected coordinator/filesystem boundary. Its coordinated `.forReplacing` block:

1. reads the current destination bytes and modification date;
2. computes the disk-byte SHA-256;
3. returns `.conflict(currentVersion)` without creating or replacing a destination when either expected value differs;
4. writes and synchronizes a same-directory temporary file;
5. atomically replaces the destination;
6. re-reads the destination and requires exact requested bytes and SHA-256; and
7. returns `.written(verifiedVersion)`.

The existing per-destination FIFO lock stays active across the complete coordinated transaction. Temporary-file cleanup remains limited to the writer's own generated temporary URL.

## 4. FileService Flow

Normal Save keeps its early preflight to report obvious missing, read-only, or stale states before allocating a write transaction. It then calls the conditional writer with the snapshot's base hash and mtime. A late `.conflict` result is surfaced as `FileServiceError.conflict` and no successful `FileSaveResult` is created.

`FileService` continues to obtain the destination only from a scoped-access token, never from `pathHint`, and awaits `endAccess` on every post-token branch. It does not mutate `DocumentSession`.

Save As calls the existing unconditional atomic writer and performs the same read-back verification. This is the only bypass and is authorized only by an already-confirmed native-panel or explicit conflict decision.

## 5. Error Handling

- Missing, read-only, reselection-required, generic access, conflict, write, read, and verification failures remain distinct.
- A late conditional conflict is not mapped to a generic write failure.
- Coordination failure is a typed write failure and leaves the existing destination untouched.
- Verification failure never returns a save result or marks a document clean.
- Scoped access always ends exactly once after a token is acquired.

## 6. Verification

TDD additions must first fail against the current check-then-write implementation:

- an injected external mutation after FileService preflight but before replacement returns conflict and records no replacement;
- the live coordinated writer rejects a changed temporary test file without altering it;
- the live coordinated writer replaces an unchanged temporary test file and returns verified metadata;
- every post-token success and failure branch ends the exact acquired token once; and
- live filesystem tests cover bytes, mtime, writability, missing files, and read failures.

Focused AtomicFileWriter and FileService suites, five repeated race-test iterations, the full warning-free build/test suite, and diff/invariant scans are required before Task 3.4 can be verified. The signed-app manual external-edit scenario remains required at the Stage 3 integration gate after `ApplicationModel` wires the service into user-visible Save.

## 7. Alternatives Considered

### Coordinated conditional replacement — selected

This follows the native macOS document-access model, keeps the final comparison beside the atomic replacement, preserves the single writer boundary, and is testable through dependency injection.

### A second FileService check immediately before `write` — rejected

Another check narrows but does not close the race; an external writer can still modify the file between that check and replacement.

### Swap, inspect the displaced file, then restore on mismatch — rejected

This can preserve multiple versions but creates a more complex multi-replacement failure protocol, visible sidecar artifacts, and additional races during restoration. It is disproportionate for the recovery milestone.

## 8. Documentation Amendments

After written-spec approval:

- `ARCHITECTURE.md` will define coordinated conditional Save and its threat model;
- `IMPLEMENTATION_PLAN.md` Task 3.4 will add the conditional writer API, race regressions, full scoped-access matrix, and live-filesystem tests;
- `SPEC.md` will clarify that normal Save performs a final coordinated conflict check; and
- `AGENTS.md` and `TRACKER.md` will remain on Task 3.4 until implementation, review, and manual evidence pass.
