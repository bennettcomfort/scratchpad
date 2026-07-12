# SPEC.md — Scratchpad v1

> **Audience:** the implementing coding agent. This document is self-contained — every rule you need is stated here, not referenced elsewhere. If this file and any other document disagree, ask the human; do not guess.
> **Derived from:** `MASTER_CANON.md` + `docs/superpowers/specs/2026-07-11-scratchpad-identity-design.md` (2026-07-11). Regenerated on Canon change — never hand-edit into divergence.

---

## 1. What Scratchpad Is

**Scratchpad** is a scratch-first, local-first, native macOS Markdown editor and workspace.

The v1 promise, stated as a test:

> Press a global hotkey from anywhere — or launch the app — and be typing into a buffer instantly. Open a folder of Markdown files and work across them like a workspace. Quit — or crash — and relaunch to find everything exactly as you left it, including unsaved text. Nothing the user types is ever lost.

Identity: *fast and austere like Sublime Text, scratch-capture-first, workspace-capable like VS Code, impossible to lose text in.* Aesthetic: Sublime/Zed austerity — near-zero chrome, syntax color is the only decoration. Governing UI rule (testable): **at rest, with no workspace open, Scratchpad renders text and nothing else.**

## 2. Non-Negotiables

```text
- Native macOS app (Swift). No Electron. No Tauri. No web views for editing.
- User documents remain plain files on disk. No proprietary content database.
- Zero network access. No network entitlements in the binary.
- Original files change ONLY on explicit user save.
- No silent data loss. No silent overwrite of external changes.
- No WYSIWYG, preview, plugins, or AI features in v1.
- ZERO third-party runtime dependencies. Dev-only tools allowed:
  XcodeGen, SwiftLint, swift-format, create-dmg.
```

## 3. Technology Stack (fixed — do not substitute)

| Layer | Decision |
|---|---|
| Language | Swift 6, strict concurrency enabled |
| Minimum OS | macOS 26 (Tahoe) |
| UI shell | SwiftUI — one main `Window` scene + one AppKit-managed zen window |
| Editor | AppKit `NSTextView` on **TextKit 2**, wrapped via `NSViewRepresentable` |
| Observation | `@Observable` (Observation framework). No Combine. |
| Persistence | Codable JSON (Application Support) + `UserDefaults` for scalar prefs. No SwiftData, no Core Data. |
| File access | `FileManager` + security-scoped bookmarks; App Sandbox ON |
| Project generation | XcodeGen (`project.yml` in repo; `.xcodeproj` gitignored) |
| Testing | XCTest; manual data-loss QA gate before releases |
| Distribution | Developer ID signed, notarized, stapled `.dmg` |

## 4. Hard API Rules (violating any of these is a defect)

```text
H1. NEVER access NSTextView.layoutManager — touching it silently downgrades
    the view to TextKit 1. Use textLayoutManager / textContentStorage only.
    Debug builds assert textView.textLayoutManager != nil after setup.
H2. NEVER subclass NSTextStorage. Apply attributes to the existing storage.
H3. NEVER force-unwrap (!) and never use try!. Use guard let / if let / do-catch.
H4. NSTextStorage and ALL AppKit objects are touched on the main actor only.
H5. All persisted file access goes through BookmarkManager (actor).
H6. ALL file writes — user files AND internal JSON — go through AtomicFileWriter.
H7. No new package dependencies, ever. If one seems necessary, STOP and ask.
H8. No print(). Use os.Logger (subsystem "com.scratchpad.app", category per service).
```

## 5. Text Ownership Model (load-bearing)

**While a document is open, its text lives in exactly one place: its `NSTextStorage`.**

- No model type has a mutable `text: String` property. No two-way String binding anywhere.
- Each open buffer owns one `NSTextStorage` (created at open, retained for background tabs — preserves per-tab undo via the text view's `undoManager`).
- Models hold **metadata only**: id, file URL/bookmark (nil for scratch buffers), display name, `lastSavedHash`, `lastKnownDiskMTime`, `saveState`, cursor location, scroll offset, `generation` (Int, incremented on every edit).
- Reading text (for save/snapshot): `storage.string` on the main actor at moment of use.
- Writing text into storage happens in exactly ONE method — `replaceEntireContents(_:)` — used only for file open, external reload, and session restore. It preserves selection and scroll where valid.
- Dirty detection: `NSTextStorage` delegate edit notifications set `saveState = .dirty` and increment `generation`.

```swift
enum SaveState: String, Codable {
    case clean, dirty, conflicted, deletedOnDisk, readOnly, scratch
}
```
(`scratch` = never saved to any file; the untitled state.)

## 6. Concurrency Topology (fixed — do not invent isolation)

| Lane | Members | Rule |
|---|---|---|
| `@MainActor` | All SwiftUI/AppKit, `AppModel`, `BufferStore`, `DocumentManager`, `WorkspaceModel`, `EditorCoordinator`, `ThemeManager`, every `NSTextStorage` | Only lane that touches UI or text storage |
| `actor BookmarkManager` | bookmark create/resolve/start/stop | Sole owner of scoped access |
| `actor SessionWriter` | ALL session + recovery JSON writes | Single writer ⇒ no torn state |
| `actor FileIndexer` | workspace scan, file index, fuzzy query | Returns Sendable value types |
| Background tasks | tokenizer runs (pure `String` → tokens) | No shared mutable state |

**Async round-trip protocol (the only sanctioned pattern for returning async results to the text system):** capture `(bufferID, generation, snapshot)` on main → compute in background (pure function) → back on main, `guard buffer.generation == captured else { discard }` → apply.

## 7. File Safety Invariants

```text
I1. Original files change only on explicit user save (⌘S / Save All / Save As).
I2. Hot exit writes recovery copies to Application Support — never originals.
I3. Every write is atomic: temp file in destination directory → atomic replace
    (FileManager.replaceItemAt or write(to:options:.atomic) for same-volume temp).
I4. A buffer is marked clean ONLY after a verified successful write.
I5. Before saving, compare disk mtime+hash to last-known; mismatch ⇒ conflict
    flow, never silent overwrite.
I6. Recovery buffers are deleted only after the successful save that supersedes them.
I7. Unparseable session/recovery files are QUARANTINED (renamed into quarantine/
    with timestamp), never deleted; the app then starts cleanly.
```

Save pipeline (⌘S): verify exists → staleness check (I5) → encode UTF-8, preserving the file's original line endings → temp write + atomic replace (I3) → re-read mtime/hash → mark clean (I4) → delete recovery buffer (I6). On ANY failure: stay dirty, keep recovery buffer, surface error banner.

External-change matrix:

| Buffer | Disk event | Behavior |
|---|---|---|
| clean | modified | reload silently; subtle "updated from disk" note |
| dirty | modified | `= .conflicted`; on save show: Overwrite / Reload from Disk / Save As / Cancel |
| any | deleted | keep buffer open; `= .deletedOnDisk`; Save recreates; Save As available |
| any | moved / permission lost | mark missing; offer locate / reselect workspace |

## 8. Scratch Buffers & Hot Exit

**Scratch buffers are a first-class persistent collection**, not transient tab state:

- `⌘N` (in-app) and the global summon both create scratch buffers.
- Each scratch buffer gets a recovery file at creation; appears in `⌘P` as "Scratch — <first-line preview>"; survives until saved to a file (Save As) or explicitly closed-with-discard.
- The main window launches directly into a scratch buffer — never a welcome screen or file dialog.

**Hot exit restores silently. There is NO restore prompt.** Relaunch reproduces: open buffers (file-backed and scratch), active buffer, unsaved text, cursor, scroll, window frames (both windows), sidebar width, theme, layout settings. Restored dirty buffers simply appear dirty.

Storage layout:

```text
~/Library/Application Support/Scratchpad/
  session/latest-session.json      # schemaVersion, workspace bookmark, buffers,
                                   # active buffer, cursors, scrolls, window
                                   # frames, sidebar width, theme id
  recovery/buffer-<uuid>.json      # schemaVersion, bookmark/path or nil,
                                   # unsaved text, baseDiskHash, timestamp
  quarantine/                      # corrupt files moved here (I7)
  logs/
```

Every JSON schema carries `schemaVersion: Int` (start at 1). Snapshot cadence: session metadata on structural events (buffer open/close/switch, window/sidebar change, background, terminate); recovery buffers debounced **1–3 s** after edits while dirty. Cursor movement alone never causes disk writes. A `didCloseCleanly` UserDefaults flag distinguishes crash from quit (diagnostics only — restore behavior is identical).

## 9. The Two Windows

**Main window:** hidden title bar (full-size content; traffic lights float over the editor margin), no toolbar ever, sidebar hidden until a workspace opens (`⌘\` toggles, slides in with hairline divider), tab bar materializes only at 2+ open buffers (text-only tabs, dirty dot, × on hover), status bar is one muted line (~60% opacity: word count · line:col · save state), toggleable.

**Zen scratch window** — the signature feature:

- Summoned by a **global hotkey** (default `⌃⌥Space`, rebindable in Settings), registered via **`RegisterEventHotKey`** (Carbon; sandbox-safe; requires no accessibility permission). Do not use CGEvent taps.
- On press: find the screen containing `NSEvent.mouseLocation` → center the zen window there (initial ~640×400; remembers user resize) → create a fresh scratch buffer → focus, typeable instantly.
- A real window (hidden title bar, movable, resizable) — not a floating overlay panel. Only one ever exists; re-press moves/re-summons it.
- Contains ONLY the editor: no tabs, no status bar. Same theme/highlighting as main editor.
- Exits: **`⌘⏎` = copy entire buffer to clipboard + dismiss** (subtle "Copied" flash). **`Esc` = dismiss only.** Settings toggle "Esc also copies" (default OFF). Dismissed buffers always survive.
- Works while the app runs; Settings offers a launch-at-login toggle via `SMAppService.mainApp`.

## 10. Workspace, Sidebar, Navigation

- Open folder: `NSOpenPanel` (`⇧⌘O`), directories only → create security-scoped bookmark → persist → resolve on relaunch (stale ⇒ refresh or prompt reselect).
- Scan on `actor FileIndexer`, never on main. Visible types: `.md .markdown .mdown .txt`. Ignore: `.git .DS_Store node_modules .build DerivedData dist out target venv .env` + hidden files. Sort folders first, then case-insensitive alphabetical.
- Sidebar v1 operations: open file, Reveal in Finder, Copy Path, New File. (Rename/Delete/New Folder deferred.)
- **⌘P quick switcher:** centered overlay ≤ 600 pt; empty query shows recents + scratch buffers; fuzzy scoring: exact filename 100 · prefix 80 · consecutive 60 · subsequence 40 · path-segment +15 · recent +10 · open tab +5. `↑/↓/⏎/⎋`.
- Find in file: `⌘F` via `NSTextView.usesFindBar = true` (nearly free — do not build custom find UI).

## 11. Markdown Highlighting

- Pure function, no AppKit imports: `MarkdownTokenizer.tokenize(lines: [Substring], initialState: LineState) -> [Token]` — TDD-first.
- Line-oriented; carried state: in-fence, in-frontmatter. On edit, re-tokenize damaged line range extended to enclosing block boundaries.
- Priority: fenced code blocks → YAML frontmatter → headings → blockquotes → lists → horizontal rules → inline code → bold → italic → links.
- Debounce 100–250 ms; apply via generation-counter protocol (§6); attributes only — **never mutates characters**; preserves selection.
- Files > 2 MB: highlighting disabled, subtle banner.

## 12. Themes & Layout

4 built-in themes, Codable JSON bundled in Resources, hex color strings:

| Theme | Character |
|---|---|
| **Scratch Dark** (hero, default) | Near-black, Zed-like, muted syntax hues |
| **Scratch Light** | Paper-white counterpart, same hue relationships |
| **System** | Follows macOS appearance → maps to the two above |
| **High Contrast** | Accessibility, both appearances |

Theme schema: `{ schemaVersion, id, name, isDark, colors: { editorBackground, editorForeground, caret, selection, sidebarBackground, lineHighlight }, syntax: { heading, bold, italic, code, codeBlockBackground, link, quote, listMarker, frontmatter, rule } }`.

All UI chrome is grayscale; color appears only in syntax + one accent (selection/caret). Hairline dividers 0.5 pt. No icons where a word is shorter.

Layout settings (persisted, live-applied): font family (default SF Mono), size (default 15, range 9–32), line-height multiple (default 1.45, range 1.0–2.5), paragraph spacing, editor max width (default 800 pt, full-width toggle), alignment (default left), wrapping (default on), line numbers (default off).

## 13. Keyboard Shortcuts (final)

| Action | Key | | Action | Key |
|---|---|---|---|---|
| Summon zen (global) | `⌃⌥Space` | | Quick switcher | `⌘P` (Print removed) |
| Zen: copy all + dismiss | `⌘⏎` | | Find in file | `⌘F` |
| Zen: dismiss | `Esc` | | Toggle sidebar | `⌘\` |
| New scratch buffer | `⌘N` | | Settings | `⌘,` |
| Open file | `⌘O` | | Next / prev tab | `⌘}` / `⌘{` |
| Open workspace | `⇧⌘O` | | Font + / − / reset | `⌘+` / `⌘−` / `⌘0` |
| Save / Save As / Save All | `⌘S` / `⇧⌘S` / `⌥⌘S` | | Close tab | `⌘W` |

## 14. Performance Budgets (testable acceptance criteria)

| Metric | Budget |
|---|---|
| Cold launch → typeable (restored session, 5 buffers) | **< 400 ms** |
| Global hotkey → zen window typeable (app running) | **< 150 ms** |
| Keystroke → screen, ≤ 2 MB file | no dropped frames (120 Hz) |
| `⌘P` open / tab switch | **< 50 ms** |
| Workspace scan, 10k files | sidebar interactive < 1 s (async) |
| Full-file highlight, 1 MB | < 100 ms or auto-degrade |
| Quit with 10 dirty buffers | < 2 s fully persisted |
| Memory, 20 open buffers | < 300 MB |
| App binary | < 20 MB |

## 15. Testing Requirements

- **TDD-mandatory (pure logic):** MarkdownTokenizer, FuzzyMatcher, AtomicFileWriter, session/recovery/theme codecs, hashing, dirty-state logic, ignore-list filtering, zen screen-picking logic. Failing test first, always.
- **Integration (temp dirs):** FileService open/save/missing/read-only/encoding; staleness detection; bookmark round-trip; session snapshot/restore; recovery lifecycle; quarantine.
- **UI smoke:** open→edit→save; ⌘P; settings persistence.
- **Manual data-loss QA (release gate):** kill -9 mid-typing → relaunch → nothing lost; failed save stays dirty; external modify → conflict; external delete → buffer survives; untitled scratch with text → quit → restored.
- **Debug assertions:** TextKit 2 active per editor; recovery-file count == dirty-buffer count after debounce; session JSON round-trips on write.

## 16. v1 Scope

**Must ship:** everything in §§5–14, plus recents, error banners, app icon, accessibility labels, signed/notarized DMG.

**Deferred — do NOT build, do NOT scaffold hooks for:** live preview · WYSIWYG · plugins · AI features · MCP · terminal · export (HTML/PDF/Pandoc) · custom theme editor / user theme loading · tree-sitter · SwiftData · Sparkle · command palette beyond ⌘P · multi-window / detachable tabs · workspace-wide search · wiki links · localization · sync.

## 17. Stage Order (summary — details in IMPLEMENTATION_PLAN.md)

0 Foundation · 1 App shell · 2 Editor core + scratch buffers · 3 Hot exit · **4 Zen summon (☆ daily-usable scratchpad)** · 5 File open/save · 6 Tabs · 7 Workspace · 8 ⌘P + recents (☆ full daily driver) · 9 Highlighting · 10 Themes/layout · 11 Hardening (conflicts, file watching) · 12 Polish · 13 Release.

Rationale: the product is a complete usable scratchpad before it is a workspace; hot exit lands before file I/O (scratch buffers need only the recovery store) and gets the longest soak time.
