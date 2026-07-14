# SPEC.md — Scratchpad Recovery Milestone

> **Authority:** This file defines product behavior, user-visible requirements, scope, and acceptance criteria. `ARCHITECTURE.md` defines implementation boundaries. `IMPLEMENTATION_PLAN.md` defines task order. If they disagree, stop work and resolve the documents before changing code.

## 1. Product

Scratchpad is a scratch-first, local-first, native macOS prompt and Markdown editor.

The recovery milestone has one promise:

> Launch or summon Scratchpad, type immediately, and trust that the correct text will remain available through saves, failures, quits, and crashes.

The current prototype is not a release baseline. This milestone deliberately returns to one document window and rebuilds reliability before tabs, workspaces, highlighting, or global capture return.

## 2. Recovery Milestone Scope

The milestone includes:

- one native macOS document window;
- one untitled or file-backed document at a time;
- `NSTextView` editing on TextKit 2;
- native macOS editing plus a fixed Sublime-style shortcut profile;
- undo and redo for native edits and every custom text command;
- UTF-8 plain-text open, save, and Save As;
- atomic writes and explicit external-change conflicts;
- silent session and unsaved-text restoration;
- persistent security-scoped bookmarks under the real App Sandbox;
- a Noto-inspired title area and information bar;
- approximate prompt-token count;
- native General, Editor, and Theme settings;
- fixed System, Light, and Dark appearances;
- user-facing non-modal error banners; and
- automated and manual data-loss gates.

The milestone excludes:

- tabs and multiple open documents;
- workspace folders and sidebar;
- Quick Open;
- Zen window and global hotkey;
- Markdown syntax highlighting;
- line numbers;
- custom or rebindable shortcuts;
- editable theme colors or theme files;
- an information HUD;
- preview, WYSIWYG, plugins, AI, MCP, terminal, export, sync, and networking; and
- release packaging or distribution.

Excluded features must be disabled, not repaired, scaffolded, or partially exposed during recovery.

## 3. Non-Negotiable Product Rules

```text
P1. Original user files change only after an explicit Save or Save As.
P2. Unsaved text is preserved independently from original files.
P3. A failed save leaves the document open, dirty, and recoverable.
P4. External changes are never overwritten silently.
P5. Restoration is silent and mandatory; there is no discard-on-launch prompt.
P6. Corrupt internal state is quarantined, never deleted.
P7. The window never displays or edits text belonging to another document.
P8. The application contains no network code or network entitlement.
P9. The application has zero third-party runtime dependencies.
P10. A green build without behavioral evidence is not acceptance.
```

## 4. Document Lifecycle

### 4.1 Launch

On launch, Scratchpad performs exactly one of these outcomes:

1. Restore the previous dirty or untitled document from recovery.
2. Reopen the previous clean file-backed document from disk.
3. If no restorable document exists, create an empty untitled document.

The editor becomes first responder without a welcome screen or file picker.

Restoration includes text, document identity, file association, save state, selection, and vertical scroll position. Restored dirty text remains visibly edited.

### 4.2 New document

`⌘N` requests a new untitled document.

- If the current document is clean or empty, replace it immediately.
- If it contains unsaved text, present Save / Discard / Cancel.
- Save replaces the document only after verified save success.
- Discard removes the superseded recovery record, then creates the new document.
- Cancel changes nothing.

### 4.3 Open

`⌘O` opens one `.md`, `.markdown`, `.mdown`, or `.txt` file selected through `NSOpenPanel`.

- Resolve the current document through the same Save / Discard / Cancel flow used by New.
- Reject invalid UTF-8 without modifying the selected file or current document.
- On success, show the selected file's text and metadata exactly once.
- Repeated or simultaneous requests for the same URL must not create duplicate document state.

### 4.4 Save

`⌘S` performs Save.

- For an untitled document, Save opens Save As.
- For a file-backed document, Save checks disk staleness before writing.
- A successful write is re-read or otherwise verified before the document becomes clean.
- A failed write leaves the document open and edited and displays a recovery-preserving banner.

`⇧⌘S` always performs Save As. Save As creates or replaces a UTF-8 file only after normal macOS panel confirmation. It associates the document with the new URL only after verified write success.

The editor preserves the original file's LF or CRLF line-ending convention on Save. New documents use LF.

### 4.5 Close and quit

`⌘W` requests window close. `⌘Q` requests application termination.

- Clean or empty documents close immediately after session metadata is flushed.
- Edited documents present Save / Discard / Cancel.
- Save waits for verified success before close or termination continues.
- Failed save cancels close or termination automatically.
- Discard explicitly deletes the superseded recovery record.
- Cancel returns focus to the editor.

Normal termination is reported as clean only after current recovery and session state have been written successfully.

## 5. Save States

Every document is in one user-visible state:

| State | Meaning | Required behavior |
|---|---|---|
| Untitled | Empty document with no file URL | `⌘S` invokes Save As |
| Edited | Text differs from the last saved or initial state | Recovery active; title shows `— Edited` |
| Clean | File text matches verified saved state | May reload an external change |
| Conflicted | Disk contents changed since the known base | Require Overwrite / Reload / Save As / Cancel |
| Deleted | Associated file disappeared | Keep text open; Save may recreate after confirmation |
| Read Only | Destination cannot be written | Keep text open; offer Save As |

An untitled document becomes Edited after its first text mutation. No state transition may delete recoverable text implicitly.

## 6. External Change Behavior

Scratchpad checks file metadata and content before every Save.

| Current state | Disk event | Behavior |
|---|---|---|
| Clean | Modified | Reload from disk, preserving a valid selection; show a subtle update notice |
| Edited | Modified | Enter Conflicted state |
| Any file-backed state | Deleted | Enter Deleted state and retain editor text |
| Any file-backed state | Permission lost | Enter Read Only state and retain editor text |

The conflict interface provides:

- **Overwrite:** explicitly replace disk content with editor text.
- **Reload from Disk:** replace editor text only after confirmation that unsaved changes will remain recoverable until the reload succeeds.
- **Save As:** write editor text to another location.
- **Cancel:** preserve the editor and disk unchanged.

## 7. Main Window UI

The window follows the supplied Noto-inspired mockups:

- standard native macOS traffic lights;
- centered document icon and title;
- `Untitled` or filename when clean;
- `Untitled — Edited` or `filename — Edited` when modified;
- editor content beginning below the native title region;
- no floating traffic lights over editor text;
- no custom toolbar, tab strip, sidebar, line numbers, or syntax colors;
- generous, consistent editor padding; and
- a single bottom information bar.

Default window size is 820 × 640 points. Minimum size is 480 × 320 points. The last user-selected frame is restored.

The editor defaults to SF Mono 15 pt and a 1.45 line-height multiple. It wraps long lines by default. The insertion point, selection, text, and background remain legible in every fixed appearance.

## 8. Information Bar

The information bar is visible by default and shows:

```text
72 characters · 14 words · 8 lines · ~21 tokens          Unicode (UTF-8)
```

Metrics are defined as follows:

- **Characters:** Swift extended-grapheme count. When whitespace counting is off, whitespace characters are excluded.
- **Words:** non-empty runs separated by Unicode whitespace.
- **Lines:** newline count plus one; an empty document reports one line.
- **Estimated tokens:** zero for empty text; otherwise `ceil(UTF-8 byte count / 4)`.
- **Encoding:** `Unicode (UTF-8)` for all recovery-milestone documents.

The `~` token prefix is mandatory. Help text states: “Estimated token count. Exact counts vary by model.”

Metrics update within 150 ms after an edit without putting document text into SwiftUI state and without interrupting typing or selection.

The information bar can be enabled or disabled in Editor settings. HUD mode is not available.

## 9. Keyboard Behavior

### 9.1 Native behavior

Standard `NSTextView` behavior remains intact for text input, marked text, movement, selection, deletion, clipboard operations, undo, redo, find, and Services.

The application must not replace native command routing with a general key-event monitor. In particular, `⌘Delete`, Option-modified movement/deletion, input methods, and accessibility commands retain native behavior.

### 9.2 Application shortcuts

| Action | Shortcut |
|---|---|
| New document | `⌘N` |
| Open | `⌘O` |
| Save | `⌘S` |
| Save As | `⇧⌘S` |
| Close window | `⌘W` |
| Find | `⌘F` |
| Settings | `⌘,` |
| Quit | `⌘Q` |

### 9.3 Fixed Sublime-style profile

| Command | Shortcut |
|---|---|
| Duplicate line or selection | `⇧⌘D` |
| Delete line | `⌃⇧K` |
| Move line or selected lines up | `⌃⌘↑` |
| Move line or selected lines down | `⌃⌘↓` |
| Select line | `⌘L` |
| Join lines | `⌘J` |
| Indent | `⌘]` |
| Outdent | `⌘[` |
| Insert line after | `⌘Return` |
| Insert line before | `⇧⌘Return` |

Each custom command must:

- fire once per shortcut;
- use the normal text-system edit path;
- preserve a valid selection;
- create one coherent undo operation;
- avoid mutating attributes unrelated to the command; and
- remain inactive when the editor is not first responder.

Custom shortcut configuration is deferred.

## 10. Settings

Settings use native General, Editor, and Theme sections.

### 10.1 General

- **Launch at Login:** off by default.
- **Open Recovery Folder:** opens the application recovery directory in Finder.

Silent restoration and unsaved-text preservation are mandatory and cannot be disabled.

### 10.2 Editor

| Setting | Default | Behavior |
|---|---|---|
| Font | SF Mono 15 pt | Choose any installed font with the native font chooser |
| Smart substitutions | Off | Disable automatic quote and dash substitution when off |
| Spelling checking and correction | Off | Disable continuous checking and automatic correction when off |
| Insert spaces instead of tabs | Off | Affects future Tab insertion only |
| Tab width | 4 columns | Range 1–8 |
| Keep indentation on new lines | On | Carry leading indentation into the new line |
| Count whitespace in characters | Off | Changes only the displayed character metric |
| Information bar | On | Show or hide the bottom bar |

Changing spaces-versus-tabs never rewrites existing text.

### 10.3 Theme

- **System:** default; follows current macOS appearance.
- **Light:** fixed Noto-inspired light palette.
- **Dark:** fixed Noto-inspired charcoal palette.
- A non-editable preview shows font, foreground, background, selection, and information-bar treatment.

User-editable colors and custom theme files are deferred.

## 11. Recovery and Persistence Behavior

Unsaved recovery snapshots are written two seconds after the latest edit. A later edit replaces the pending snapshot for that document with a snapshot of the newest text.

Recovery is flushed immediately when:

- the application resigns active because of termination or system shutdown;
- the window closes;
- the user begins New or Open replacement flow; or
- the application receives its termination request.

Session state records document identity, file association, save state, selection, scroll position, encoding, line endings, disk base metadata, and clean-termination status.

Corrupt session, recovery, or bookmark files are moved to a timestamped quarantine directory. A quarantine failure is surfaced and the original corrupt file remains untouched.

Orphan recovery files remain discoverable in the recovery directory. Scratchpad never silently deletes recovery data it cannot associate safely.

## 12. Errors and User Decisions

Routine failures appear in a non-modal banner above the information bar. A banner contains a concise message and only actions that preserve user text.

Modal sheets are reserved for decisions that can discard or overwrite content:

- Save / Discard / Cancel before replacement, close, or quit;
- Overwrite / Reload / Save As / Cancel for conflicts; and
- confirmation before recreating a deleted file at its original URL.

Logging supplements visible error handling; it never replaces it.

## 13. Technology Constraints

```text
- Swift 6 with complete strict concurrency.
- macOS 26 minimum deployment target.
- SwiftUI application and settings shell.
- AppKit NSTextView using TextKit 2 for editing.
- Observation framework; no Combine state pipelines.
- Codable JSON plus UserDefaults for scalar preferences.
- App Sandbox enabled with persistent security-scoped bookmarks.
- Zero third-party runtime dependencies.
- Zero network code and zero network entitlements.
```

## 14. Performance Budgets

| Interaction | Budget |
|---|---|
| Cold launch to typeable restored editor | Under 400 ms for a 1 MB document |
| Keystroke to visible text | No dropped frames at 120 Hz for documents up to 2 MB |
| Information metrics update | Within 150 ms without blocking text input |
| Recovery snapshot after idle | 2.0–2.5 seconds after the final edit |
| Save of a 2 MB local file | Under 250 ms excluding user-panel interaction |
| Window close after clean state | Under 100 ms |

Files larger than 2 MB remain editable, but only correctness—not the interactive budgets above—is guaranteed during recovery.

## 15. Automated Acceptance

The suite must include:

- document state-transition tests;
- editor attachment and text-ownership integration tests;
- selection and undo tests for every custom command;
- UTF-8 open and invalid-encoding tests;
- atomic save, failed save, read-only, deleted, and staleness-conflict tests;
- Save-and-Close ordering tests;
- session and recovery round trips;
- latest-keystroke flush tests;
- corrupt-state quarantine tests;
- bookmark persistence and stale-bookmark tests;
- metrics tests including Unicode, whitespace, empty text, and token estimates;
- settings default and persistence tests; and
- build verification under Swift 6 complete strict concurrency.

Every regression test must be observed failing for the intended reason before its implementation task begins.

## 16. Manual Data-Loss Gate

All scenarios must pass on a signed sandboxed Debug or Release build:

1. Type into an untitled document, force-quit, relaunch, and recover the latest text.
2. Edit a file, force-quit, relaunch, and recover unsaved text with its file association.
3. Deny a save, confirm the document remains open and edited, then Save As successfully.
4. Modify the file externally while Scratchpad has unsaved edits and confirm no silent overwrite.
5. Delete the file externally and confirm the editor text survives.
6. Choose Save while closing and confirm the window closes only after success.
7. Cancel New, Open, Close, and Quit decisions and confirm text and selection remain unchanged.
8. Relaunch and confirm security-scoped access without another panel selection.
9. Exercise every custom shortcut and undo it.
10. Switch System appearance between Light and Dark and confirm editor readability.
11. Change every Editor preference and confirm one immediate, stable update without UI feedback loops.
12. Verify VoiceOver names for the editor, title state, banner, information bar, and settings controls.

The milestone cannot advance with an unexecuted or failing manual scenario.

## 17. Deferred Return Order

After the recovery milestone is accepted and dogfooded, features may return only in this order:

1. Tabs and multi-document management.
2. Workspace and a native split-view sidebar.
3. Quick Open.
4. Zen window and global hotkey.
5. Incremental background Markdown highlighting.
6. Release packaging and distribution.

Each returning feature requires a spec amendment, its own implementation stage, regression tests, and a manual acceptance gate.

## 18. Definition of Done

The recovery milestone is done only when:

- every included behavior above exists;
- every excluded subsystem is absent from the active product;
- the build succeeds with zero project warnings;
- the full automated suite passes;
- every manual data-loss scenario passes and is recorded in `TRACKER.md`;
- `AGENTS.md` and `TRACKER.md` point to the same completed stage;
- the user approves the Noto-inspired UI against the supplied mockups; and
- the app has been used for real prompt writing without a known data-loss or document-identity defect.
