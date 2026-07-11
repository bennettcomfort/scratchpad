# MASTER CANON — Scratchpad

> **Status:** Authoritative. This is the project's single source of truth.
> **Amended 2026-07-11:** Scratchpad identity design (see `docs/superpowers/specs/2026-07-11-scratchpad-identity-design.md`) — name finalized, scratch-first concept, zen summon window (D-18/D-19), 4 themes, reordered roadmap, tightened budgets, `AGENTS.md` replaces `CLAUDE.md`.
> **Supersedes:** All documents in `Project Plans/` and `markdown_workspace_release_plan_bundle/` (historical inputs — do not consult them for decisions).
> **Audience:** Every human and AI agent working on this project. A new coding agent must be able to begin work from this document alone.
> **Companion:** `ARCHITECTURAL_REVIEW_REPORT.md` explains *why* these decisions were made. This document contains only the decisions.
> **Amendments:** Any change to this document requires an entry in `docs/DECISIONS.md` (append-only ADR log).

---

## 1. Project Vision

**Scratchpad** — a **scratch-first, local-first, native macOS Markdown workspace** for writers, developers, prompt engineers, and documentation authors.

The v1 promise, stated as a test:

> Press a hotkey from anywhere — or launch the app — and be typing into a buffer instantly. Open a folder full of Markdown files and work across them like a workspace. Quit — or crash — and relaunch to find everything exactly as you left it, including unsaved text. Nothing you type is ever lost.

Identity in one line: *fast and austere like Sublime Text, scratch-capture-first, workspace-capable like VS Code, and impossible to lose text in.*

Aesthetic north star: **Sublime Text / Zed austerity** — near-zero chrome, syntax color as the only decoration, high-res sharpness. Governing testable rule: *at rest, with no workspace open, Scratchpad renders text and nothing else.*

## 2. Product Goals

1. **Reliability above all.** The app's brand is "never loses text." Every other goal yields to this one.
2. **Native speed and feel.** Instant launch, instant typing, instant file switching. Feels built by Apple.
3. **Plain text forever.** User documents are ordinary `.md`/`.txt` files on disk. No database, no lock-in, no sync service.
4. **Keyboard-first.** Every core action has a shortcut. Minimal chrome.
5. **Small and honest.** v1 does few things flawlessly rather than many things adequately.

## 3. Non-Negotiables

```text
- Native macOS app (Swift). No Electron. No Tauri. No web views for editing.
- User documents remain plain files on disk. No proprietary content database.
- Zero network access. No network entitlements in the binary.
- Original files change ONLY on explicit user save.
- No silent data loss. No silent overwrite of external changes.
- No WYSIWYG, preview, plugins, or AI features in v1.
- Zero third-party runtime dependencies in v1.
```

## 4. Core Principles

1. **One source of truth per fact.** Text lives in `NSTextStorage`. Decisions live here. State lives in one store each.
2. **Design out, don't guard against.** Prefer architectures where a bug class is impossible over conventions that avoid it.
3. **Pure logic is test-first.** Anything expressible as a pure function (tokenizer, fuzzy matcher, codecs) is built TDD.
4. **Internal state is as sacred as user files.** Session and recovery JSON get atomic writes too.
5. **Boring is a feature.** Platform APIs over packages. Proven patterns over clever ones.
6. **Small verified slices.** One stage in flight at a time; merge only green.

---

## 5. Technology Decisions (Final)

| Layer | Decision | Ref |
|---|---|---|
| Language | Swift 6, strict concurrency enabled | D-01, D-05 |
| Minimum OS | **macOS 26 (Tahoe)**; conservative API use so the floor can drop later | D-02 |
| UI shell | SwiftUI (`Window` scene) — main window + single zen scratch window | D-01, D-14, D-18 |
| Editor core | AppKit `NSTextView` on **TextKit 2**, wrapped via `NSViewRepresentable` | D-03 |
| Observation | `@Observable`. No Combine. | D-06 |
| Persistence | Codable JSON in Application Support + `UserDefaults` for scalar prefs. No SwiftData / Core Data. | D-07 |
| File access | `FileManager` + security-scoped bookmarks; App Sandbox **ON** | D-09 |
| Highlighting | Hand-rolled line-based Markdown tokenizer, attributes only | D-11 |
| File watching | None in v1 core; DispatchSource/FSEvents at Stage 10 hardening | D-12 |
| Build | Xcode + SwiftPM (no runtime packages); SwiftLint/swift-format as dev tools |
| Testing | XCTest (unit + integration), XCUITest (smoke), manual data-loss QA gate |
| CI | GitHub Actions: build + unit tests on every push, from Stage 0 |
| Distribution | Developer ID signed, notarized, stapled `.dmg` (create-dmg). App Store deferred. |

### Hard API Rules (agents: memorize)

```text
1. NEVER access NSTextView.layoutManager — it silently downgrades the view
   to TextKit 1. Use textLayoutManager / textContentStorage. A debug-build
   assertion verifies TK2 remains active.
2. NEVER subclass NSTextStorage. Apply attributes to the existing storage.
3. NEVER force-unwrap (!). Use guard let / if let.
4. NSTextStorage and all AppKit objects are touched on the main actor only.
5. All persisted file access goes through BookmarkManager.
6. All file writes — user files AND internal JSON — go through AtomicFileWriter.
7. No new package dependencies. If one seems necessary, stop and record a
   proposal in docs/DECISIONS.md; do not add it.
```

---

## 6. Architecture

### 6.1 Module Map

```text
┌─ SwiftUI Shell (single Window) ───────────────────────────────┐
│  MainWindowView · Sidebar · TabBar · EditorContainer          │
│  QuickSwitcher overlay · Settings scene · Welcome view        │
└──────────────┬────────────────────────────────────────────────┘
               │ observes (@Observable)
┌──────────────▼──────────── @MainActor ────────────────────────┐
│ AppModel            root composition, lifecycle, commands     │
│ WorkspaceModel      active workspace, file tree, selection    │
│ DocumentManager     open documents, tabs, dirty state, save   │
│ EditorCoordinator   NSTextView bridge, per-document storage   │
│ ThemeManager        active theme, semantic colors             │
│ SettingsModel       editor/layout prefs (UserDefaults-backed) │
└───────┬──────────────┬───────────────┬───────────────┬────────┘
        │              │               │               │
┌───────▼─────┐ ┌──────▼──────┐ ┌──────▼───────┐ ┌─────▼──────┐
│ actor       │ │ actor       │ │ actor        │ │ background │
│ Bookmark    │ │ Session     │ │ FileIndexer  │ │ Highlight  │
│ Manager     │ │ Writer      │ │ (scan +      │ │ tasks      │
│ (scoped     │ │ (session +  │ │  fuzzy index)│ │ (pure      │
│  access)    │ │  recovery   │ │              │ │  tokenize) │
│             │ │  JSON)      │ │              │ │            │
└─────────────┘ └─────────────┘ └──────────────┘ └────────────┘
        Persistence: AtomicFileWriter · JSONStore · ApplicationSupportPaths
```

### 6.2 Text Ownership Model (load-bearing — D-04)

**While a document is open, its text lives in exactly one place: the `NSTextStorage` of its editor.** There is no mutable `text: String` property on any model, and no two-way String binding.

- Each open document owns one `NSTextStorage` (created at open, kept for background tabs — preserves per-tab undo history via the text view's `undoManager`).
- `DocumentModel` holds **metadata only**: file URL/bookmark, display name, `lastSavedHash`, `lastKnownDiskMTime`, `saveState`, cursor/scroll (for persistence).
- Reads (save, recovery snapshot) pull `storage.string` on the main actor at the moment of use.
- Writes to storage happen in exactly one guarded path — `replaceEntireContents(_:)` — used only for file open and explicit external reload. It saves and restores selection and scroll.
- Dirty detection: storage-delegate edit notifications set `saveState = .dirty` and bump the **generation counter** (a monotonically increasing `Int` per document, incremented on every edit).

```swift
enum DocumentSaveState: Codable {
    case clean, dirty, conflicted, deletedOnDisk, readOnly, untitled
}
```

### 6.3 Concurrency Topology (load-bearing — D-05)

| Lane | Members | Rules |
|---|---|---|
| `@MainActor` | All SwiftUI/AppKit, `AppModel`, `WorkspaceModel`, `DocumentManager`, `EditorCoordinator`, `ThemeManager`, every `NSTextStorage` | The only lane that touches UI or text storage |
| `actor BookmarkManager` | security-scoped bookmark create/resolve/start/stop | Sole owner of scoped-access lifecycle |
| `actor SessionWriter` | serializes ALL session + recovery writes | One writer ⇒ no interleaved/torn state files |
| `actor FileIndexer` | workspace scan, file index, fuzzy query | Returns `Sendable` value-type results |
| Background tasks | tokenizer runs (pure functions on `String` snapshots) | No shared mutable state; results are `Sendable` token arrays |

**Highlight round-trip protocol (mandatory pattern):**

```text
main: snapshot = (docID, generation, damagedRange, substring)
  └─▶ background: tokens = MarkdownTokenizer.tokenize(snapshot)   // pure
        └─▶ main: guard document.generation == snapshot.generation else discard
                  apply attributes to textStorage (never mutates characters)
```

Stale results are discarded, never applied. This is the only sanctioned way async work returns to the text system.

### 6.4 File Safety Invariants (load-bearing — D-08)

```text
I1. Original files change only on explicit user save (⌘S / Save All / Save As).
I2. Hot exit writes recovery copies to Application Support — never originals.
I3. Every write (user file or internal JSON) is atomic:
    temp file in destination directory → atomic replace.
I4. A buffer is marked clean ONLY after a verified successful write.
I5. Before saving, compare disk mtime+hash to last-known; mismatch ⇒ conflict
    flow, never silent overwrite.
I6. Recovery buffers are deleted only after the successful save that
    supersedes them.
I7. Unparseable session/recovery files are quarantined (renamed aside with
    timestamp), never deleted; the app then starts cleanly.
```

**Save pipeline (⌘S):**

```text
verify file exists ─▶ staleness check (I5) ─▶ encode UTF-8 (preserve original
line endings) ─▶ temp write + atomic replace (I3) ─▶ re-read mtime/hash ─▶
mark clean (I4) ─▶ delete recovery buffer (I6)
     └─ on ANY failure: remain dirty, keep recovery buffer, surface error
```

**External-change matrix:**

| Buffer state | Disk event | Behavior |
|---|---|---|
| clean | modified | reload silently; subtle "updated from disk" note |
| dirty | modified | `saveState = .conflicted`; on save show: Overwrite / Reload from Disk / Save As / Cancel |
| any | deleted | keep buffer open; `= .deletedOnDisk`; Save recreates, Save As available |
| any | moved / permission lost | mark missing; offer locate / reselect workspace |

### 6.5 Session & Hot Exit (D-08, D-13)

**Restore is silent. There is no restore prompt.** Relaunch reproduces the prior state: workspace, tabs, active tab, unsaved text, cursor, scroll, sidebar width, window frame, theme, layout settings. Restored dirty tabs simply appear dirty.

Storage layout:

```text
~/Library/Application Support/<AppName>/
  session/latest-session.json          # schemaVersion, workspace bookmark,
                                       # tabs, active tab, cursors, scrolls,
                                       # window frame, sidebar width, theme id
  recovery/buffer-<docID>.json         # schemaVersion, bookmark/path or nil
                                       # (untitled), unsaved text,
                                       # baseDiskHash, timestamp
  quarantine/                          # corrupt files moved here (I7)
  logs/
```

Snapshot cadence: session metadata on structural events (tab open/close/switch, window/sidebar change, background, terminate); recovery buffers debounced **1–3 s** after edits while dirty. Cursor movement alone never triggers disk writes. `didCloseCleanly` flag in UserDefaults distinguishes crash from quit (diagnostics only — restore behavior is identical).

**Untitled documents (D-15):** `⌘N` creates an untitled buffer (`saveState = .untitled`). It participates fully in recovery (buffer with `path: nil`). First save runs Save As. Untitled buffers survive quit/crash like any file-backed buffer.

### 6.6 Workspace & File Tree

- Open folder via `NSOpenPanel` (`⇧⌘O`); persist security-scoped bookmark; resolve on relaunch; stale bookmark ⇒ refresh or prompt reselect.
- Scan asynchronously on `FileIndexer`; UI never blocks on enumeration.
- Visible types: `.md .markdown .mdown .txt`. Openable-as-text (v1 optional): `.json .yaml .yml .toml`.
- Default ignore list: `.git .DS_Store node_modules .build DerivedData dist out target venv .env` + hidden files.
- Sort: folders first, then case-insensitive alphabetical.
- v1 sidebar operations: open file, Reveal in Finder, Copy Path, New File (post-Stage 5). Rename/Delete/New Folder → deferred.

### 6.7 Quick Switcher (`⌘P`)

Centered overlay ≤ 600 pt wide; opens < 100 ms. Searches the `FileIndexer` index (filename + relative path). Empty query shows recent files. `↑/↓` navigate, `⏎` opens, `⎋` dismisses.

Fuzzy scoring:

| Signal | Score |
|---|---:|
| Exact filename | 100 |
| Filename prefix | 80 |
| Consecutive chars | 60 |
| Subsequence | 40 |
| Path-segment match | +15 |
| Recently opened | +10 |
| Currently open tab | +5 |

### 6.8 Markdown Highlighting (D-11)

- Pure function: `MarkdownTokenizer.tokenize(lines:state:) -> [Token]` — no AppKit imports, TDD-first.
- Line-oriented with minimal carried state (in-fence, in-frontmatter). On edit, re-tokenize the damaged line range extended to enclosing block boundaries.
- Token classes (priority order): fenced code blocks → YAML frontmatter → headings → blockquotes → lists → horizontal rules → inline code → bold → italic → links.
- Debounce 100–250 ms; apply via the generation-counter protocol (§6.3); **never mutates characters**; preserves selection.
- Files > **2 MB**: highlighting disabled (plain text), banner notes it.

### 6.9 Themes, Fonts, Layout

Theme = Codable JSON bundled in Resources, hex color strings, semantic keys:

```text
Theme { schemaVersion, id, name, isDark,
  colors: { editorBackground, editorForeground, caret, selection,
            sidebarBackground, lineHighlight },
  syntax: { heading, bold, italic, code, codeBlockBackground, link,
            quote, listMarker, frontmatter, rule } }
```

Built-in v1 themes (**4** — austerity-coherent set; Paper/Midnight cut 2026-07-11):

| Theme | Character |
|---|---|
| **Scratch Dark** (hero, default) | Near-black, Zed-like, muted syntax hues |
| **Scratch Light** | Paper-white counterpart, same hue relationships |
| **System** | Follows macOS appearance → maps to the two above |
| **High Contrast** | Accessibility, both appearances |

No custom-theme editor in v1; loading user theme files is v1.2.

Layout settings (persisted, applied live to all open editors): font family (default SF Mono), size (default 15, range 9–32), line-height multiple (default 1.45, range 1.0–2.5), paragraph spacing, editor max width (default 800 pt; "full width" toggle), text alignment (default **left**), line wrapping (default on), line numbers (default off), sidebar visibility.

### 6.10 Zen Scratch Window & Scratch Buffers (D-18, D-19)

**Window model (amends D-14):** one main window + at most one **zen scratch window**. The zen window is a real window (hidden title bar, movable, resizable, remembers size; ~640×400 initial) containing only an editor — no tabs, no status bar.

**Global summon (D-18):** registered via `RegisterEventHotKey` (Carbon — sandbox-safe, no accessibility permission). Default `⌃⌥Space`, rebindable in Settings. On press: find the screen containing `NSEvent.mouseLocation` → center the zen window there → create a fresh untitled scratch buffer → focus it, typeable instantly. Re-press while open re-summons/moves the existing window (never a second one). Launch-at-login toggle via `SMAppService`.

**Zen exits:** `⌘⏎` = copy entire buffer to clipboard + dismiss (signature exit; subtle "Copied" flash). `Esc` = dismiss only. Settings toggle "Esc also copies" (default off — never clobber the clipboard silently). Dismissed buffers always survive (hot exit applies).

**Scratch buffers (D-19):** untitled buffers are a first-class persistent collection, not transient tab state. Each gets a recovery file at creation; appears in `⌘P` as "Scratch — <first-line preview>"; survives until saved to a file (Save As) or explicitly closed-with-discard. Launch behavior: the main window opens straight into a scratch buffer — never a welcome screen or file dialog.

**Chrome recession rules:** no toolbar ever; sidebar hidden until a workspace is opened (`⌘\`); tab bar materializes only at 2+ open buffers (single buffer = zero tab UI; × on hover only); status bar is one muted line (~60% opacity), toggleable. All UI chrome is grayscale — color appears only in syntax and one accent (selection/caret). Hairline dividers (0.5 pt Retina). No icons where a word is shorter; no buttons for keyboard-reachable actions.

### 6.11 Keyboard Shortcuts (Final — conflicts resolved)

| Action | Shortcut | | Action | Shortcut |
|---|---|---|---|---|
| New scratch buffer | `⌘N` | | Quick switcher | `⌘P` (Print removed from menu) |
| Summon zen window (global) | `⌃⌥Space` | | Zen: copy all + dismiss | `⌘⏎` |
| Zen: dismiss | `Esc` | | | |
| Open file | `⌘O` | | Find in file | `⌘F` (native find bar) |
| Open workspace | `⇧⌘O` | | Toggle sidebar | `⌘\` |
| Save | `⌘S` | | Settings | `⌘,` |
| Save As | `⇧⌘S` | | Next / prev tab | `⌘}` / `⌘{` |
| Save All | `⌥⌘S` | | Font size + / − / reset | `⌘+` / `⌘−` / `⌘0` |
| Close tab | `⌘W` | | Undo / Redo | `⌘Z` / `⇧⌘Z` |

(`⌥⌘S` belongs to Save All **only** — the prior double-binding with Toggle Sidebar is resolved to `⌘\`.)

---

## 7. Repository Structure

```text
Scratchpad/                             # repo root
├── AGENTS.md                           # agent rules distilled from this Canon
│                                       # (cross-agent convention; read by pi agent,
│                                       #  Claude Code, and most coding agents)
├── SPEC.md                             # self-contained spec for implementing agents
├── IMPLEMENTATION_PLAN.md              # per-stage task packets with acceptance criteria
├── MASTER_CANON.md                     # this document (copied into repo at Stage 0)
├── README.md
├── CHANGELOG.md
├── docs/
│   └── DECISIONS.md                    # append-only ADR log for post-Canon changes
├── scripts/
│   ├── build_and_notarize.sh
│   └── make_dmg.sh
├── .github/workflows/ci.yml            # build + unit tests on push
├── Scratchpad.xcodeproj
├── Scratchpad/
│   ├── App/                            # @main, AppDelegate bridge, Commands, MainWindowView
│   ├── Domain/                         # value types only, no UI imports:
│   │   │                               # Workspace, FileNode, DocumentModel,
│   │   │                               # DocumentSaveState, AppSession, RecoveryBuffer,
│   │   │                               # Theme, EditorSettings, RecentItem
│   ├── Services/                       # BookmarkManager, SessionWriter, FileIndexer,
│   │   │                               # DocumentManager, FileService, ThemeManager,
│   │   │                               # RecentItemsStore
│   ├── Editor/                         # EditorRepresentable, EditorCoordinator,
│   │   │                               # MarkdownTokenizer, HighlightApplier, LayoutApplier
│   ├── Features/                       # Welcome/ Sidebar/ Tabs/ QuickSwitcher/ Settings/ StatusBar/
│   ├── Persistence/                    # ApplicationSupportPaths, JSONStore, AtomicFileWriter
│   ├── Utilities/                      # Debouncer, FuzzyMatcher, Hashing,
│   │                                   # EncodingDetector, Logger (os.Logger)
│   └── Resources/                      # Themes/*.json, Assets.xcassets
├── ScratchpadTests/                    # unit + integration (temp-dir based)
└── ScratchpadUITests/                  # smoke flows only
```

Rules: `Domain/` imports Foundation only. `Features/` never touch `Persistence/` directly — always via `Services/`. The tokenizer and fuzzy matcher import no AppKit.

## 8. Documentation Standards

- **Governance docs** (D-16, amended 2026-07-11): `MASTER_CANON.md` (truth), `AGENTS.md` (distillation), `docs/DECISIONS.md` (ADR log) — plus two **generated artifacts** for the implementing agent: `SPEC.md` and `IMPLEMENTATION_PLAN.md`, both derived from the Canon (regenerate on Canon change; never hand-edit them into divergence).
- `AGENTS.md` is a ≤ 150-line distillation: hard API rules (§5), actor topology (§6.3), safety invariants (§6.4), zero-dependency rule, current-stage pointer. It never contradicts the Canon; when in doubt the Canon wins.
- ADR format in `DECISIONS.md`: `## D-xxx — Title / Date / Status / Context / Decision / Consequences`.
- Code comments explain *why*, not *what*. Public service APIs get doc comments.
- `CHANGELOG.md` maintained per release, Keep-a-Changelog format.

## 9. Coding Standards

- Swift 6 strict concurrency; zero warnings policy on `main`.
- `struct` for models; `@Observable final class` for view models; `actor` per §6.3 only — no new actors without an ADR.
- No force unwraps, no `try!`, no `fatalError` outside truly unreachable paths.
- Errors: typed error enums per service; user-facing failures surface as non-modal banners where possible.
- Logging via `os.Logger`, one subsystem, category per service. No `print`.
- Naming: services end in `Manager`/`Store`/`Writer`/`Indexer` per the structure above; follow existing patterns.
- SwiftLint + swift-format run in CI; format-on-save locally.
- Conventional commits (`feat: … / fix: … / test: … / chore: …`); tags `v0.<stage>.x` per stage, `v1.0.0` at release.

## 10. Testing Strategy

**Tier 1 — TDD-mandatory (pure logic):** `MarkdownTokenizer`, `FuzzyMatcher`, `AtomicFileWriter`, session/recovery/theme codecs, `Hashing`, dirty-state logic, ignore-list filtering. Tests written before implementation.

**Tier 2 — Integration (temp directories):** FileService open/save/missing/read-only/encoding; staleness detection; BookmarkManager round-trip; SessionWriter snapshot/restore; recovery lifecycle (create → restore → delete-on-save); quarantine path.

**Tier 3 — UI smoke (XCUITest):** open workspace → open file → edit → save; quick switcher open/navigate; settings persistence.

**Tier 4 — Manual data-loss QA (release gate, every RC):**

```text
□ edit → save → verify on disk           □ edit → quit → relaunch → text restored
□ edit → kill -9 → relaunch → restored   □ save fails (perms) → stays dirty
□ external modify while dirty → conflict □ external delete → buffer survives, Save As works
□ recovery buffer deleted after save     □ cursor/scroll/window/sidebar restore
□ untitled with text → quit → restored   □ 1k-file workspace, 5 MB file, binary file, odd encoding
□ dark/light/high-contrast credible      □ fresh-machine install: signed, notarized, launches
```

**Debug-build assertions:** TextKit 2 active on every editor; recovery-buffer count == dirty-doc count after debounce settles; session JSON round-trips on write.

### Performance Budgets (testable acceptance criteria)

| Metric | Budget |
|---|---|
| Cold launch → typeable (restored session, 5 tabs) | **< 400 ms** |
| Global hotkey → zen window typeable (app running) | **< 150 ms** |
| Keystroke → screen, ≤ 2 MB file | no dropped frames (120 Hz) |
| `⌘P` overlay appearance / tab switch | **< 50 ms** |
| Workspace scan, 10k files | sidebar interactive < 1 s (async) |
| Full-file highlight, 1 MB | < 100 ms or auto-degrade |
| Quit with 10 dirty buffers | < 2 s to fully persisted |
| Memory, 20 open files | < 300 MB |
| App binary | < 20 MB |

## 11. Agent Workflow (D-17)

The project is built by one human orchestrating coding agents — **pi agent running DeepSeek/Kimi models for implementation**, with Claude Code available for planning/review passes. The unit of work is the **stage** (§12); the unit of change is a small, reviewed slice.

Because the implementing models differ from the planning model, the written artifacts carry the discipline: `IMPLEMENTATION_PLAN.md` tasks are small and explicitly bounded, critical constraint blocks are repeated verbatim where they apply, and every task has a "done when" checklist. Assume a capable but drift-prone implementer.

```text
Per stage:
1. Branch: feat/stage-<n>-<slug>. One stage in flight at a time. Never parallel stages.
2. Plan: produce a written implementation plan from this Canon's stage definition
   (files touched, test list, acceptance criteria). Human approves the plan.
3. TDD: Tier-1 logic gets failing tests first, then implementation.
4. Implement in slices small enough to review as a single diff.
5. Verify: build clean (zero warnings), all tests green, exercise the feature
   in the running app — not just tests.
6. Review: automated code review pass (data-loss risk, retain cycles in the
   representable, actor-isolation correctness, Canon compliance) before merge.
7. Merge to main; tag; update CHANGELOG; update AGENTS.md stage pointer.
```

Agent context rules: agents read `AGENTS.md` + `SPEC.md` + the current stage of `IMPLEMENTATION_PLAN.md`; agents do **not** read the superseded planning documents. Agents never expand scope, add dependencies, or invent concurrency — any of those requires stopping and recording a proposal in `docs/DECISIONS.md` for human decision.

## 12. Roadmap & Implementation Order

Stages are strictly sequential. Each has a goal and exit criteria; a stage is done only when exit criteria pass and it is merged to `main`.

Order rationale (2026-07-11): the product is a complete, usable **scratchpad before it is a workspace**. Hot exit lands before file I/O — scratch buffers need only the recovery store, so the dependency order works, and the hardest reliability feature gets the longest soak time.

| Stage | Deliverable | Exit criteria (abridged) |
|---|---|---|
| **0 — Foundation** | Repo, Xcode project (sandbox ON, zero network entitlements), AGENTS.md, CI, **sign→notarize dry-run**, DECISIONS.md seeded | CI green from clean checkout; dry-run notarization succeeds |
| **1 — App shell** | Hidden-titlebar single window, menus/commands, launch-to-empty-buffer, Settings placeholder, ApplicationSupportPaths, Logger | Launches straight to a typeable area; menus wired; no file logic |
| **2 — Editor core** | TextKit-2 `NSTextView` bridge per §6.2, untitled scratch buffers (D-19), undo/redo, cursor/scroll tracking, TK2 assertion | Typing native; no cursor jumps; no update loops |
| **3 — Hot exit** | SessionWriter, AtomicFileWriter (for internal state), recovery buffers, silent restore, quarantine, didCloseCleanly | Full kill-9 test passes: scratch buffers, cursor, window state all restore |
| **4 — Zen summon** | Global hotkey (D-18), cursor-screen centering, zen window, `⌘⏎` copy-exit, launch-at-login toggle | Hotkey→typeable < 150 ms; **☆ dogfooding begins — daily-usable scratchpad** |
| **5 — File open/save** | FileService, open `.md`/`.txt`, ⌘S atomic save, dirty state, **pre-save staleness check**, Save As for untitled | Edit→save→verify externally; failed save stays dirty |
| **6 — Tabs & documents** | DocumentManager, per-doc storage, tab bar (2+ rule), dirty dots, close-dirty prompt, Save All | Multi-file editing safe; per-tab undo preserved |
| **7 — Workspace** | Folder open, BookmarkManager, async scan, sidebar tree (slides in), ignore list | Relaunch restores workspace access; 10k-file budget met |
| **8 — Navigation** | FileIndexer, FuzzyMatcher, ⌘P overlay (includes scratch buffers), recents | Scoring table honored; < 50 ms open. **☆ full daily driver** |
| **9 — Highlighting** | Tokenizer (TDD), generation-counter pipeline, debounce, 2 MB degrade | Token tests green; cursor stable; text never mutated |
| **10 — Appearance** | 4 themes (§6.9), font/layout settings live-applied and persisted | Instant theme switch; settings survive relaunch |
| **11 — Hardening** | Full conflict UX (matrix §6.4), deleted/moved handling, file watching (DispatchSource/FSEvents), find bar polish | External-change matrix fully implemented |
| **12 — Polish** | Status bar (words, line:col, save state), Reveal in Finder, Copy Path, New File, error banners, app icon, accessibility labels, full-screen/multi-monitor | Manual QA checklist (non-release items) passes |
| **13 — Release** | Bundle ID, version, sign, notarize, staple, DMG, release notes | Tier-4 gate passes on a fresh machine; `v1.0.0` tagged |

### Milestones

- **M1 (Stages 0–4): The scratchpad.** ~2–3 weeks. *The identity ships here — summonable, crash-proof, daily-usable.*
- **M2 (5–8): The workspace.** ~2–3 weeks. Files, tabs, folders, ⌘P.
- **M3 (9–10): Fast and beautiful.** ~1–2 weeks. Highlighting + austerity themes.
- **M4 (11–13): Shippable.** ~2 weeks → **v1.0.0**.

(Estimates are planning aids, not commitments; stage exit criteria are the truth.)

## 13. v1 Feature Scope (Frozen)

**Must ship:** app shell · **zen summon window + global hotkey (D-18)** · **persistent scratch buffers (D-19)** · **`⌘⏎` copy-all-and-dismiss** · open file · open workspace (bookmarked) · sidebar tree · TextKit-2 raw Markdown editor · atomic safe save · dirty tracking · tabs · silent hot exit + recovery · cursor/scroll/window restore · quick switcher · recents · **find in file** · syntax highlighting · 4 themes · font/layout controls · launch-at-login toggle · signed/notarized DMG.

**Should ship (cut without guilt if risky):** status bar · Reveal in Finder · Copy Path · New File from sidebar · external-change banner polish · line numbers.

**Deferred (do not build, do not scaffold "hooks" for):** live preview · WYSIWYG · plugins · AI features · MCP · terminal · Pandoc/HTML/PDF export · custom theme editor & user theme loading · tree-sitter · SwiftData · Sparkle · command palette beyond ⌘P · multi-window/detachable tabs · workspace-wide search · wiki links/backlinks · localization · iCloud/sync.

## 14. Deployment Strategy

1. Sandbox ON, hardened runtime, zero network entitlements (verifiable local-first claim).
2. `scripts/build_and_notarize.sh`: archive → export → `notarytool submit --wait` → `stapler staple`. Exercised via dry-run in Stage 0 CI, not first tried at release.
3. `scripts/make_dmg.sh` via create-dmg; DMG itself signed.
4. Distribution: GitHub Releases (default) or product page. `spctl -a -vv` must return *accepted* on a clean machine.
5. Updates: manual download for v1.0. Sparkle is a post-v1 ADR.
6. Versioning: SemVer; `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` set per release.

## 15. Risks (Top — full register in Review Report)

| Risk | Standing mitigation |
|---|---|
| Data loss via save/recovery bug | Invariants §6.4 + Tier-4 gate every RC |
| Torn internal state on crash | Atomic writes for internal JSON + quarantine |
| Editor bridge update loops | Designed out via §6.2 (no dual source of truth) |
| AI concurrency errors | Fixed topology §6.3 in AGENTS.md; no invented isolation |
| Silent TK2→TK1 downgrade | Banned API + debug assertion |
| Dependency / scope creep | §3 non-negotiables; ADR required to amend |
| Notarization friction late | Stage-0 dry-run |
| Solo-dev stall | ≤ 1-week stages; Stage-7 dogfooding loop |

## 16. Future Expansion (Post-v1 Direction, Non-Binding)

- **v1.1:** live preview pane (cmark-based render, scroll-synced) · workspace search · better conflict diff view.
- **v1.2:** user theme loading from disk · export HTML/PDF · Sparkle updates · line-number/gutter polish.
- **v2.x candidates (each requires an ADR):** command palette · WYSIWYG/hybrid mode · plugin surface (JavaScriptCore) · local-AI integrations/MCP client · terminal pane · TextBundle · App Store distribution.

The v1 architecture already accommodates these (semantic themes, tokenizer as a pure library, service boundaries) — but **no v1 code is written "for" them.**

## 17. Open Questions (Intentionally Deferred)

| Question | Decide by |
|---|---|
| Bundle ID (name is decided: **Scratchpad**; verify trademark/App-Store-name availability if MAS ever pursued) | Stage 13 |
| App icon design | Stage 12 |
| GitHub Releases vs. dedicated download page | Stage 13 |
| Sparkle vs. manual updates | Post-v1 ADR |
| App Store submission | Post-v1 ADR |
| STTextView / tree-sitter spikes | Only if a perf budget fails |

---

*End of Canon. If a question isn't answered here, it's either in `docs/DECISIONS.md` or it's yours to raise — not to improvise.*
