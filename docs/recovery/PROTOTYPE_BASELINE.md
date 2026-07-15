# Scratchpad Prototype Baseline

> Historical evidence only. This document cannot authorize implementation.

## Preserved Revision

- Last prototype code revision: `a1f36f6`
- Recovery decision date: 2026-07-14
- Disposition: preserve source for evidence; remove it from the active target; replace the core in place.

## Observed Baseline

- XcodeGen generation: succeeded.
- macOS build: succeeded.
- XCTest: 35 tests passed with zero failures.
- Runtime quality: not accepted; SwiftUI reported background publication during tests.
- Build quality: not accepted; the asset catalog reported an unassigned 1024 px app-icon child and AppIntents metadata extraction was skipped because the target has no AppIntents dependency.
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
