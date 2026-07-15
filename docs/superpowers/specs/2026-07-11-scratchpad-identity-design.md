# Scratchpad — Identity & Design Refinement

> **Historical design input.** This document predates the controlled recovery milestone and has no implementation authority. Workspace, tabs, Zen/global hotkey, highlighting, and other expanded-scope decisions here are deferred. See `SPEC.md`, `ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md`, `TRACKER.md`, and `AGENTS.md` for the live contract.
>
> **Date:** 2026-07-11
> **Original status:** Approved by user for the superseded prototype direction.
> **Former relationship:** Amended the now-historical `MASTER_CANON.md`.
> **Current use:** Product-identity and visual provenance only.

---

## 1. Identity Decisions (from clarifying round)

| Question | Decision |
|---|---|
| Product name | **Scratchpad** (final — no longer a Stage-12 open question) |
| Core concept | **Scratch-first, workspace too.** Launch → type immediately into an untitled buffer. Folder workspaces fully supported as the power feature, not the front door. |
| Minimalism | **Minimal chrome, full features.** Nothing cut from scope; the UI recedes. |
| Aesthetic | **Sublime Text / Zed austerity.** Near-zero chrome; syntax color is the only decoration; high-res sharpness. |
| Speed identity | All three: instant launch, wired keystroke latency, sub-perceptual switching. Budgets tightened (§5). |
| Signature feature | **Global hotkey summons a small zen scratch window** on the cursor's screen (not a Raycast-style overlay; a real, calm, Sublime-zen-mode-like window). |

## 2. The Two Windows

**Main window** — full app: sidebar (hidden until a workspace opens, `⌘\`), tab bar (materializes only at 2+ buffers), editor, whisper status bar (~60% opacity, toggleable). Hidden title bar, full-size content, traffic lights float over the margin. No toolbar, ever. Launches straight into an untitled scratch buffer — never a welcome screen or file dialog.

**Zen scratch window** — summoned via global hotkey (default `⌃⌥Space`, rebindable):

- Appears **centered on the screen containing the mouse cursor**
- Small narrow-column window (~640×400 initial; remembers user resize), hidden title bar, movable/resizable — a real window, not a floating panel
- Contains a fresh untitled scratch buffer, focused, typeable instantly
- Same editor/theme/highlighting as the main editor; no status bar, no tabs — text only
- Only one zen window ever exists; re-pressing the hotkey moves/re-summons it to the current cursor screen
- Requires app running; **launch-at-login toggle** in Settings (`SMAppService`)

**Zen exit actions:**

| Key | Action |
|---|---|
| `⌘⏎` | **Copy entire buffer to clipboard + dismiss** (signature exit; subtle "Copied" flash) |
| `Esc` | Dismiss only (buffer survives, as always) |
| Setting | "Esc also copies to clipboard" — off by default (avoids silent clipboard clobbering) |

Primary use case this serves: summon → draft (a prompt, commit message, note) → `⌘⏎` → paste anywhere.

## 3. Chrome & Aesthetic Rules

Governing testable rule: **at rest, with no workspace open, Scratchpad renders text and nothing else.**

- All UI chrome is grayscale; color appears only in syntax (theme palette) and one accent (selection/caret)
- Hairline dividers (0.5 pt Retina); no icons where a word is shorter; no buttons for keyboard-reachable actions
- Typography gets the luxury (SF Mono default, 1.45 line height); the frame gets nothing

**Themes: reduced 6 → 4** (Paper and Midnight cut as aesthetic hedges for unpicked identities):

| Theme | Character |
|---|---|
| **Scratch Dark** (hero, default) | Near-black, Zed-like, muted syntax hues |
| **Scratch Light** | Paper-white counterpart, same hue relationships |
| **System** | Follows macOS appearance → maps to the two above |
| **High Contrast** | Accessibility, both appearances |

## 4. Architecture Deltas to the Canon

- **D-14 amended:** window model is now **main window + single zen scratch window**. Session restore covers both.
- **D-18 (new) — Global summon hotkey:** `RegisterEventHotKey` (Carbon; sandbox-safe, no accessibility permission). Default `⌃⌥Space`, rebindable. Summon: screen of `NSEvent.mouseLocation` → center zen window → new untitled buffer → focus.
- **D-19 (new) — Scratch buffers are a first-class persistent collection:** each untitled buffer gets a recovery file at creation; appears in `⌘P` as "Scratch — <first-line preview>"; survives until saved to a file or explicitly closed-with-discard. Not transient tab state.
- **Governance rename:** `CLAUDE.md` → **`AGENTS.md`** (implementing agent is pi agent + DeepSeek/Kimi; `AGENTS.md` is the cross-agent convention).
- Everything else in the Canon stands unchanged (text ownership, actor topology, file-safety invariants, zero dependencies, TextKit 2 rules, JSON persistence, sandbox-on).

## 5. Tightened Performance Budgets

| Metric | Was | Now |
|---|---|---|
| Cold launch → typeable | < 800 ms | **< 400 ms** |
| Hotkey → zen window typeable (app running) | — | **< 150 ms** |
| `⌘P` open / tab switch | < 100 ms | **< 50 ms** |
| Keystroke → screen | no dropped frames (120 Hz) | unchanged |

All other Canon budgets unchanged.

## 6. Reordered Roadmap (full scope, scratch-core first)

Nothing is cut; order changes so the product is a complete usable scratchpad before it is a workspace.

| Stage | Deliverable | Milestone |
|---|---|---|
| 0 | Foundation: repo, CI, sandbox, notarization dry-run | |
| 1 | App shell: hidden-titlebar window, menus, launch-to-empty-buffer | |
| 2 | Editor core: TextKit 2 bridge, untitled scratch buffers | |
| 3 | Hot exit: recovery buffers, silent restore | |
| 4 | Zen summon: global hotkey, cursor-screen centering, `⌘⏎` copy-exit, login item | **☆ daily-usable scratchpad** |
| 5 | File open/save: atomic writes, dirty state, Save As for untitled | |
| 6 | Tabs & document manager | |
| 7 | Workspace: folder open, bookmarks, sidebar | |
| 8 | Navigation: `⌘P`, recents | **☆ full daily driver** |
| 9 | Highlighting: tokenizer (TDD), debounce, 2 MB degrade | |
| 10 | Themes & layout: 4 austerity themes, font/layout controls | |
| 11 | Hardening: conflict UX, external changes, file watching, find polish | |
| 12 | Polish: status bar, icon, accessibility, error banners | |
| 13 | Release: sign, notarize, DMG, v1.0.0 | **☆ ship** |

Rationale: hot exit lands before file I/O (scratch buffers need only the recovery store — dependency order verified); the hardest reliability feature gets the longest soak; dogfooding starts at Stage 4.

## 7. Shortcut Additions/Changes

| Action | Shortcut |
|---|---|
| Summon zen window (global) | `⌃⌥Space` (rebindable) |
| Zen: copy all + dismiss | `⌘⏎` |
| Zen: dismiss | `Esc` |
| New scratch buffer (in-app) | `⌘N` (unchanged — now creates a scratch buffer per D-19) |

All other Canon shortcuts unchanged.

## 8. Follow-on Deliverables (user requirement)

At the end of planning, produce for the implementing agent (pi agent + DeepSeek/Kimi):

1. **`SPEC.md`** — self-contained product + technical spec (Canon + this design merged; no critical rule referenced-but-not-stated)
2. **`IMPLEMENTATION_PLAN.md`** — per-stage, per-task packets with explicit acceptance criteria and "done when" checklists (Kimi-style prompt-packet format)
3. **`AGENTS.md`** — always-in-context rules: hard API rules, actor topology, file-safety invariants, zero-dependency rule, current-stage pointer

Writing standard: assume a capable but drift-prone implementer — small bounded tasks, verbatim constraint blocks repeated where they apply, no implicit context.
