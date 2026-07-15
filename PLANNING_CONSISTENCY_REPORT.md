# Scratchpad Planning Consistency Report

> **Role:** Gate 5 review evidence only. This report does not override `SPEC.md`, `ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md`, `TRACKER.md`, or `AGENTS.md`.
>
> **Review date:** 2026-07-14  
> **Status:** Approved by the user; implementation unlock authorized on 2026-07-14.

## Verdict

The controlled recovery plan is coherent and implementation-ready after Gate 5 approval. It replaces the unsafe core in place, proves one document before reintroducing collection features, and preserves the prototype only as regression evidence. No application or test implementation has begun.

## Authority and Stage Alignment

| Check | Result |
|---|---|
| Live authority order | `SPEC.md` → `ARCHITECTURE.md` → `IMPLEMENTATION_PLAN.md` → `TRACKER.md` → `AGENTS.md` |
| Current stage | Recovery Stage 0 — Baseline and containment |
| Current phase | Planning until Gate 5 approval |
| Implementation lock | ON until Gate 5 approval |
| Historical plans | Explicitly marked non-authoritative |
| Deferred features | Absent from all recovery implementation tasks |

## Product Coverage

| `SPEC.md` area | Implemented and proved by |
|---|---|
| Scope and single-document launch | Tasks 0.1–1.5 |
| New, Open, Save, Save As, Close, Quit | Tasks 3.4–3.8 |
| Save states and external conflicts | Tasks 3.4, 3.6, 3.7 |
| Noto-inspired main window | Task 4.4 |
| Information metrics and approximate tokens | Task 4.3 and Task 4.4 |
| Native and Sublime-style keyboard behavior | Tasks 2.1–2.4 |
| General, Editor, and Theme settings | Tasks 4.1, 4.2, 4.5 |
| Recovery, bookmarks, quarantine, and sandbox | Tasks 3.1–3.5 and 3.8 |
| Visible errors and destructive decisions | Tasks 3.6 and 4.4 |
| Performance budgets | Task 5.2 |
| Accessibility and keyboard-only operation | Task 5.1 |
| Release and dogfood acceptance | Tasks 5.3–5.4 |

## Invariant Coverage

| Invariants | Primary enforcement |
|---|---|
| H1–H2 TextKit 2 and storage rules | Tasks 1.3–1.4, 2.3, 5.3 |
| H3–H6 safety, isolation, and text ownership | Tasks 0.3, 1.1–1.5, 5.3 |
| H7 bookmark-only external access | Tasks 3.3–3.4, 5.3 |
| H8 atomic user-file/internal-JSON writes | Tasks 3.1–3.4, 5.3 |
| H9 verified clean transition | Tasks 3.4 and 3.6 |
| H10 awaited destructive operations | Tasks 3.6 and 3.8 |
| H11 quarantine without deletion | Tasks 3.1–3.3 |
| H12 typed settings state | Tasks 4.1–4.5 |
| H13 dependency/network prohibition | Tasks 0.3, 3.3, 5.3 |
| H14 structured logging | Tasks 3.6 and 5.3 |

## Plan Arithmetic

| Stage | Tasks | Cumulative tests | Required manual gate |
|---|---:|---:|---|
| 0 | 3 | 7 | containment/build policy |
| 1 | 5 | 18 | document/editor identity |
| 2 | 4 | 38 | shortcut and undo matrix |
| 3 | 8 | 98 | signed-sandbox data-loss matrix |
| 4 | 5 | 133 | visual and settings matrix |
| 5 | 4 | 149 | accessibility, performance, dogfood, and failure injection |
| **Total** | **29** | **149** | **approval after every stage** |

## Corrections Made During Planning

- Replaced fake whole-text command edits with selection outcomes and narrow ordered mutations.
- Made bookmark actor calls explicitly asynchronous and added persisted bookmark lookup for clean restoration.
- Added document identity and initiating generation to save results.
- Added an injected native file-panel boundary and deduplicated bookmark identity.
- Added `hasUnsavedChanges` separately from file display state so deleted/read-only documents remain safe.
- Clarified that `AtomicFileWriter` covers user files and internal JSON while scalar settings write only through `SettingsStore`.
- Reconciled target file names (`FileResults`, `PersistenceRecords`, and `ContentHash`).
- Marked every prototype-era plan and identity document non-authoritative.

## Accepted Risks and Boundaries

- A forced kill before the two-second recovery debounce completes can lose edits newer than the last completed recovery snapshot. Stage 5 records this explicitly rather than claiming impossible durability.
- Absolute UI performance budgets require fresh evidence on the target Mac; relative XCTest baselines alone are insufficient.
- Tabs, workspace/sidebar, Quick Open, highlighting, Zen/global hotkey, custom themes, shortcut rebinding, packaging, and distribution remain deferred and unscaffolded.

## Unlock Transaction After Approval

Gate 5 approval authorizes one documentation-only unlock commit:

1. Set `AGENTS.md` implementation lock to OFF.
2. Keep the stage at Recovery Stage 0 — Baseline and containment.
3. Set `TRACKER.md` phase to Implementation and current task to 0.1.
4. Mark Gate 5 verified with the unlock commit as evidence.
5. Mark the implementation plan fully approved.
6. Begin Task 0.1 only; do not begin Task 0.2 or a later stage.
