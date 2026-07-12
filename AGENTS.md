# AGENTS.md — Scratchpad

Rules for every coding agent working on this repo. `SPEC.md` is the full spec; `IMPLEMENTATION_PLAN.md` has your tasks. If anything here conflicts with your instincts, these rules win. If a task seems to require breaking one, STOP and ask the human.

## Current Stage

> **Stage: 0 — Foundation** (update this pointer when a stage merges)

Work ONLY on the current stage. Never start the next stage, never "prepare" for future stages, never scaffold deferred features.

## What This App Is

Scratchpad: scratch-first, local-first, native macOS Markdown editor/workspace. Sublime/Zed austerity. Never loses text. Swift 6 + SwiftUI shell + AppKit `NSTextView` (TextKit 2). macOS 26+.

## Hard Rules (violating any is a defect, no exceptions)

```text
H1. NEVER access NSTextView.layoutManager — it silently downgrades to TextKit 1.
    Use textLayoutManager / textContentStorage only.
H2. NEVER subclass NSTextStorage. Apply attributes to the existing storage.
H3. No force-unwrap (!), no try!. Use guard let / if let / do-catch.
H4. NSTextStorage and all AppKit objects: main actor only.
H5. All persisted file access via BookmarkManager (actor).
H6. ALL writes (user files AND internal JSON) via AtomicFileWriter.
H7. ZERO third-party runtime dependencies. Never add a package. Dev tools
    allowed: XcodeGen, SwiftLint, swift-format, create-dmg.
H8. No print(). Use os.Logger("com.scratchpad.app", category: <service>).
H9. No network code of any kind. No network entitlements.
H10. Never delete session/recovery files on parse failure — quarantine them
     (rename into quarantine/ with timestamp).
```

## Text Ownership (memorize)

Open-document text lives ONLY in its `NSTextStorage`. No model has a mutable `text: String`. No two-way String binding. Models hold metadata: id, url?, lastSavedHash, saveState, cursor, scroll, generation (Int, ++ on every edit). Whole-text replacement happens only in `replaceEntireContents(_:)` (file open / external reload / restore). Undo belongs to the text view's `undoManager` — don't touch it.

## Concurrency Map (do not invent isolation)

- `@MainActor`: all UI, AppModel, BufferStore, DocumentManager, WorkspaceModel, EditorCoordinator, ThemeManager, every NSTextStorage
- `actor BookmarkManager` — scoped bookmarks only
- `actor SessionWriter` — sole writer of session/recovery JSON
- `actor FileIndexer` — workspace scan + fuzzy index
- Background tasks: pure tokenizer functions only

Async→text-system results use the generation protocol: capture `(bufferID, generation)` on main → compute in background → on main, discard if `generation` changed, else apply.

## File Safety Invariants

```text
I1. Original files change only on explicit user save.
I2. Hot exit writes recovery copies — never originals.
I3. Every write is atomic (temp file → atomic replace).
I4. Mark clean ONLY after verified successful write.
I5. Pre-save staleness check (mtime+hash); mismatch ⇒ conflict flow.
I6. Delete a recovery buffer only after the save that supersedes it.
I7. Corrupt state files are quarantined, never deleted.
```

## Workflow (per task)

1. One task at a time, in plan order. Read the task's full block first.
2. TDD for all pure logic: write the failing test, run it, see it fail, implement, see it pass.
3. Build with zero warnings: `xcodegen && xcodebuild -scheme Scratchpad -destination 'platform=macOS' build`
4. Run tests: `xcodebuild -scheme Scratchpad -destination 'platform=macOS' test`
5. Commit per task, conventional commits: `feat: …` / `fix: …` / `test: …` / `chore: …`
6. Never expand scope. Never add features not in the current task. Never refactor unrelated code.

## Style

- `struct` for models; `@Observable final class` for view models; actors per the map above only.
- Typed error enums per service. User-facing failures = non-modal banners.
- Match existing naming: services end in Manager/Store/Writer/Indexer.
- Comments explain *why*, not *what*. No commented-out code.

## Deferred (do not build, do not scaffold, do not "future-proof" for)

Live preview · WYSIWYG · plugins · AI · MCP · terminal · export · custom themes · tree-sitter · SwiftData · Sparkle · command palette beyond ⌘P · multi-window · workspace search · wiki links · localization · sync.
