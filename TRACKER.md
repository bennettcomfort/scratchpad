# TRACKER.md — Scratchpad Recovery

> **Current stage:** Recovery Stage 0 — Baseline and containment  
> **Current phase:** Planning  
> **Current task:** Gate 4E — approve Stages 4–5 implementation plan
> **Implementation lock:** ON

Only these task states are valid: `pending`, `in progress`, `blocked`, and `verified`. Only `verified` work counts toward a gate or stage. Application and test code remain locked until Gates 4A–4E and the final consistency gate are approved.

## Planning Gates

| Gate | Deliverable | State | Evidence |
|---|---|---|---|
| Design | Controlled recovery design | verified | Approved; commit `f3cb8f1` |
| 1 | Replace `SPEC.md` | verified | Approved; commit `a4abbe1` |
| 2 | Create `ARCHITECTURE.md`; mark prior canon and review historical | verified | Approved; commit `273aee6` |
| 3 | Replace `AGENTS.md`; create `TRACKER.md` | verified | Approved; commit `82aee23` |
| 4A | Stage 0 implementation plan | verified | Approved; commit `41986d1` |
| 4B | Stage 1 implementation plan | verified | Approved; commit `92c8863` |
| 4C | Stage 2 implementation plan | verified | Approved; commit `faa86de` |
| 4D | Stage 3 implementation plan | verified | Approved; commit `05781a2` |
| 4E | Stages 4–5 implementation plan | in progress | Draft complete; awaiting user approval |
| 5 | Cross-document consistency and implementation unlock | pending | — |

## Recovery Roadmap

The roadmap rows are stage anchors. Each approved Gate 4 section adds its task-level ledger from `IMPLEMENTATION_PLAN.md`; no row authorizes implementation while the implementation lock is ON.

### Stage 0 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 0.1 | Preserve prototype baseline and regression contract | pending | Awaiting Gate 4A approval and implementation unlock |
| 0.2 | Enforce the recovery source boundary | pending | Awaiting Gate 4A approval and implementation unlock |
| 0.3 | Enforce warning, dependency, entitlement, and CI policy | pending | Awaiting Gate 4A approval and implementation unlock |

### Stage 1 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 1.1 | Define document values and snapshot boundaries | pending | Awaiting Gate 4B approval and implementation unlock |
| 1.2 | Implement single-owner `DocumentSession` | pending | Awaiting Gate 4B approval and implementation unlock |
| 1.3 | Attach document storage to TextKit 2 exactly once | pending | Awaiting Gate 4B approval and implementation unlock |
| 1.4 | Synchronize native edits, selection, scroll, and undo | pending | Awaiting Gate 4B approval and implementation unlock |
| 1.5 | Replace containment shell with the single editor | pending | Awaiting Gate 4B approval and implementation unlock |

### Stage 2 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 2.1 | Define command values and UTF-16 line geometry | pending | Awaiting Gate 4C approval and implementation unlock |
| 2.2 | Implement and prove pure command transformations | pending | Awaiting Gate 4C approval and implementation unlock |
| 2.3 | Apply commands through one undoable AppKit transaction | pending | Awaiting Gate 4C approval and implementation unlock |
| 2.4 | Route fixed shortcuts through the first responder | pending | Awaiting Gate 4C approval and implementation unlock |

### Stage 3 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 3.1 | Establish atomic persistence and canonical internal paths | pending | Awaiting Gate 4D approval and implementation unlock |
| 3.2 | Persist and quarantine session and recovery records | pending | Awaiting Gate 4D approval and implementation unlock |
| 3.3 | Enable sandboxed persistent security-scoped bookmarks | pending | Awaiting Gate 4D approval and implementation unlock |
| 3.4 | Open, inspect, and atomically save UTF-8 files | pending | Awaiting Gate 4D approval and implementation unlock |
| 3.5 | Debounce recovery per document and restore the correct source | pending | Awaiting Gate 4D approval and implementation unlock |
| 3.6 | Serialize native panels, decisions, and destructive document operations | pending | Awaiting Gate 4D approval and implementation unlock |
| 3.7 | Monitor external changes without document-identity races | pending | Awaiting Gate 4D approval and implementation unlock |
| 3.8 | Await window close and application termination | pending | Awaiting Gate 4D approval and implementation unlock |

### Stage 4 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 4.1 | Implement typed settings and Launch at Login | pending | Awaiting Gate 4E approval and implementation unlock |
| 4.2 | Define fixed themes and apply editor appearance safely | pending | Awaiting Gate 4E approval and implementation unlock |
| 4.3 | Calculate prompt metrics off the main actor | pending | Awaiting Gate 4E approval and implementation unlock |
| 4.4 | Build the Noto-inspired main window | pending | Awaiting Gate 4E approval and implementation unlock |
| 4.5 | Build native General, Editor, and Theme settings | pending | Awaiting Gate 4E approval and implementation unlock |

### Stage 5 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 5.1 | Prove accessibility and keyboard-only operation | pending | Awaiting Gate 4E approval and implementation unlock |
| 5.2 | Measure the published performance budgets | pending | Awaiting Gate 4E approval and implementation unlock |
| 5.3 | Automate the final source and release audit | pending | Awaiting Gate 4E approval and implementation unlock |
| 5.4 | Complete dogfood and destructive failure injection | pending | Awaiting Gate 4E approval and implementation unlock |

| Stage | Outcome | State | Approval gate |
|---|---|---|---|
| 0 | Preserve baseline, remove deferred surfaces from the active target, and lock known failures with regressions | pending | User approves baseline evidence and contained target |
| 1 | Establish one `DocumentSession`, one TextKit 2 editor attachment, and correct text ownership | pending | User approves document/editor manual matrix |
| 2 | Route native and fixed Sublime-style commands once, with correct selections and undo | pending | User approves command matrix |
| 3 | Make recovery, bookmarks, sandboxed file access, saves, conflicts, close, and quit data-safe | pending | User approves forced-termination and data-loss matrix |
| 4 | Build the approved Noto-inspired shell, fixed themes, information bar, token estimate, and settings | pending | User approves visual and settings matrix |
| 5 | Complete warning, regression, accessibility, performance, and dogfood hardening | pending | User accepts recovery milestone |

## Known Defect Ledger

| Defect | Required disposition | Planned stage | State |
|---|---|---|---|
| Editor coordinator remains bound to the first buffer; tabs can show or edit the wrong text | Reduce to one document, then prove editor identity before multi-document returns | 0–1 | pending |
| Concurrent open paths and double activation can create duplicate tabs | Remove from recovery target; retain a regression requirement for the later tabs stage | 0 / deferred | pending |
| Save-and-Close closes before an asynchronous save finishes | Replace with an awaited decision transaction that remains open on failure | 3 | pending |
| Global recovery debounce lets one buffer cancel another and quit can miss the latest edit | Use per-document recovery scheduling and an awaited termination flush | 3 | pending |
| Clean restoration can produce empty text; dirty restoration lacks complete save metadata | Persist explicit session/recovery records and restore from the correct source | 3 | pending |
| App Sandbox and persistent security-scoped bookmarks are absent | Enable the real sandbox and persist refreshed bookmarks atomically | 3 | pending |
| Competing local key monitors mutate storage directly and commands fire unreliably | Replace with responder-chain actions and one typed command router | 2 | pending |
| Sidebar divider shakes because drag geometry moves under the pointer and writes defaults continuously | Remove from recovery target; require native split view when workspace returns | 0 / deferred | pending |
| Zen/global hotkey registration and lifecycle are unreliable | Remove from recovery target; restore only through the shared command registry with visible errors | 0 / deferred | pending |
| Global defaults notifications cause unrelated view and command feedback | Replace active settings flow with typed observable state | 4 | pending |
| Whole-document Markdown highlighting runs on the main actor and leaves stale attributes | Remove from recovery target; later restore incrementally with generation validation | 0 / deferred | pending |

## Decision Log

| Date | Decision | Affected documents |
|---|---|---|
| 2026-07-14 | Recover in place through a controlled core replacement; do not start an empty repository | Design, `SPEC.md`, `ARCHITECTURE.md` |
| 2026-07-14 | Prove a single-document editor before tabs, workspace, highlighting, or Zen return | All live documents |
| 2026-07-14 | Ship fixed System, Light, and Dark appearances; System is default; custom theme editing is deferred | `SPEC.md`, `ARCHITECTURE.md` |
| 2026-07-14 | Ship one fixed, tested Sublime-style macOS shortcut profile; rebinding is deferred | `SPEC.md`, `ARCHITECTURE.md` |
| 2026-07-14 | Use a native Noto-inspired document title and visible information bar | `SPEC.md`, `ARCHITECTURE.md` |
| 2026-07-14 | Display approximate prompt tokens as `~ceil(UTF-8 byte count / 4)`, with empty text equal to `0` | `SPEC.md`, `ARCHITECTURE.md` |
| 2026-07-14 | Require user approval after every planning section and implementation stage | Design, `AGENTS.md`, `TRACKER.md` |
| 2026-07-14 | Represent editor commands as selection-only outcomes or ordered narrow mutations so Select Line creates no fake edit and multi-line commands preserve unrelated attributes | `ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md` |
| 2026-07-14 | Persist `hasUnsavedChanges` separately from display save state because read-only and deleted files can contain either clean or preservation-required text | `ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md` |

## Blockers

None. Gate 4E is awaiting the required user approval, not blocked.

When blocked, record the concrete evidence, affected task, safe work already exhausted, and exact user decision needed. Never mark a task `blocked` merely because it is difficult or incomplete.

## Verification Evidence

| Date | Scope | Command or check | Result | Commit |
|---|---|---|---|---|
| 2026-07-14 | Recovery design | User approval and committed design | verified | `f3cb8f1` |
| 2026-07-14 | Product contract | User approval; `git diff --check` | verified | `a4abbe1` |
| 2026-07-14 | Architecture contract | User approval; `git diff --check` | verified | `273aee6` |
| 2026-07-14 | Gate 3 documents | Authority, stage-pointer, vocabulary, and whitespace review | verified | `82aee23` |
| 2026-07-14 | Gate 4A plan | Invariant comparison, prototype diff, placeholder scan, and whitespace review | verified | `41986d1` |
| 2026-07-14 | Gate 4B plan | SDK API check, type/test-count review, invariant comparison, and whitespace review | verified | `92c8863` |
| 2026-07-14 | Gate 4C plan | Responder API check, command-contract correction, transformation review, test-count review, and whitespace review | verified | `faa86de` |
| 2026-07-14 | Gate 4D plan | Atomicity, bookmark, save, recovery, operation, external-change, termination, test-count, and whitespace review | verified | `05781a2` |
| 2026-07-14 | Gate 4E plan | Settings, theme, metrics, visual, accessibility, performance, policy, dogfood, test-count, and whitespace review | in progress | Draft awaiting approval |

## Current Manual Acceptance Matrix

Stage 0 implementation has not begun. These checks remain `pending` until the implementation lock is cleared and Tasks 0.1–0.3 produce fresh evidence.

| Check | Expected | State | Evidence |
|---|---|---|---|
| Prototype preservation | Prototype implementation directories have no diff from `a1f36f6` | pending | Awaiting Task 0.1–0.2 execution |
| Active source boundary | Generated project contains `RecoveryBaseline` and no prototype implementation source | pending | Awaiting Task 0.2 execution |
| Deferred surface removal | Launched app exposes none of the recovery-milestone deferred surfaces | pending | Awaiting Task 0.2 manual check |
| Warning and test policy | Warnings are errors; the 7 Stage 0 tests pass | pending | Awaiting Task 0.3 execution |
| Dependency and network policy | No runtime packages or network entitlements | pending | Awaiting Task 0.3 execution |
| CI parity | CI uses the approved local build and test commands without deployment override | pending | Awaiting Task 0.3 execution |

## Update Protocol

1. Set exactly one task to `in progress`; all other unfinished tasks remain `pending` unless genuinely blocked.
2. Record failing baseline evidence before implementation and fresh passing evidence before `verified`.
3. Keep the `AGENTS.md` and `TRACKER.md` stage pointers identical in the same commit.
4. Record decisions that alter scope, behavior, architecture, task order, or acceptance.
5. Do not advance a stage, clear the implementation lock, or reinterpret a failed gate without explicit user approval.
6. At an approval gate, stop and present the changed files, evidence, open risks, and the next proposed gate.
