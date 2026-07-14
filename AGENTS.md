# AGENTS.md — Scratchpad

Rules for every coding agent in this repository. Read this file before acting.

## Current Stage

> **Recovery Stage 0 — Baseline and containment**
>
> **Implementation lock: ON.** Planning gates 4A–4E and the final consistency gate are not yet approved. Do not change application or test code.

Work only on the current stage and current task recorded in `TRACKER.md`. Never prepare, scaffold, or begin a later stage without the user's explicit approval.

## Authority

When documents disagree, stop and resolve the disagreement before editing code.

1. `SPEC.md` — required product behavior and acceptance.
2. `ARCHITECTURE.md` — ownership, boundaries, data flow, and safety invariants.
3. `IMPLEMENTATION_PLAN.md` — approved task order and verification steps.
4. `TRACKER.md` — current stage, current task, evidence, blockers, and decisions.
5. `AGENTS.md` — always-loaded operating rules.

`MASTER_CANON.md`, `ARCHITECTURAL_REVIEW_REPORT.md`, and other earlier planning documents are historical evidence only. They cannot authorize implementation.

## Hard Invariants

Violating any invariant is a defect, even when the feature appears to work.

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

## Task Workflow

For every implementation task, in the exact approved plan order:

1. Confirm the task is the current `TRACKER.md` task and is within the current stage.
2. Read the entire task block, including prohibited scope and acceptance evidence.
3. Add the specified failing test or capture the specified failing baseline; run it and record the failure.
4. Implement only the minimum change required by that task.
5. Run the focused test until it passes.
6. Run the full warning-free build and test suite:

   ```sh
   xcodegen && xcodebuild -scheme Scratchpad -destination 'platform=macOS' build
   xcodebuild -scheme Scratchpad -destination 'platform=macOS' test
   ```

7. Perform the task's manual acceptance check when required.
8. Review the diff for invariant, scope, warning, and data-loss violations.
9. Commit one conventional commit for the verified task.
10. Update `TRACKER.md` with fresh command, manual-check, date, and commit evidence.
11. Stop at the stage approval gate. The user advances the stage.

Use `feat:`, `fix:`, `test:`, `refactor:`, `docs:`, or `chore:` commit prefixes. A passing build alone never changes a task to `verified`.

## Stop Conditions

Stop and ask the user when:

- a requested change conflicts with a live authoritative document;
- a task would cross the current stage or expand scope;
- a safety invariant appears impossible without changing the architecture;
- required verification cannot run or produces unexplained warnings;
- a data-loss scenario cannot be reproduced or verified; or
- a task requires a new dependency, entitlement, network access, or destructive migration.

Do not preserve broken prototype APIs for compatibility. Do not refactor unrelated code. Do not hide errors with test weakening, warning suppression, or asynchronous delays.

## Deferred

Do not build or scaffold tabs, multi-document support, workspaces, sidebar, Quick Open, Zen window, global hotkey, Markdown highlighting, custom keybindings, custom themes, information HUD, live preview, WYSIWYG, plugins, AI, MCP, terminal, export, sync, localization, release packaging, or distribution.

Deferred features return only through a focused spec amendment, architecture review, implementation-plan stage, regression tests, manual acceptance evidence, and explicit user approval.
