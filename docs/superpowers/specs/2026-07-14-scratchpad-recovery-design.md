# Scratchpad Recovery Design

**Status:** Approved
**Date:** 2026-07-14  
**Scope:** Replace the unsafe prototype core with a trustworthy single-document editor before restoring advanced features.

## 1. Outcome

Scratchpad will recover in place rather than restart in a new repository. The project keeps its Swift 6/XcodeGen shell, product identity, assets, history, and reusable pure utilities, but replaces the editor, document lifecycle, persistence, file access, command routing, and application-state plumbing.

The first recovery milestone intentionally supports exactly one document window. It ships only after text ownership, undo, save, restoration, crash recovery, keybindings, settings, and the Noto-inspired interface pass automated and manual gates.

Tabs, workspace/sidebar, Quick Open, Zen/global hotkey, and Markdown highlighting are disabled during recovery. They return one at a time only after the single-document foundation is accepted.

## 2. Product Contract

The recovery milestone must let a user:

- launch directly into an empty untitled document;
- type with native macOS editing behavior and a fixed Sublime-style command profile;
- undo and redo every text-changing command correctly;
- open, edit, save, and Save As plain-text files;
- quit, crash, or lose a write permission without losing unsaved text;
- relaunch into the same document, text, selection, and scroll position;
- see explicit conflict and failure states instead of relying on logs;
- configure editor behavior through native settings; and
- use a calm, document-first interface matching the supplied Noto mockups.

The milestone is not complete merely because it builds or unit tests pass. Its data-loss and interaction acceptance matrix must pass in full.

## 3. Authoritative Documents

The live repository will have five authoritative documents:

| Document | Authority |
|---|---|
| `SPEC.md` | Product behavior, UI contract, acceptance criteria, and scope |
| `ARCHITECTURE.md` | Component boundaries, ownership, data flow, concurrency, and invariants |
| `IMPLEMENTATION_PLAN.md` | Ordered TDD tasks, exact files, commands, and commit boundaries |
| `TRACKER.md` | Current stage, task state, blockers, decisions, and verification evidence |
| `AGENTS.md` | Short always-loaded rules and the single current-stage pointer |

`MASTER_CANON.md`, `ARCHITECTURAL_REVIEW_REPORT.md`, the pre-recovery implementation plan, the council plans, and the release-plan bundle are historical inputs. They may explain a past decision but cannot override the five live documents.

When live documents disagree, work stops until the inconsistency is resolved. Agents do not choose the convenient interpretation.

## 4. Delivery Governance

Only one recovery task is in progress at a time. Every task uses this gate:

1. Confirm that the task belongs to the current stage in `TRACKER.md`.
2. Write or identify a behavioral test that fails for the intended reason.
3. Record the failing command and concise failure evidence.
4. Implement only the task's behavior.
5. Run the focused tests.
6. Run the complete build and test suite.
7. Perform the named manual check for UI, file access, recovery, or lifecycle work.
8. Review the change against `SPEC.md`, `ARCHITECTURE.md`, and the hard invariants.
9. Commit one coherent task.
10. Record the commit and verification evidence in `TRACKER.md`.

A task cannot be marked complete from code inspection alone. A stage cannot advance while any required automated test, manual scenario, build, or review gate is red. New features cannot be used to work around a failed foundational gate.

## 5. Recovery Architecture

### 5.1 Component map

```text
NativeDocumentWindow
        |
        v
EditorHost (NSTextView, TextKit 2)
        |
        v
DocumentSession (@MainActor)
        |
        +-- NSTextStorage: sole owner of open text
        +-- EditorCommandRouter: native and Sublime-style commands
        +-- FileService: open, save, Save As, and conflicts
        +-- RecoveryCoordinator: snapshots and awaited flushes
        +-- DocumentMetrics: characters, words, lines, estimated tokens

ApplicationModel (@MainActor)
        +-- DocumentSession
        +-- SettingsStore
        +-- BannerState

Persistence services
        +-- BookmarkStore (actor)
        +-- SessionRepository (actor)
        +-- AtomicFileWriter (stateless writer)
```

### 5.2 Text and document ownership

`DocumentSession` is a main-actor observable reference type. It owns one `NSTextStorage` and observable metadata: stable identifier, file URL, display name, save state, generation, selection, scroll position, encoding, last-known disk modification date, and last-saved content hash.

The `NSTextStorage` is the sole mutable owner of open text. SwiftUI never owns or two-way binds a document `String`. Text snapshots are read on the main actor only for saving, recovery, metrics, and pure background work.

`EditorHost` attaches its TextKit 2 stack to the session storage once. The first recovery milestone has no document switching, eliminating ambiguous representable identity. When tabs return, editor identity and storage attachment must be proven by integration tests before tab UI is added.

### 5.3 Command routing

Editor commands use AppKit's responder and command-selector mechanisms. There is no general-purpose local key event monitor for editor shortcuts.

Native macOS movement, selection, deletion, clipboard, undo, redo, and text-input behavior remain authoritative. A fixed Sublime-style macOS profile adds:

- duplicate line or selection;
- delete line;
- move line or selected lines up/down;
- select line;
- join lines;
- indent/outdent;
- insert line before/after; and
- later-stage document navigation commands when tabs return.

Every text-changing command must participate in the text view's undo manager, call the sanctioned edit path once, preserve a valid selection, and have a regression test. Custom/rebindable shortcuts are deferred.

### 5.4 Recovery and termination

`RecoveryCoordinator` owns recovery scheduling for the active document. Its pending work is keyed by document identity rather than shared globally. Each scheduled write captures the latest main-actor snapshot at execution time, not an earlier edit's text.

Application backgrounding and termination request an awaited flush of dirty recovery state and session metadata. The clean-termination flag is set only after both writes succeed. Failure leaves the recovery state intact and is logged without claiming a clean close.

Restoration reconstructs metadata and text deliberately:

- a dirty or untitled document restores from recovery;
- a clean file-backed document reopens from disk;
- a dirty file-backed document restores recovery text plus its base disk metadata;
- corrupt state is quarantined and never deleted; and
- an orphan recovery record remains discoverable instead of silently disappearing.

### 5.5 Files, bookmarks, and conflicts

The App Sandbox is actually enabled. `BookmarkStore` persists security-scoped bookmark data atomically, resolves stale bookmarks, and balances every successful access start with a stop.

All writes, including new files and internal JSON, go through `AtomicFileWriter`. A file-backed save performs a disk existence and staleness check, writes atomically, re-reads metadata, verifies the resulting content, marks the document clean, then removes the superseded recovery record.

Closing a dirty document cannot begin until save or discard is resolved. Choosing Save closes only after verified success. A failed save leaves the document open and dirty.

External-change conflicts enter explicit application state with Overwrite, Reload from Disk, Save As, and Cancel actions. File deletion keeps the buffer open. User-facing failures appear in a non-modal banner and never exist only in logs.

### 5.6 Application and settings state

`ApplicationModel` is the single observable root for the document, settings, and banner state. Views do not communicate through `UserDefaults.didChangeNotification`.

`SettingsStore` exposes typed preferences and uses `UserDefaults` only as its persistence backend for scalar values. Preference mutations update the model directly and persist once per deliberate change; high-frequency pointer movement never writes preferences.

## 6. Noto-Inspired Interface

### 6.1 Main window

The main window uses a native macOS document presentation:

- standard traffic lights;
- centered document icon and title;
- `Untitled` or filename when clean;
- `Untitled — Edited` or `filename — Edited` when modified;
- editor content beginning below the title region;
- generous, consistent editor padding;
- no tab strip, sidebar, line numbers, or syntax colors; and
- a bottom information bar visible by default.

The information bar shows:

```text
72 characters · 14 words · 8 lines · ~21 tokens          Unicode (UTF-8)
```

The token count is explicitly approximate. Empty text reports zero; non-empty text reports `ceil(UTF-8 byte count / 4)` and always uses the `~` prefix. Help text explains that exact counts vary by model. The implementation remains offline and dependency-free. Character counting respects the user's whitespace-counting preference.

### 6.2 Appearance

The recovery milestone provides fixed System, Light, and Dark themes, with System selected by default. Their editor surfaces, title region, separators, selection, caret, and information bar match the visual weight and contrast of the supplied mockups. System follows the current appearance.

The default editor font is SF Mono 15 pt with a 1.45 line-height multiple. The user may choose another installed font through the native font chooser. User-editable theme colors and custom theme files are deferred.

### 6.3 Settings

Settings use native General, Editor, and Theme sections.

**General** contains a Launch at Login toggle, off by default, and an Open Recovery Folder action. Restoration is mandatory, silent, and not configurable; a preference can never disable preservation of unsaved text.

**Editor** contains the font chooser and these explicit defaults:

- smart quote/dash substitution disabled;
- automatic spelling correction disabled;
- tabs insert tab characters rather than spaces;
- tab width is four columns;
- indentation carries onto new lines;
- whitespace is excluded from the displayed character count; and
- the information bar is visible.

Each setting is directly editable. Spaces-versus-tabs changes future insertion behavior and never rewrites existing text.

**Theme** contains the fixed System/Light/Dark picker and a non-editable editor preview. The information bar supports enabled and disabled states only; HUD mode is deferred.

## 7. Recovery Stages

### Stage 0: Baseline and containment

Preserve the prototype revision, disable deferred subsystems, establish the live documents, and add regression coverage for known lifecycle and data-loss failures.

### Stage 1: Document and editor core

Build the single `DocumentSession` and TextKit 2 editor attachment. Prove text ownership, selection, scroll, dirty state, and undo behavior.

### Stage 2: Command system

Implement the fixed Sublime-style macOS profile through AppKit command routing. Prove transformations, selections, undo, and native-command compatibility.

### Stage 3: Recovery and files

Implement per-document recovery, awaited lifecycle flushes, persistent bookmarks, actual sandboxing, atomic saves, close safety, and conflict flows.

### Stage 4: Noto-inspired shell

Implement the native document title, fixed appearances, information bar, approximate token count, and General/Editor/Theme settings.

### Stage 5: Hardening gate

Run the complete automated, manual data-loss, accessibility, performance, and warning-free build matrices. The milestone becomes usable only when every required result is recorded as passing in `TRACKER.md`.

## 8. Required Regression Scenarios

The new plan must include automated or manual coverage for each known failure:

- switching document identity never displays or edits another document when tabs later return;
- two simultaneous open requests for one URL produce one document;
- Save-and-Close waits for successful save and remains open on failure;
- rapid edits in separate future documents cannot cancel each other's recovery;
- clean file restoration reloads disk contents rather than an empty buffer;
- dirty file restoration retains the base hash and can enter conflict handling;
- termination flushes the latest keystroke;
- security-scoped access survives relaunch under the real sandbox;
- editor commands fire once, preserve undo, and cannot intercept Zen commands later;
- the information bar updates without copying text into SwiftUI state;
- preference changes do not use global defaults notifications; and
- future sidebar resizing uses a native split view without gesture/layout feedback.

## 9. Deferred Feature Return

After the recovery milestone, features return in this order:

1. Tabs and multi-document management, including in-flight open deduplication.
2. Workspace and sidebar through a native split-view implementation.
3. Quick Open.
4. Zen window and global hotkey using the shared command registry and visible registration errors.
5. Incremental background Markdown highlighting with generation validation.
6. Release packaging and distribution.

Each feature requires a focused spec amendment, its own implementation stage, regression tests, manual acceptance evidence, and a green tracker gate. No deferred subsystem is scaffolded during the recovery milestone.

## 10. Tracker Contract

`TRACKER.md` starts at Recovery Stage 0 and contains:

- the single current stage and current task;
- one checkbox row per planned task;
- task states limited to `pending`, `in progress`, `blocked`, and `verified`;
- a blocker section containing the evidence and the user decision required;
- a decision log containing date, choice, and affected documents;
- a verification table containing command, result, date, and commit; and
- the manual acceptance matrix for the current stage.

Only `verified` tasks count toward stage completion. Changing a task to `verified` requires fresh evidence in the same tracker update. The stage pointer in `AGENTS.md` and `TRACKER.md` must always match.

## 11. Acceptance Standard

The recovery succeeds when the single-document editor is boringly reliable: the correct text is always visible, native editing and the approved commands behave predictably, every close/save decision is explicit, restoration survives forced termination, settings update without UI feedback loops, and the interface matches the approved Noto-inspired contract.

Only after that foundation is dogfooded and accepted may the project resume feature development.
