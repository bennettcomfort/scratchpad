# Architectural Review Report — macOS Markdown Workspace

> **Historical review.** This report explains earlier planning inputs but is not a current specification. See `SPEC.md` and `ARCHITECTURE.md` for approved recovery requirements.

> **Role:** Lead Orchestrator / Principal Engineer review
> **Date:** 2026-07-11
> **Corpus reviewed:** 5 independent AI-generated project plans + 1 prior synthesis bundle (council report, master plan, scope table, risk register, agent prompt pack, QA checklist, diagrams)
> **Historical companion:** `MASTER_CANON.md`, which was the prototype source of truth before the recovery contract superseded it.
> **Note (2026-07-11, later same day):** The product identity was subsequently refined in a brainstorming session — name **Scratchpad**, scratch-first concept, zen summon window (D-18/D-19 amending D-14), 4 themes, reordered roadmap. Where this report and the amended Canon differ, the Canon wins. See `docs/superpowers/specs/2026-07-11-scratchpad-identity-design.md`.

---

## Executive Summary

The corpus is unusually convergent for independently generated proposals. All five plans agree on the fundamentals: **native Swift + SwiftUI shell + AppKit editor core, plain files on disk, JSON app state, source-mode-only v1, hot exit as the flagship reliability feature, signed/notarized DMG distribution.** The prior council synthesis correctly graded the documents and locked scope. That consensus is sound and I confirm it.

However, consensus stopped exactly where the hard engineering begins. **Every document specifies *what* to build; none of them designs the three decisions that determine whether the build succeeds:**

1. **Text ownership.** All plans say "bind text two-way without update loops" and simultaneously list "cursor jumps during highlighting" as a top risk — without noticing these are the same problem. Two-way `String` binding between SwiftUI state and `NSTextView` is the *cause* of cursor jumps, undo breakage, and update loops. The fix is architectural, not a guardrail: `NSTextStorage` must be the single source of truth for open-document text. The Canon specifies this model precisely (§ Architecture, D-04).

2. **Concurrency topology.** Every plan invokes "Swift 6 strict concurrency" as a checkbox. None defines what is `@MainActor`, what is an actor, or how text snapshots cross the boundary to background highlighting and session persistence. This is the single most common failure mode of AI-generated Swift 6 code — the exact development method this project uses. The Canon defines the full actor map (D-05).

3. **TextKit version.** The corpus is internally contradictory: Grok specifies TextKit 2 while four documents specify `NSLayoutManager` (TextKit 1). On modern macOS, an `NSTextView` created for TextKit 2 **silently downgrades to TextKit 1 the moment any code touches `.layoutManager`** — a trap an AI agent following the current plans verbatim would trip immediately. The Canon picks TextKit 2 and bans the downgrade path (D-03).

Beyond these, the prior bundle left the platform target undecided, contains a duplicate keyboard binding, prescribes a six-document governance set that will drift, treats find-in-file as optional when it is nearly free, and encodes a 2025-era "paste prompts into Cursor" agent workflow that does not match the project's actual tooling (Claude Code with plan/TDD/review skills).

**Verdict:** The product definition and scope are ready. The engineering design was not. The Master Canon closes the gaps, makes every deferred decision, and supersedes all prior documents.

---

## Review of Each Submitted Document

### 1. GPT-5.5-Council-Synthesis (`GPT-5.5-Council-Synthesis-final.md`)

- **Summary:** The strongest overall plan. Full product definition, scope table with explicit defer list, module architecture, data models, file-safety rules, 13-stage roadmap with acceptance criteria, testing strategy, release plan.
- **Strengths:** Best scope discipline in the corpus ("boring in the best possible way"). Correct mandatory/deferred split. Good module boundaries. Acceptance criteria per stage. The save-safety pipeline (temp file → atomic replace → verify → mark clean) is correct.
- **Weaknesses:** Broad rather than operational at the hard parts — the editor bridge is one `NSViewRepresentable` stub with no text-ownership design. Contains a **duplicate shortcut bug**: `⌥⌘S` is assigned to both *Save All* (§9) and *Toggle Sidebar* (§9). Proposes a "Restore Session? [Restore] [Discard]" dialog that contradicts the hot-exit promise (see D-13). No concurrency design.
- **Unique ideas:** `DocumentSaveState` enum including `conflicted` / `deletedOnDisk`; deleted-file UX (keep buffer open, allow re-save); explicit "do not build an Obsidian clone first" framing.
- **Concerns:** Its authority (it graded well in the prior council) risks freezing its blind spots into the project.
- **Opportunities:** Its stage structure is the right skeleton for the final roadmap — kept, with corrections.
- **Assessment:** **Adopted as the roadmap and scope backbone.** Editor and concurrency design replaced entirely.

### 2. GPT-5.5-Local-First (`GPT-5.5-Local-First-Markdown-Workspace-final.md`)

- **Summary:** The deepest engineering document: data models, persistence layout, file-safety golden rules, recovery-buffer design, per-stage roadmap, the best testing matrix, agent role prompts, risk register.
- **Strengths:** The **file-safety model is the best single idea in the corpus**: *hot exit saves recovery copies, never original files; `⌘S` is the only thing that touches user documents.* Correctly rejects SwiftData for v1. Correct implementation order (single file → save → editor → workspace). Manual QA checklist centered on data loss. "Narrow task" agent prompt discipline.
- **Weaknesses:** Long and repetitive. `EditorBuffer.text: String` as a mutable model property re-creates the dual-source-of-truth problem its own risk register warns about. Fixed shortcut set punts `⌘1` for sidebar toggle (nonstandard). No concurrency design. Recommends "centered" alignment as a default (should be left).
- **Unique ideas:** Recovery buffers keyed by tab ID with last-saved hash; line-ending preservation; encoding-detection utility; two-tier recents (files + workspaces); `noteNewRecentDocumentURL` system integration.
- **Concerns:** Its "snapshot on every important event" list is too aggressive (cursor-move snapshots) — would generate constant disk writes; needs debounce policy, which the Canon sets.
- **Opportunities:** Its golden rules become the Canon's File Safety Invariants nearly verbatim.
- **Assessment:** **Adopted as the engineering-rules source.** Data-model shape corrected for the new text-ownership design.

### 3. Kimi-K2.6 (`Kimi-K2.6-MacOS-Native-Markdown-Workspace-final.md`)

- **Summary:** "Vibe-coding blueprint": 8 sprints as copy-paste agent prompt packets, feature-based directory layout, concrete code patterns (BookmarkManager actor, session models), orchestration playbook, CI workflow, post-v1 roadmap.
- **Strengths:** Best agent-facing writing in the corpus — each sprint is a self-contained prompt with success criteria. The **security-scoped `BookmarkManager` actor** is the best code artifact anywhere in the corpus. Feature-based folders ("organize so an AI agent can reason about boundaries") is the right principle. Only document with performance budgets (launch RAM, binary size, 10k-line file). Only document with CI. "Never let the AI work on more than one sprint at a time" is correct.
- **Weaknesses:** **Overcommits to dependencies before need is proven**: STTextView, swift-tree-sitter, SwiftData, EonilFSEvents, Sparkle — five external commitments for a v1 whose value proposition is reliability. Each is a supply-chain, API-churn, and debugging surface. Conflates macOS 15 with Tahoe. Suggests `⌘⇧O`/`⌘⇧T` for quick open based on an unfounded `⌘P` collision worry (overriding Print is standard practice — VS Code, Zed, Sublime all do it).
- **Unique ideas:** `.cursorrules`-style always-in-context constraints file; MCP-based repo access for the assistant; recovery via `didCloseCleanly` flag; sprint-per-branch merge discipline; DMG via `create-dmg`; notarization shell script.
- **Concerns:** Its confidence is seductive — the prompts read as authoritative even where the underlying choice (STTextView) is the risky one.
- **Opportunities:** Prompt-packet format and success-criteria style adopted for the Canon's stage definitions; constraints-file idea modernized into `CLAUDE.md`.
- **Assessment:** **Adopted for agent-workflow format, bookmark pattern, performance budgets, CI.** Dependency stack rejected for v1 (spike-only).

### 4. DeepSeek-V4-Pro (`DeepSeek-V4-Pro-Markdown-Workspace-Project-Plan-final.md`, "Inkflow")

- **Summary:** Readable 8-phase plan: custom workspace model, `NSTextStorage` subclass for highlighting, JSON sessions, MVVM + Combine, ~40-day timeline.
- **Strengths:** Clear rationale for rejecting `NSDocument`/pure-SwiftUI-`TextEditor`. Sensible phase framing. First document to propose an always-in-context AI rules file (`AI_CONTEXT.md`). Honest "review every generated code block" posture.
- **Weaknesses:** No atomic-save design, no bookmark persistence detail, no conflict handling, no acceptance criteria. Phase order puts workspace/file-tree before proving the single-file save loop (the council correctly flagged this). **Subclassing `NSTextStorage` is the riskiest highlighting approach offered anywhere in the corpus** — it takes over primary text storage responsibilities and is a well-known source of subtle editor bugs; attribute application to the existing storage achieves the same result safely. Combine-based architecture is dated relative to `@Observable`.
- **Unique ideas:** Line-numbers gutter consideration; pattern-priority ordering for the tokenizer (fences before inline syntax — correct and kept).
- **Concerns:** Timeline optimism (40 days including notarization) sets wrong expectations.
- **Assessment:** **Kept:** tokenizer priority ordering, readability standard, AI-context-file lineage. **Rejected:** `NSTextStorage` subclassing, Combine, phase order.

### 5. Grok-4.3 (`Grok-4.3-macOS-Markdown-Workspace-v1-Release-Plan-final.md`, "Plain")

- **Summary:** One-page executive brief: vision, non-negotiables, stack table, 6 compressed stages.
- **Strengths:** The **non-negotiables list is excellent** ("no proprietary databases," "session state survives quit/crash," "keyboard-first, minimal UI chrome") and survives into the Canon nearly intact. Only document to name TextKit 2 — accidentally surfacing the corpus's most important unresolved technical conflict. Simple JSON theme format.
- **Weaknesses:** Too thin to execute: no save safety, no bookmark handling, no acceptance criteria, no recovery design. Adds PDF/HTML export to v1 polish (scope creep). Recommends `NSFilePresenter` for folder watching — the weakest of the three watching options for this use case (designed for document coordination, notoriously unreliable for directory-tree observation). References stale AI models.
- **Unique ideas:** "Detachable tabs (Tahoe style)" — rejected for v1 (multi-window session restore complexity) but noted for the future-expansion list.
- **Assessment:** **Kept:** non-negotiables, TextKit 2 prompt. Otherwise reference-only.

### 6. Prior Synthesis Bundle (`markdown_workspace_release_plan_bundle/`)

- **Summary:** A complete prior pass at this exact task: graded council review, 12-stage master plan, must/should/defer scope, risk register, agent prompt pack, manual QA checklist, Mermaid diagrams.
- **Strengths:** The grading is fair and its conclusions match my independent read. The 12-stage roadmap ordering (single file → editor → workspace → tabs → recovery → switcher → highlighting → themes → conflicts → polish → release) is correct and is retained. The fuzzy-scoring table, ignore-lists, shortcut resolution (`⌘P` restored for quick open), and data-loss QA checklist are all solid, concrete, and kept. The "Tahoe target inconsistency" catch was sharp.
- **Weaknesses:**
  1. **It aggregates rather than designs.** Where the sources were silent (text ownership, concurrency, TextKit version), the bundle is silent too. A synthesis that inherits every blind spot of its inputs has added ordering, not architecture.
  2. **Platform target left open** — "decide minimum macOS target before code" is a task, not a decision. The Canon decides (D-02).
  3. **Governance doc sprawl:** Stage 0 mandates `PRODUCT.md`, `SPEC.md`, `ARCHITECTURE.md`, `RULES.md`, `TODO.md`, `AGENTS.md` — six overlapping documents for a solo project. Overlapping sources of truth drift apart, and agents then follow the stale one. The Canon consolidates to three (D-16).
  4. **Restore UX unspecified:** inherits the Council's restore-prompt in one diagram and silent restore in the prompt pack — contradictory.
  5. **Agent workflow is dated:** the prompt pack assumes paste-into-Cursor sessions. The project's actual environment (Claude Code, July 2026, with planning/TDD/review skills installed) supports repo-resident context, test-first loops, and automated review — a materially better workflow the Canon specifies.
  6. Missing entirely: performance budgets, session-schema versioning, untitled-document lifecycle, find-in-file (nearly free via `NSTextView.usesFindBar`), dogfooding milestone.
- **Assessment:** **Superseded.** Its roadmap skeleton, scope table, QA checklist, and fuzzy scoring live on inside the Canon; everything else is replaced.

---

## Cross-Comparison Matrix

| Dimension | DeepSeek | Grok | Kimi | GPT Local-First | GPT Council | Bundle | **Canon Decision** |
|---|---|---|---|---|---|---|---|
| Language / UI shell | Swift + SwiftUI | Swift + SwiftUI | Swift 6 + SwiftUI | Swift 6 + SwiftUI | Swift 6 + SwiftUI | Swift 6 + SwiftUI | **Swift 6 + SwiftUI** (unanimous — confirmed) |
| Editor core | NSTextView + NSTextStorage subclass | "TextKit 2 + NSTextView" | STTextView | NSTextView (TK1 APIs) | NSTextView (TK1 APIs) | NSTextView (TK1 APIs) | **NSTextView on TextKit 2**; no storage subclass; STTextView spike-only (D-03) |
| Text ownership | Model `String` + binding | unspecified | two-way binding "avoid loops" | `EditorBuffer.text` model | binding via representable | inherited | **`NSTextStorage` is source of truth** — no two-way String binding (D-04) |
| Concurrency design | Combine, unspecified actors | none | "strict concurrency" flag only | none | none | none | **Explicit actor topology** (D-05) |
| Reactive framework | Combine | unspecified | @Observable | @Published/Observable mix | unspecified | inherited | **@Observable; no Combine** (D-06) |
| Metadata persistence | JSON | Codable + UserDefaults | **SwiftData** + JSON | JSON (explicitly anti-SwiftData) | JSON | JSON | **JSON + UserDefaults; no SwiftData** (D-07) |
| Highlighting | hand-rolled regex, storage subclass | Highlightr / tree-sitter | tree-sitter | hand-rolled tokenizer | hand-rolled tokenizer | hand-rolled | **Hand-rolled line-based tokenizer**, attributes-only, damage-range (D-11) |
| File watching | DispatchSource | NSFilePresenter | FSEvents (EonilFSEvents) | optional/guarded | optional | Stage-10 | **Deferred to hardening; pre-save staleness check is the v1 safety net** (D-12) |
| Hot exit model | session JSON + unsaved blobs | serialize all state | tmp autosave files + silent restore | **recovery copies ≠ originals** | recovery buffers + restore prompt | recovery buffers | **Recovery-copy model, silent restore, no prompt** (D-08, D-13) |
| Platform target | macOS 14 | "Tahoe only" | macOS 15 ("Tahoe") | Tahoe (unversioned) | Tahoe (unversioned) | undecided | **macOS 26 (Tahoe) minimum** (D-02) |
| Sandbox | entitlements, no network | "App Store ready" | sandbox + bookmarks | "optional but design for it" | bookmarks if sandboxed | inherited | **Sandbox ON from day one** (D-09) |
| Quick-open shortcut | ⌘P | ⌘P | ⌘⇧O (collision worry) | ⌘P | ⌘P | ⌘P | **⌘P** (remove/remap Print) |
| Dependencies at v1 | 0–1 | 2–3 | **5+** | 0 | 0 | 0 | **Zero third-party runtime dependencies** (D-10) |
| Agent workflow | paste-prompt + AI_CONTEXT.md | Cursor + Claude Projects | Cursor Composer + .cursorrules + MCP | role-split prompt sessions | role-split prompt sessions | Cursor-era prompt pack | **Claude Code-native: CLAUDE.md + stage-gated TDD loop** (D-17) |
| Perf budgets | 1MB highlight note | none | launch/RAM/binary budgets | 2MB highlight threshold | none | none | **Full budget table** (Canon § Performance Budgets) |
| CI | "optional later" | none | GitHub Actions build | optional | none | none | **CI from Stage 0** (build + unit tests on push) |

**Contradictions resolved:** TextKit version (D-03) · platform target (D-02) · restore prompt vs. silent (D-13) · ⌥⌘S double-binding (Canon shortcut table) · ⌘P vs ⌘⇧O (⌘P wins) · SwiftData yes/no (no) · watching mechanism (deferred).

**Ideas absent from every document** — see Missing Opportunities below.

---

## Architectural Decisions

Each decision below is recorded as final in the Master Canon. Format: chosen → rejected → reasoning → tradeoffs/implications.

**D-01 — Native Swift 6 + SwiftUI shell + AppKit editor core.**
Rejected: Electron, Tauri, Catalyst, pure-SwiftUI `TextEditor`, AppKit-only. Unanimous across the corpus and correct: the product's positioning (lightweight, native, zero-latency, local) is unachievable on a web runtime, and `TextEditor` cannot support attribute-level highlighting or cursor/scroll restoration. Tradeoff: Apple-platform lock-in — acceptable; it *is* the product.

**D-02 — Minimum platform: macOS 26 (Tahoe).**
Rejected: macOS 14/15+ compatibility (the prior council's lean). Reasoning: this is a solo project with exactly one test machine, running Tahoe. Every `#available` branch for an OS you cannot run is untested code masquerading as compatibility — worse than no support. Tahoe has been shipping for ~9 months; the target audience (developers, prompt engineers, writers who adopt new tools) updates fast. Tradeoff: smaller initial install base. Mitigation: keep API usage conservative so lowering the floor later is a build-setting change, not a rewrite. Revisit only with real distribution data.

**D-03 — Editor: `NSTextView` on TextKit 2, explicitly.**
Rejected: TextKit 1 (`NSLayoutManager`), `NSTextStorage` subclassing (DeepSeek), STTextView as default (Kimi), tree-sitter at v1. Reasoning: TextKit 2 is the supported future and the default for new `NSTextView`s; the corpus's TK1 API references would cause silent downgrades. Highlighting works identically on TK2 via attribute application to `textContentStorage.textStorage`. Hard rule for agents: **never access `NSTextView.layoutManager`** — it silently converts the view to TextKit 1. STTextView and tree-sitter remain time-boxed spikes if the vanilla path proves painful. Tradeoff: TK2 has API gaps vs TK1 (noted in risks); mitigated because v1 needs no exotic layout features.

**D-04 — Text ownership: `NSTextStorage` is the single source of truth for open-document text.**
Rejected: two-way `String` binding; model-owned mutable text. Reasoning: this dissolves the corpus's top recurring risk (cursor jumps, update loops, undo breakage) instead of guarding against it. While a document is open, its text lives in exactly one place — the text view's storage. The `DocumentModel` holds metadata (URL, dirty hash, save state) and *reads* the storage on demand (save, snapshot); it never pushes strings back except on explicit whole-document replacement (file open, external reload), which runs through one guarded code path that restores selection. Undo stays entirely inside `NSTextView`'s `undoManager`. Implication: per-open-document, an `NSTextStorage` exists even for background tabs (cheap; preserves undo history per tab).

**D-05 — Concurrency: explicit actor topology under Swift 6 strict concurrency.**
Rejected: "enable strict concurrency" as an unexamined flag. The topology (full spec in Canon): all AppKit/SwiftUI, `DocumentManager`, and text storage on `@MainActor`; `FileIndexer`, `SessionWriter`, `BookmarkManager` as actors; highlighting computed on a background task from an immutable snapshot + generation counter, attributes applied back on main only if the generation still matches. Reasoning: AI-generated Swift 6 fails most often at ad-hoc concurrency; a fixed map turns every agent task into "which lane am I in?" Tradeoff: some ceremony for small operations — acceptable for correctness.

**D-06 — Observation: `@Observable`; no Combine.**
Rejected: Combine pipelines (DeepSeek), mixed `@Published`. Reasoning: `@Observable` is the current-era default, integrates cleanly with SwiftUI and strict concurrency, and removes an entire class of retain-cycle risks the corpus warns about. Debouncing is a ~15-line `Task`-based utility, not a framework dependency.

**D-07 — Persistence: Codable JSON + UserDefaults; no SwiftData/Core Data. All schemas carry `schemaVersion`.**
Rejected: SwiftData (Kimi). Reasoning: user documents are plain files (non-negotiable); remaining state is small, debuggable-by-eye JSON. SwiftData adds schema/migration/concurrency complexity with zero v1 payoff. The `schemaVersion` field (absent from every document) costs one line now and prevents a migration cliff later.

**D-08 — File safety: recovery-copy model with atomic writes.**
Adopted from GPT Local-First, hardened: originals change **only** on explicit user save; dirty buffers are snapshotted to app-support recovery files (debounced 1–3 s), themselves written atomically (a torn recovery file is lost recovery — the corpus missed this); save pipeline = staleness check (mtime/hash) → temp file in same directory → atomic replace → re-read metadata → mark clean → delete recovery buffer. Never mark clean on failure.

**D-09 — App Sandbox ON from day one; security-scoped bookmarks for all persisted file access; Developer ID + notarized DMG distribution.**
Rejected: unsandboxed v1 with later retrofit. Reasoning: retrofitting sandbox breaks every persisted-access assumption at the worst time; adopting it now costs one entitlement and the `BookmarkManager` actor (Kimi's pattern, adopted). Keeps App Store optional, not required. Zero network entitlements — enforced local-first, verifiable at review time.

**D-10 — Zero third-party runtime dependencies in v1.**
Rejected: STTextView, tree-sitter, Highlightr, EonilFSEvents, SwiftData, Sparkle, KeyboardShortcuts. Reasoning: every dependency is API churn, supply-chain surface, and a debugging seam — for a v1 whose entire brand is reliability. Everything required is achievable with platform APIs. Dev-only tools (SwiftLint/swift-format, create-dmg) are allowed. Any dependency may still enter via an explicit, time-boxed spike with a written verdict.

**D-11 — Highlighting: hand-rolled, line-oriented Markdown tokenizer applying attributes only.**
Rejected: tree-sitter (v1), Highlightr, `NSTextStorage` subclass, whole-document re-regex per keystroke. Design: tokenize per-line with minimal cross-line state (inside-fence, inside-frontmatter); on edit, re-tokenize only the damaged line range extended to enclosing block boundaries; debounce 100–250 ms; hard size threshold (default 2 MB) degrades to plain text. Token priority per DeepSeek: fences → frontmatter → headings → blockquotes/lists → inline (code, bold, italic, links). The tokenizer is a pure `String → [Token]` function — fully unit-testable, TDD-first.

**D-12 — File watching deferred to hardening (Stage 10); pre-save staleness check is the v1 safety net.**
Rejected: FSEvents/NSFilePresenter/DispatchSource in core stages. Reasoning: the data-loss risk of external edits is fully covered by the save-time hash/mtime check plus conflict flow; live tree refresh is UX polish, not safety. When added, DispatchSource/FSEvents on the workspace root — not `NSFilePresenter` (wrong tool for directory trees; Grok's suggestion rejected).

**D-13 — Hot exit restores silently. No restore prompt, ever.**
Rejected: GPT Council's "[Restore] [Discard]" dialog. Reasoning: the product promise is *continue exactly where you left off* — a dialog converts the flagship feature into a decision chore and invites accidental discard of unsaved work (the one catastrophic click this app must make impossible). Restored dirty tabs simply appear dirty, with an unobtrusive "restored" indication. A `didCloseCleanly` flag distinguishes crash from clean quit for diagnostics only.

**D-14 — App model: custom workspace app; single main window; custom tab bar.**
Rejected: `NSDocument`/`DocumentGroup` (one-document-per-window model fights the workspace concept — unanimous corpus reasoning, confirmed); detachable tabs and multi-window (Grok) — multiplies session-restore complexity for marginal v1 value. SwiftUI `Window` scene (not `WindowGroup`) enforces the single-window model.

**D-15 — Untitled documents are first-class.**
Absent from most of the corpus. `⌘N` creates an untitled buffer that participates fully in hot exit (recovery buffer with no file URL); first save runs Save As. An editor that can lose a brand-new note fails its core promise.

**D-16 — Governance: three documents, not six.**
Rejected: the bundle's PRODUCT/SPEC/ARCHITECTURE/RULES/TODO/AGENTS set. Kept: `MASTER_CANON.md` (all decisions — vision, scope, architecture, standards), `CLAUDE.md` (thin, always-in-context agent rules distilled from the Canon), `docs/DECISIONS.md` (append-only ADR log for post-Canon changes). Reasoning: overlapping documents drift; agents then obey the stale one. One canon, one distillation, one changelog-of-decisions.

**D-17 — Agent workflow: Claude Code-native, stage-gated, test-first.**
Rejected: the corpus's paste-into-Cursor prompt-pack model (2025-era). The workflow: repo-resident `CLAUDE.md` context; one stage in flight at a time on a feature branch; per-stage plan → TDD for all pure logic (tokenizer, fuzzy matcher, session codecs, atomic writer) → implementation → automated code review → manual data-loss QA → merge. Full spec in Canon § Agent Workflow.

---

## Risks

Consolidated from all documents, re-scored, with new entries (★) the corpus missed.

| # | Risk | P | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Data loss via save/recovery bug | M | **Critical** | D-08 invariants; recovery-store tests; data-loss QA gate before every release |
| R2 | Silent overwrite of external edits | M | **Critical** | Pre-save hash/mtime check (Stage 2, not Stage 10); conflict flow |
| R3 | ★ Torn/corrupt recovery or session JSON on crash | M | High | Atomic writes for *internal* state too; tolerate-and-quarantine corrupt files on load |
| R4 | Cursor jump / update loop in editor bridge | H→L | Medium | Eliminated by design via D-04 (single source of truth), not guarded by convention |
| R5 | ★ Swift 6 concurrency errors in AI-generated code | H | Medium | Fixed actor topology (D-05) in `CLAUDE.md`; agents never invent isolation |
| R6 | ★ Silent TextKit 2→1 downgrade | M | Medium | Hard rule: never touch `.layoutManager`; assert TK2 in debug builds |
| R7 | Highlighting lag on large files | M | Medium | Damage-range tokenizing, debounce, 2 MB degrade threshold, perf tests |
| R8 | Bookmark resolution fails after relaunch/move | M | High | `BookmarkManager` actor; stale-bookmark refresh; explicit reselect flow |
| R9 | Workspace scan freezes UI on huge folders | M | Medium | Async scan off main; ignore-list; lazy tree; 10k-file perf budget |
| R10 | Dependency creep re-enters via agent suggestions | H | High | D-10 zero-dependency rule in `CLAUDE.md`; spike protocol for exceptions |
| R11 | Scope creep (preview/WYSIWYG/AI/plugins) | H | High | Frozen defer list in Canon; any addition requires a DECISIONS.md entry |
| R12 | Agent-generated architecture drift | H | Medium | One stage in flight; review gate per stage; Canon as tiebreaker |
| R13 | ★ TextKit 2 API gaps vs TK1 for a needed feature | L | Medium | v1 needs no exotic layout; time-boxed spike + ADR if a gap appears |
| R14 | Notarization/signing friction at first release | M | Low | Dry-run the sign→notarize→staple pipeline in Stage 0 CI, not at Stage 12 |
| R15 | ★ Solo-developer stall (motivation/attention) | M | High | Dogfood milestone (Stage 7) makes the app self-hosting; stages sized ≤ 1 week |

---

## Missing Opportunities

Absent from **every** submitted document; all incorporated into the Canon:

1. **Dogfooding milestone.** From Stage 7 (quick switcher) onward, the app edits this project's own planning corpus daily. Self-hosting is the cheapest, highest-signal QA the project can buy — every data-loss bug becomes personally intolerable.
2. **Session/recovery schema versioning.** One `schemaVersion` field per JSON schema; forward-compatibility policy defined now, not post-corruption.
3. **Find-in-file as a v1 must.** `NSTextView.usesFindBar = true` is nearly free; the corpus deferring "basic find" while hand-building a fuzzy switcher was a mis-weighting.
4. **Untitled-document lifecycle** (D-15).
5. **Debug-build integrity assertions:** TK2 still active; recovery-buffer count matches dirty-tab count; session JSON round-trips. Cheap invariant checks that catch corruption where it starts.
6. **Notarization dry-run in Stage 0** rather than first attempt at release week (R14).
7. **Performance budget table** as testable acceptance criteria (only Kimi gestured at this).
8. **Generation-counter protocol** for async highlight application — the concrete mechanism that makes "debounced background highlighting" actually safe.
9. **Corrupt-state quarantine:** unparseable session/recovery files are renamed aside (never deleted), the app starts fresh, and the user keeps a recovery path.
10. **`⌘P` conflict resolution done properly:** remove/remap Print rather than surrender the ecosystem-standard quick-open binding.

---

## Open Questions

Require resolution before or during the stated stage; none blocks Stage 0–1.

| Question | Deadline | Notes |
|---|---|---|
| Final product name + bundle ID | Before Stage 12 | Codename `MarkdownWorkspace` until then; check trademark/domain |
| App icon direction | Stage 11 | Placeholder acceptable through betas |
| Distribution page (GitHub Releases vs. site) | Stage 12 | GitHub Releases is the low-friction default |
| Sparkle auto-update vs. manual | Post-v1 | Deliberately deferred (D-10) |
| App Store submission | Post-v1 | Sandbox-on design (D-09) keeps it open |
| STTextView / tree-sitter spikes | Only if triggered | Trigger: vanilla path demonstrably fails a perf budget |
| Localization | Post-v1 | English-only v1; avoid hardcoded-string sprawl anyway |

---

## Final Recommendations

1. **Adopt `MASTER_CANON.md` as the sole source of truth** and mark the five plans + prior bundle as historical inputs. Do not let agents read the superseded documents.
2. **Do Stage 0 next:** repo init, Xcode project, sandbox entitlements, `CLAUDE.md`, CI with a notarization dry-run. The planning phase is complete — further planning is procrastination with extra steps.
3. **Hold the three load-bearing decisions under pressure:** text ownership (D-04), actor topology (D-05), zero dependencies (D-10). Agents will repeatedly propose "simpler" two-way bindings and "helpful" packages; the Canon exists precisely for those moments.
4. **Treat the data-loss QA checklist as a release gate,** not a suggestion — every release candidate, no exceptions.
5. **Start dogfooding at Stage 7** with this very folder as the first workspace.

The corpus earned its consensus: a small, native, boringly reliable Markdown workspace is the right product. What it lacked was the engineering spine to survive contact with an AI-driven build process. The Canon provides it.
