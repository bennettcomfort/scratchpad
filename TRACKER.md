# TRACKER.md — Scratchpad Recovery

> **Current stage:** Recovery Stage 1 — Document and editor core
> **Current phase:** Implementation
> **Current task:** Task 1.5 — replace containment shell with the single editor
> **Implementation lock:** OFF

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
| 4E | Stages 4–5 implementation plan | verified | Approved; plan `8d8ed19`, approval `a12199e` |
| 5 | Cross-document consistency and implementation unlock | verified | Approved by user on 2026-07-14; unlock commit pending |

## Recovery Roadmap

The roadmap rows are stage anchors. Each approved Gate 4 section adds its task-level ledger from `IMPLEMENTATION_PLAN.md`; no row authorizes implementation while the implementation lock is ON.

### Stage 0 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 0.1 | Preserve prototype baseline and regression contract | verified | `a1f36f6`; XcodeGen/build succeeded; 35/35 tests passed; warnings and regressions recorded; commit `61be30c` |
| 0.2 | Enforce the recovery source boundary | verified | Red compile failure captured; 2/2 focused and 3/3 full tests pass; source boundary and manual containment UI verified; commit `f7c765a` |
| 0.3 | Enforce warning, dependency, entitlement, and CI policy | verified | Two expected policy failures captured; 6/6 focused and 7/7 full tests pass; warnings-as-errors, dependency, entitlement, CI, and whitespace policies verified; this policy commit |

### Stage 1 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 1.1 | Define document values and snapshot boundaries | verified | Expected missing-type compile failure captured; 2/2 focused and 9/9 full tests pass; warning-as-error build succeeds; this task commit |
| 1.2 | Implement single-owner `DocumentSession` | verified | Expected missing-session compile failure captured; 4/4 focused and 13/13 full tests pass; warning-as-error build succeeds; this task commit |
| 1.3 | Attach document storage to TextKit 2 exactly once | verified | Expected missing-editor compile failure captured; 2/2 focused and 15/15 full tests pass; warning-as-error build succeeds; forbidden TextKit 1 scan is empty; this task commit |
| 1.4 | Synchronize native edits, selection, scroll, and undo | verified | Expected missing-delegate compile failure captured; 3/3 focused and 18/18 full tests pass; native undo and exactly-once edit callback verified; warning-as-error build succeeds; forbidden TextKit 1 scan is empty; this task commit |
| 1.5 | Replace containment shell with the single editor | in progress | Task 1.4 verified; approved Stage 1 plan continuing |

### Stage 2 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 2.1 | Define command values and UTF-16 line geometry | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 2.2 | Implement and prove pure command transformations | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 2.3 | Apply commands through one undoable AppKit transaction | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 2.4 | Route fixed shortcuts through the first responder | pending | Approved plan; awaiting Gate 5 implementation unlock |

### Stage 3 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 3.1 | Establish atomic persistence and canonical internal paths | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 3.2 | Persist and quarantine session and recovery records | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 3.3 | Enable sandboxed persistent security-scoped bookmarks | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 3.4 | Open, inspect, and atomically save UTF-8 files | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 3.5 | Debounce recovery per document and restore the correct source | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 3.6 | Serialize native panels, decisions, and destructive document operations | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 3.7 | Monitor external changes without document-identity races | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 3.8 | Await window close and application termination | pending | Approved plan; awaiting Gate 5 implementation unlock |

### Stage 4 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 4.1 | Implement typed settings and Launch at Login | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 4.2 | Define fixed themes and apply editor appearance safely | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 4.3 | Calculate prompt metrics off the main actor | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 4.4 | Build the Noto-inspired main window | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 4.5 | Build native General, Editor, and Theme settings | pending | Approved plan; awaiting Gate 5 implementation unlock |

### Stage 5 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 5.1 | Prove accessibility and keyboard-only operation | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 5.2 | Measure the published performance budgets | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 5.3 | Automate the final source and release audit | pending | Approved plan; awaiting Gate 5 implementation unlock |
| 5.4 | Complete dogfood and destructive failure injection | pending | Approved plan; awaiting Gate 5 implementation unlock |

| Stage | Outcome | State | Approval gate |
|---|---|---|---|
| 0 | Preserve baseline, remove deferred surfaces from the active target, and lock known failures with regressions | verified | User approved Stage 0 on 2026-07-14; commits `61be30c`, `f7c765a`, `81d0865` |
| 1 | Establish one `DocumentSession`, one TextKit 2 editor attachment, and correct text ownership | in progress | Task 1.5 starting; user approval required after Tasks 1.1–1.5 |
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
| 2026-07-14 | Clarify atomic-write scope: user files and internal JSON use `AtomicFileWriter`; scalar preferences write only through typed `SettingsStore` | `AGENTS.md`, `ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md` |
| 2026-07-14 | Align Task 0.1 regression ownership with the exact test names approved in later stage task blocks | `IMPLEMENTATION_PLAN.md`, `docs/recovery/REGRESSION_MATRIX.md` |
| 2026-07-14 | User explicitly approved aligning the live pointer to Task 0.2 and removing the invalid standalone 1024px app-icon child so containment has zero project-owned warnings | `AGENTS.md`, `IMPLEMENTATION_PLAN.md`, `TRACKER.md`, app icon catalog |
| 2026-07-14 | User approved the complete Stage 0 evidence matrix and authorized Recovery Stage 1 | `AGENTS.md`, `TRACKER.md` |

## Blockers

None. Task 1.5 is in progress, not blocked.

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
| 2026-07-14 | Gate 4E plan | Settings, theme, metrics, visual, accessibility, performance, policy, dogfood, test-count, and whitespace review | verified | `8d8ed19`, `a12199e` |
| 2026-07-14 | Gate 5 consistency | Authority, invariant, product coverage, file/type, task/test arithmetic, historical status, and deferred-scope review | verified | Approved; unlock commit pending |
| 2026-07-14 | Task 0.1 baseline | `git show`; XcodeGen; prototype build; full prototype tests; regression-name and whitespace checks | verified | 35 tests, zero failures; known SwiftUI, asset, and AppIntents diagnostics; commit `61be30c` |
| 2026-07-14 | Task 0.2 containment | Focused red/green test; generated-project source scan; prototype diff; clean build; full tests; Computer Use window inspection | verified | Expected `RecoveryStage` compile failure; 2 focused and 3 full tests pass; no prototype project references or implementation diffs; malformed icon warning removed; Xcode AppIntents no-dependency diagnostic remains tool-generated; commit `f7c765a` |
| 2026-07-14 | Task 0.3 policy | Focused red/green policy tests; clean warning-as-error build; full tests; whitespace check | verified | Two selected tests failed as expected, then 6 focused and all 7 Stage 0 tests passed; build used `-warnings-as-errors`; no project warnings; Xcode AppIntents no-dependency diagnostic remains tool-generated; this policy commit |
| 2026-07-14 | Stage 0 approval | User approval after the complete containment, policy, manual UI, test, and clean-working-tree matrix | verified | Approved; Stage 1 authorized |
| 2026-07-14 | Task 1.1 document boundaries | Missing-type compile failure; 2 focused tests; warning-as-error build; 9 full tests; invariant, scope, and whitespace review | verified | This task commit |
| 2026-07-14 | Task 1.2 document session | Missing-session compile failure; 4 focused tests; warning-as-error build; 13 full tests; invariant, scope, and independent review | verified | This task commit |
| 2026-07-14 | Task 1.3 TextKit 2 attachment | Missing-editor compile failure; SDK numeric ambiguity reproduced and type-qualified; 2 focused tests; empty forbidden-access scan; warning-as-error build; 15 full tests; independent review | verified | This task commit |
| 2026-07-14 | Task 1.4 native editor synchronization | Missing-delegate compile failure; 3 focused tests; native undo and exactly-once callback evidence; empty forbidden-access scan; warning-as-error build; 18 full tests; independent lifecycle review | verified | This task commit |

## Current Manual Acceptance Matrix

Stage 0 implementation is in progress. These checks remain `pending` until Tasks 0.1–0.3 produce fresh evidence.

| Check | Expected | State | Evidence |
|---|---|---|---|
| Prototype preservation | Prototype implementation directories have no diff from `a1f36f6` | verified | `git diff --exit-code a1f36f6` over all prototype implementation directories returned 0 |
| Active source boundary | Generated project contains `RecoveryBaseline` and no prototype implementation source | verified | Prototype filename scan of generated `project.pbxproj` returned no matches |
| Deferred surface removal | Launched app exposes none of the recovery-milestone deferred surfaces | verified | Computer Use inspection showed one containment window with only recovery title and explanation |
| Warning and test policy | Warnings are errors; the 7 Stage 0 tests pass | verified | Generated build uses `-warnings-as-errors`; 7 tests passed with zero failures |
| Dependency and network policy | No runtime packages or network entitlements | verified | Policy tests confirm no `packages` declaration and no client/server network entitlement |
| CI parity | CI uses the approved local build and test commands without deployment override | verified | Policy test confirms exact build/test commands and no `MACOSX_DEPLOYMENT_TARGET` override |

## Update Protocol

1. Set exactly one task to `in progress`; all other unfinished tasks remain `pending` unless genuinely blocked.
2. Record failing baseline evidence before implementation and fresh passing evidence before `verified`.
3. Keep the `AGENTS.md` and `TRACKER.md` stage pointers identical in the same commit.
4. Record decisions that alter scope, behavior, architecture, task order, or acceptance.
5. Do not advance a stage, clear the implementation lock, or reinterpret a failed gate without explicit user approval.
6. At an approval gate, stop and present the changed files, evidence, open risks, and the next proposed gate.
