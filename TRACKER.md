# TRACKER.md — Scratchpad Recovery

> **Current stage:** Recovery Stage 3 — Data-safe persistence and lifecycle
> **Current phase:** Implementation
> **Next task:** Task 3.8 — await window close and application termination
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
| 1.5 | Replace containment shell with the single editor | verified | Expected missing-`ApplicationModel` compile failure and missing-`TextEditingCommands` policy failure captured; 6/6 focused and 18/18 full tests pass; warning-as-error build, source scans, and all eight manual checks pass; this task commit |

### Stage 2 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 2.1 | Define command values and UTF-16 line geometry | verified | Expected missing-`LineTable` compile failure captured; 3/3 focused and 21/21 full tests pass; warning-as-error build, whitespace check, and independent review pass; this task commit |
| 2.2 | Implement and prove pure command transformations | verified | Expected missing-router compile failure captured; 13/13 focused and 34/34 full tests pass; warning-as-error build and whitespace check pass; independent review findings reproduced, fixed, and re-reviewed; this task commit |
| 2.3 | Apply commands through one undoable AppKit transaction | verified | Expected missing-action compile failure captured; 4/4 focused and 38/38 full tests pass; one-step undo, exactly-once edit accounting, selection-only cleanliness, attribute preservation, TextKit 2 scan, warning-as-error build, and independent review pass; this task commit |
| 2.4 | Route fixed shortcuts through the first responder | verified | Expected missing-`AppCommands` compile failure captured; 2/2 focused and 40/40 full tests pass; warning-as-error build, responder routing, native compatibility, monitor scan, complete shortcut/Undo matrix, and independent review pass; this task commit |

### Stage 3 Task Ledger

| Task | Deliverable | State | Evidence |
|---|---|---|---|
| 3.1 | Establish atomic persistence and canonical internal paths | verified | Trusted-root quarantine, serialized transactions, 15/15 focused tests, 55/55 full tests, warning-free build, and independent review pass; this task commit |
| 3.2 | Persist and quarantine session and recovery records | verified | Missing-record and five data-integrity regression REDs; 12/12 focused and 67/67 full tests pass; warning-free build; identity, canonical filename, schema, quarantine, invariant, scope, data-loss, and whitespace checks pass; this task commit |
| 3.3 | Enable sandboxed persistent security-scoped bookmarks | verified | Expected missing-type RED plus four controller regression REDs; 11/11 focused and 78/78 full tests pass; FIFO public-operation serialization, duplicate standardized-path quarantine, warning-as-error build, exact signed entitlements, invariant, scope, and data-loss checks pass; this task commit |
| 3.4 | Open, inspect, and atomically save UTF-8 files | verified | Coordinated conditional replacement; 18/18 Task 3.4 focused tests; three independent 96/96 suites; warning-free build; controller review approved; this task commit |
| 3.5 | Debounce recovery per document and restore the correct source | verified | Corrected design `7a39707`; fresh stale-flush, launch-model compile, production-root policy, production edit-route, and nil-bookmark regressions; 17/17 focused and 113/113 full tests; both races 5/5; warning-as-error build; task and broad reviews clean; seeded recovery-first, clean-disk-first, and initial-focus manual checks pass; this task commit |
| 3.6 | Serialize native panels, decisions, and destructive document operations | verified | Feature `c72680c`; generation-race fix `b3dc20d`; 13/13 focused and 126/126 full tests; warning-as-error build and independent review pass |
| 3.7 | Monitor external changes without document-identity races | verified | Feature `8e5a018`; cancellation fix `9ff333e`; 8/8 focused and 134/134 full tests; warning-as-error build and independent review pass |
| 3.8 | Await window close and application termination | in progress | Automated gate verified at 147/147 after controller corrections; signed-sandbox 12-row matrix and controller review remain pending |

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
| 1 | Establish one `DocumentSession`, one TextKit 2 editor attachment, and correct text ownership | verified | User approved Stage 1 on 2026-07-15; commits `988a539`, `3bdacc9`, `3a1e4af`, `2e8c4c7`, `2b703b5` |
| 2 | Route native and fixed Sublime-style commands once, with correct selections and undo | verified | User approved Stage 2 on 2026-07-15; commits `cfaed34`, `04ef7ce`, `c804391`, `9d04dc0` |
| 3 | Make recovery, bookmarks, sandboxed file access, saves, conflicts, close, and quit data-safe | in progress | Task 3.8 in progress; user approval required after Tasks 3.1–3.8 |
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
| App Sandbox and persistent security-scoped bookmarks are absent | Enable the real sandbox and persist refreshed bookmarks atomically | 3 | verified |
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
| 2026-07-15 | User approved the complete Stage 1 evidence matrix and authorized Recovery Stage 2 | `AGENTS.md`, `TRACKER.md` |
| 2026-07-15 | Place Join Lines immediately before native text-editing commands in Edit so `⌘J` wins over native Jump to Selection without removing `TextEditingCommands` or other native menus | `Scratchpad/App/AppCommands.swift`, `TRACKER.md` |
| 2026-07-15 | User approved the complete Stage 2 responder, shortcut, Undo, native-editing, and focus matrix and authorized Recovery Stage 3 | `AGENTS.md`, `TRACKER.md` |
| 2026-07-15 | User approved correcting Task 3.1 to inject trusted Application Support paths, reject quarantine escapes, and serialize overlapping persistence transactions | `IMPLEMENTATION_PLAN.md`, `TRACKER.md` |
| 2026-07-16 | User approved continuous execution through the end of Stage 3; corrected stale cumulative test totals after Task 3.5 expanded the suite to 113 tests | `AGENTS.md`, `IMPLEMENTATION_PLAN.md`, `TRACKER.md` |
| 2026-07-16 | Task 3.6 controller review added three suspended-boundary generation regressions; updated the remaining cumulative targets from 123/128/134 to 126/131/137 | `IMPLEMENTATION_PLAN.md`, `TRACKER.md` |
| 2026-07-16 | Task 3.7 controller review added three cancellation and lifecycle regressions; updated the remaining cumulative targets from 131/137 to 134/140 | `IMPLEMENTATION_PLAN.md`, `TRACKER.md` |

## Blockers

None.

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
| 2026-07-14 | Task 1.5 editor-core shell | Missing-root-model compile failure; missing-native-Find policy failure; 6 focused tests; warning-as-error build; 18 full tests; empty TextKit 1 and deleted-source scans; whitespace and scoped-diff review; eight-item Computer Use matrix | verified | One root model and one native editor window; standard `TextEditingCommands` restores native Find; this task commit |
| 2026-07-15 | Stage 1 approval | User approval after the complete ownership, TextKit 2, native editing, source-boundary, automated, and manual matrix | verified | Approved; Stage 2 authorized |
| 2026-07-15 | Task 2.1 command geometry | Missing-`LineTable` compile failure; 3 focused tests; warning-as-error build; 21 full tests; UTF-16, CRLF/LF, range-boundary, scope, and independent review | verified | This task commit |
| 2026-07-15 | Task 2.2 pure command transformations | Missing-router compile failure; all ten commands covered; two review regressions captured for trailing-empty-line deletion and newline-inclusive movement; 13 focused tests; warning-as-error build; 34 full tests; clean follow-up review | verified | This task commit |
| 2026-07-15 | Task 2.3 AppKit command transaction | Missing-responder-action compile failure; 4 focused AppKit tests; one grouped undo for all nine text changes; select-line remains clean; attributes preserved; warning-as-error build; 38 full tests; empty TextKit 1 scan; independent review | verified | This task commit |
| 2026-07-15 | Task 2.4 responder shortcuts | Missing-`AppCommands` compile failure; 2 focused responder tests; warning-as-error build; 40 full tests; empty key-monitor scan; complete live shortcut, Undo, native-editing, non-editor-focus, and menu matrix; independent review | verified | This task commit |
| 2026-07-15 | Stage 2 approval | User approval after the complete command transformation, AppKit transaction, responder routing, native compatibility, automated, and manual matrix | verified | Approved; Stage 3 authorized |
| 2026-07-15 | Task 3.1 atomic persistence | Missing-type, trusted-path, same-destination overlap, and source-lock RED evidence; 15 focused tests; warning-as-error build; 55 full tests; invariant and forbidden-source scans; independent review and clean re-review | verified | This task commit |
| 2026-07-15 | Task 3.2 session and recovery persistence | Missing-type RED plus controller regressions for mismatched recovery identity, noncanonical siblings, and unsupported write schemas; 12 focused tests; sorted schema-version-1 JSON; independent recovery and deletion checks; quarantine success and source-preserving failure; warning-as-error build; 67 full tests; invariant, scope, data-loss, and whitespace review; no manual check required | verified | This task commit |
| 2026-07-15 | Task 3.3 sandboxed bookmark persistence | Expected missing-type RED plus deterministic controller REDs for rollback interleaving, stale-refresh access interleaving, concurrent initial quarantine, and duplicate standardized paths; 11 focused tests; all public operations serialized through one FIFO continuation gate with private non-recursive bodies; same-standardized-URL identity reuse; persist-before-return and stale-refresh-before-access ordering; exactly-once stop accounting; active-token forget refusal; corrupt, unsupported, duplicate-ID, and duplicate-standardized-path quarantine; quarantine-failure source preservation; no path-hint fallback; warning-as-error build; 78 full tests; signed app contains exactly app sandbox, user-selected read/write, and app-scoped bookmark entitlements; invariant, scope, data-loss, and whitespace review; no separate manual check required | verified | This task commit |
| 2026-07-15 | Task 3.4 sandbox file service | Initial RED plus controller regressions for late external mutation, conditional temporary cleanup, unknown writer errors, and read-failure provenance; 19/19 AtomicFileWriter tests; 14/14 FileService tests; 18/18 Task 3.4 focused tests; late-race case 5/5; warning-as-error build; three independent 96/96 full suites; 23-branch exact token cleanup matrix; live file/conditional-write coverage; H1–H14, scope, data-loss, and whitespace review; independent controller approval | verified | Coordinated conditional Save preserves typed missing, read-only, conflict, read, write, and verification outcomes; production app entry unchanged; windowless responder fixtures removed the unrelated XCTest animation crash; signed-app external-edit check remains at the Stage 3 integration gate; this task commit |
| 2026-07-15 | Task 3.5 recovery coordination | Missing-`RecoveryClock` compile RED plus dirty-file-association behavioral RED; all seven exact virtual-clock recovery tests; 7/7 focused tests; warning-as-error build; 103/103 full suite; H1–H14, scope, orphan-preservation, no-wall-sleep, and whitespace review; no manual check required by the task | in progress | Per-document debounce captures identity only and snapshots current storage after virtual two-second completion; explicit flush persists latest text; launch selects recovery, disk, or empty without deleting orphan recovery; recovered text uses sanctioned whole-text replacement; launch session is written unclean before restore returns; awaiting controller review |
| 2026-07-15 | Task 3.5 launch-restoration correction | Controller review reproduced stale in-flight write ordering, stale pending-generation clearing, and absent production launch invocation; written design committed as `7a39707` and approved by the user | in progress | Scope now includes live dependency composition, fail-closed editor gating, retry, recovery bookmark authority, nonempty untitled dirty state, two suspended-repository races, production-root policy coverage, warning-as-error/full-suite verification, and a live no-empty-editor-flash check |
| 2026-07-16 | Task 3.5 corrected TDD and automated verification | Fresh race RED completed `testExplicitFlushWaitsForInFlightWriteAndFinishesNewest` as `["flushed", "old"]` and left `"old"` final; launch-gate RED failed compilation because `ApplicationServices`, `LaunchState`, injected factory, retry, and `restoreCurrentLaunchAttempt` were absent; production-root policy RED failed the live-model, `.task(id:)`, and ready-branch assertions. The two source-authority regressions were added after the prior uncommitted correction and passed without weakening, preserving the controller-captured RED evidence. | in progress | Per-document token/FIFO correction: 9/9 initial recovery GREEN, then 11/11 recovery GREEN; launch-gate 2/2 GREEN; production policy 1/1 GREEN; exact Task 3.5 suite 14/14; both suspended-write races 5/5 each; `xcodegen` succeeded; installed Xcode rejected the brief's literal `-warnings-as-errors` option with exit 64, so the equivalent explicit `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build` succeeded; full suite 110/110; `git diff --check`, H1–H14/prohibited-source scans, no-wall-clock-test-sleep scan, project source-list review, and self-review pass. Manual seeded-recovery/no-empty-editor-flash and clean-disk-first launch checks remain for controller/user; independent review and single commit remain pending by process instruction. |
| 2026-07-16 | Task 3.5 independent-review blocker correction | Review found the ready-branch `EditorHost` relied on its default no-op edit closure, so production typing never scheduled recovery; review also found declared session/recovery bookmark IDs could resolve to nil and silently degrade to an empty or association-free restore. Fresh compile RED: `ApplicationModel` had no `handleCurrentDocumentEdit`; the same focused command also contained typed nil-bookmark regressions and production wiring policy coverage. | in progress | Added identity/coordinator/ready-validated model edit handling and passed it explicitly to `EditorHost`; added typed `ApplicationModelLaunchError.unresolvedBookmark(UUID)` and fail-closed reference requirements for selected clean sessions and recoveries. New covering set 4/4 GREEN; expanded exact Task 3.5 set 17/17; both suspended-write races 5/5 each; warning-as-error build succeeded; full suite 113/113; `git diff --check`, H1–H14/prohibited-source, force-operation, no-wall-clock-test-sleep, and scope scans pass. Follow-up independent review approved the complete corrected diff with no Critical, Important, or Minor findings. Manual launch checks, tracker verification, and single commit remain pending. |
| 2026-07-16 | Task 3.5 manual launch acceptance and broad review | Sandboxed built app launched against preserved/temporary fixture state, then the original container was restored. Nonempty untitled recovery displayed `RECOVERY-FIRST-CONTENT` as the first editable text; clean file-backed state displayed `DISK-FIRST-CONTENT` while stale recovery remained absent; the text entry was initial first responder in both launches. An invalid command-line bookmark also exercised the fail-closed Retry surface before an app-generated bookmark completed the clean-file check. | verified | Fresh task re-review and whole-task broad review reported no Critical, Important, or Minor findings; manual fixtures and results were moved out of Application Support, and the original sandbox session was restored before commit. |
| 2026-07-16 | Task 3.6 serialized document decisions | Missing-`FilePanelProviding` compile RED; exact coordinator case 1/1 GREEN; native-panel filename-tag RED corrected with an exact delegate and post-selection validator. Review REDs then reproduced launch-gate mutation, invalid-file recovery deletion, stale cleanup canceling a newer recovery flush, and three suspended destructive-boundary generation races. Corrected 13/13 focused tests pass; warning-as-error build; 126/126 full suite; H1–H14, operation, Save As, logging, deferred-scope, generated-source, and whitespace review; no separate manual check required | verified | Feature `c72680c` plus generation-race fix `b3dc20d`; one checked-continuation decision source; awaited New/Open/Save/Save As/Close/Quit; stable identity-plus-generation checkpoints preserve newest recovery and abort stale replacement, exit, and Reload operations; final independent review reported no findings |
| 2026-07-16 | Task 3.7 external-change monitor | Exact focused compile RED failed only for missing `ExternalChangeMonitor` and `startExternalChangeMonitoring`; controller-review RED then retained one idle-operation waiter after monitor restart and allowed a cancelled suspended clean reload to mutate text. Corrected 8/8 focused tests pass; warning-as-error build; 134/134 full suite; virtual cadence, cancellation, automatic open-start, edit-during-reload, clean reload, dirty conflict, missing, read-only, and reselection mappings covered; H1–H14, timing, scope, and whitespace checks pass; no separate manual check required | verified | Feature `8e5a018` plus cancellation fix `9ff333e`; exact waiter cancellation prevents continuation leaks/double resume, stale reloads cannot mutate after cancellation, one main-actor monitor serializes behind operations, and final independent review reported no findings |
| 2026-07-16 | Task 3.8 lifecycle automated gate | Six exact lifecycle tests captured missing-coordinator/AppDelegate compile RED, then passed 6/6 against injected window, termination, decision, repository-flush, and reply boundaries. The real success trace is exactly `decision -> recovery flush -> session(false) -> session(true) -> reply(true)`; recovery and non-clean-session failure traces end in `reply(false)` without a clean write. All 13 Task 3.6 decision tests pass after splitting decision request from gated resolution; warning-as-error build succeeded; final xcresult reports `succeeded` and 140 tests; whitespace, H1–H14, entitlement, dependency, deferred-source, and no-wall-sleep scans pass. | in progress | Window close intercepts once and bypasses once only after approval; AppDelegate owns one `.terminateLater` task/reply; resign-active uses `didCloseCleanly = false` and retains failure for activation. Signed-sandbox matrix and controller review remain pending; Stage 4 is not authorized. |
| 2026-07-16 | Task 3.8 controller-blocker correction | Compile RED failed on the new waiter-state contract before production changes. Added one production decision sheet covering every decision/action, cancellation-safe single-waiter coordination with first-resolution-wins semantics, and serialized resign-active/termination tasks that join cancellation-insensitive flush work. Focused lifecycle, decision, and policy set passed 32/32; warning-as-error build succeeded; full suite passed 147/147; whitespace and invariant scans pass. | in progress | Clean-session write failure now cancels termination without a successful clean record. Signed-sandbox matrix remains 0/12; controller review remains pending; Stage 4 is not authorized. |

## Current Manual Acceptance Matrix

Recovery Stage 2 implementation is verified. These are the fresh checks awaiting explicit user approval before Stage 3.

| Check | Expected | State | Evidence |
|---|---|---|---|
| `⇧⌘D` Duplicate | Duplicate once; one Undo restores input | verified | `one` → `one\none` → Undo `one` |
| `⌃⇧K` Delete Line | Delete current line once; one Undo restores input | verified | `one\ntwo` → `two` → Undo original |
| `⌃⌘↑` Move Up | Move current line once; one Undo restores input | verified | `one\ntwo` → `two\none` → Undo original |
| `⌃⌘↓` Move Down | Move current line once; one Undo restores input | verified | `one\ntwo` → `two\none` → Undo original |
| `⌘L` Select Line | Select exactly the current line without editing | verified | Replacing the selection changed `one\ntwo` to `Xtwo`; Undo of the proof edit restored original; automated test proves no generation/dirty/undo change from selection |
| `⌘J` Join Lines | Join once; one Undo restores input | verified | Initial live check exposed native Jump-to-Selection conflict; final Edit placement gives `one\ntwo` → `one two` → Undo original |
| `⌘]` Indent | Prefix current line once; one Undo restores input | verified | `one\ntwo` → tab + `one\ntwo` → Undo original |
| `⌘[` Outdent | Remove one prefix; one Undo restores input | verified | tab + `one\ntwo` → `one\ntwo` → Undo original |
| `⌘Return` Insert After | Insert one line after; one Undo restores input | verified | `one` → `one\n` → Undo `one` |
| `⇧⌘Return` Insert Before | Insert one line before; one Undo restores input | verified | `one` → `\none` → Undo `one` |
| Non-editor focus | All ten custom shortcuts leave the document unchanged | verified | Native Find field retained first-responder focus through all ten shortcuts; document stayed `one\ntwo` after every invocation |
| Native editing | Movement, deletion, clipboard, marked text, Find, and Services remain native | verified | `⌘Delete`, Option-Left, Option-Delete, cut/paste, dead-key `é`, standard Find bar, full native Edit menus, and Services menu all passed |
| Automated gate | Warning-free build, all tests, and source scans pass | verified | `xcodegen`; build succeeded; 40/40 tests passed; no local/global event monitor or general `keyDown` interception; no TextKit 1 access |
| Task 3.5 recovery launch | Recovered text is first editable content with no empty-editor flash; editor has focus | verified | Sandboxed launch showed `RECOVERY-FIRST-CONTENT`; AX reported the restored text entry as focused |
| Task 3.5 clean launch | Current disk text wins over stale recovery and is first editable content; editor has focus | verified | Sandboxed launch showed `DISK-FIRST-CONTENT`, never stale recovery; AX reported the disk-backed text entry as focused |

### Recovery Stage 3 Signed-Sandbox Matrix

The automated fixtures never read, replace, or delete the user's real Application Support state. The controller must run these rows with an isolated backup/restore procedure against the signed app at `/tmp/ScratchpadStage3/Build/Products/Debug/Scratchpad.app` and record actual observations before Task 3.8 or Stage 3 becomes `verified`.

| Scenario | State | Controller fixture/action and required evidence |
|---|---|---|
| Untitled crash/relaunch | pending manual | Start isolated empty state, type a unique multiline value, set selection/scroll, wait for debounce, force-kill, relaunch; first editable content, selection, and scroll must match. |
| File-backed edited crash/relaunch | pending manual | Open a temporary `.md`, edit without saving, force-kill, relaunch; recovery text must appear edited with the same file association. |
| Clean relaunch after external edit | pending manual | Save and quit a temporary file, mutate its bytes externally, relaunch; disk bytes must appear and stale recovery text must not. |
| Save then immediate Close | pending manual | Edit a temporary file, choose Save and immediately close; window must await the verified write and reopened bytes must match. |
| Failed Save then Close/Quit | pending manual | Make the selected temporary destination fail a coordinated write, then Close and Quit; each operation must cancel while text stays open, edited, and recoverable. |
| Edit while Save is suspended | pending manual | Suspend the temporary-file write after snapshot capture, type a unique suffix, resume; disk must contain the captured snapshot while the suffix remains edited and recoverable. |
| External edit while clean/dirty | pending manual | Externally mutate once while clean and once after a local edit; clean must reload, dirty must enter conflict without replacing local text. |
| Delete or revoke access | pending manual | Delete the selected temporary file, then separately revoke its bookmark access; show deleted/read-only state with no recreation or path fallback. |
| Overwrite/Reload/Save As/Cancel | pending manual | Seed a dirty conflict four times and exercise each action; verify overwrite bytes, disk reload, independent Save As bytes/association, and unchanged local text on Cancel. |
| Bookmark relaunch | pending manual | Select a file outside the container, quit cleanly, relaunch, edit, and save; the same file must reopen and accept a sandboxed save. |
| Repeated Quit | pending manual | With an edited document, invoke Quit repeatedly before resolving once; observe one decision, one flush sequence, and one termination reply. |
| Corrupt JSON | pending manual | Seed corrupt isolated session/recovery JSON, relaunch, and inspect quarantine; successful quarantine moves the file, while an injected quarantine failure leaves original bytes untouched. |

## Update Protocol

1. Set exactly one task to `in progress`; all other unfinished tasks remain `pending` unless genuinely blocked.
2. Record failing baseline evidence before implementation and fresh passing evidence before `verified`.
3. Keep the `AGENTS.md` and `TRACKER.md` stage pointers identical in the same commit.
4. Record decisions that alter scope, behavior, architecture, task order, or acceptance.
5. Do not advance a stage, clear the implementation lock, or reinterpret a failed gate without explicit user approval.
6. At an approval gate, stop and present the changed files, evidence, open risks, and the next proposed gate.
