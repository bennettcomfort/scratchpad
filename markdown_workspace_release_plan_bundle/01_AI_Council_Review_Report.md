# AI Council Review — macOS Markdown Workspace Release Plans

## Executive Verdict

**Best source document overall:** `GPT-5.5-Council-Synthesis-final.md`  
**Best implementation-detail document:** `GPT-5.5-Local-First-Markdown-Workspace-final.md`  
**Best agent-prompt / sprint-pack document:** `Kimi-K2.6-MacOS-Native-Markdown-Workspace-final.md`  
**Best concise executive brief:** `DeepSeek-V4-Pro-Markdown-Workspace-Project-Plan-final.md`  
**Weakest plan:** `Grok-4.3-macOS-Markdown-Workspace-v1-Release-Plan-final.md`

The strongest final plan should combine:

- GPT Council’s **scope discipline + release philosophy**
- GPT Local-First’s **file safety, testing, risk register, implementation order**
- Kimi’s **agent-ready sprint prompts and macOS-native polish ideas**
- DeepSeek’s **simple phased roadmap and readable structure**
- Grok’s **brief non-negotiables**, but not its technical shortcuts

The core v1 rule:

> **Build a small, native, local-first Markdown workspace that is boringly reliable: open folders, edit files, save safely, recover unsaved text, switch files fast, and feel native on macOS.**

---

## Important Correction: Tahoe Target

Several plans say “Tahoe” while also saying `macOS 15+`. Treat this as a target-platform inconsistency.

Recommended target strategy:

| Target | Recommendation |
|---|---|
| **macOS 26+ only** | Best if you want Tahoe-native only and do not care about older users |
| **macOS 14/15+ compatible, Tahoe-styled** | Best if you want larger install base |
| **macOS 15+** | Weak middle ground unless an API dependency requires it |

**Recommendation:** build for **macOS 14/15+ compatibility first**, visually optimize for Tahoe-style UX, and avoid hard Tahoe-only APIs until they create real product value.

---

## Grades

| Document | Grade | Score | Summary |
|---|---:|---:|---|
| **GPT-5.5-Council-Synthesis** | A- | 92 | Best overall architecture and scope control. Strong v1 discipline, module design, acceptance criteria. |
| **GPT-5.5-Local-First** | A- | 91 | Best practical engineering plan. Excellent file safety, risk register, testing, and implementation order. |
| **Kimi-K2.6** | B+ | 86 | Best agentic sprint prompts and concrete implementation patterns. Too aggressive on dependencies and platform assumptions. |
| **DeepSeek-V4-Pro** | B | 82 | Clean, readable, sensible phases. Too shallow on file safety, bookmarks, conflicts, and acceptance criteria. |
| **Grok-4.3** | C+ | 76 | Concise and useful as an executive brief, but too thin for implementation. |

---

## Cross-Comparison

### 1. Product Scope

**Best:** GPT Council and GPT Local-First.

They correctly identify the v1 promise:

> Open a folder full of Markdown files, edit them quickly, switch between files, quit/crash safely, reopen, and continue exactly where you left off.

**Weaknesses in other plans:**

Kimi and Grok drift into “cool app” territory too early:

- STTextView
- tree-sitter
- SwiftData
- FSEvents
- Sparkle
- drag/drop
- command palette
- plugin/AI roadmap

These are not bad ideas. They are risk multipliers for v1.

**Final call:** v1 should be a source-mode Markdown workspace, not an Obsidian clone, Notion clone, AI IDE, or WYSIWYG editor.

---

### 2. Technology Stack

Consensus stack:

| Layer | Final Recommendation |
|---|---|
| Language | Swift 6 |
| Shell UI | SwiftUI |
| Editor Core | AppKit `NSTextView` / TextKit bridge |
| Storage | Plain files + JSON app state |
| Workspace Access | FileManager + security-scoped bookmarks |
| Release | Signed/notarized macOS app |

#### Decision Matrix

| Decision | DeepSeek | GPT Council | GPT Local | Grok | Kimi | Final Verdict |
|---|---|---|---|---|---|---|
| Native Swift | Yes | Yes | Yes | Yes | Yes | **Yes** |
| SwiftUI shell | Yes | Yes | Yes | Yes | Yes | **Yes** |
| `NSTextView` | Yes | Yes | Yes | Yes | Kimi prefers STTextView | **Start with `NSTextView`** |
| STTextView | No | Optional later | No | No | Default | **Spike only** |
| tree-sitter | No | Optional later | No | Optional | Default | **Post-v1 / spike** |
| SwiftData | No | No | Avoid for v1 | Future | Default | **Avoid for v1** |
| JSON persistence | Yes | Yes | Yes | Yes | Yes | **Yes** |
| File watching | Dispatch/FSEvents | Optional | Later/guarded | NSFilePresenter | FSEvents | **Phase 2 hardening** |

Final stack:

```text
Language:        Swift 6
UI Shell:        SwiftUI
Editor Core:     AppKit NSTextView wrapped with NSViewRepresentable
Text System:     TextKit / NSTextStorage / NSLayoutManager / NSTextContainer
Persistence:     Codable JSON + UserDefaults/AppStorage
File Access:     FileManager + security-scoped bookmarks
File Safety:     Atomic writes + recovery buffers
Testing:         XCTest + manual data-loss QA
Distribution:    Developer ID signed + notarized DMG
```

Optional spikes, not default commitments:

```text
STTextView
tree-sitter-markdown
Highlightr
SwiftData
FSEvents wrapper libraries
Sparkle
```

---

### 3. File Safety and Recovery

This is the most important section. A Markdown workspace that loses text is dead.

**Best source:** GPT Local-First.

It correctly emphasizes:

- atomic writes
- dirty state tracking
- external modification detection
- deleted file handling
- recovery buffers
- data-loss QA
- risk register

Golden rule:

> **Hot exit saves recovery copies, not original files. `Cmd+S` saves original files.**

#### Final file safety model

```text
1. Original user files
   - Only changed when the user explicitly saves.

2. Recovery buffers
   - Internal app copies of dirty unsaved text.
   - Written frequently.
   - Never replace original files automatically.

3. Session metadata
   - Workspace bookmark.
   - Open tabs.
   - Active tab.
   - Cursor positions.
   - Scroll positions.
   - Sidebar width.
   - Window frame.
   - Theme/layout settings.
```

#### Save algorithm

```text
When user presses Cmd+S:

1. Confirm file still exists.
2. Check last-known file hash / modification date.
3. If disk changed externally, show conflict flow.
4. Encode current text as UTF-8.
5. Write to temp file in same directory.
6. Flush/sync as reasonably practical.
7. Atomically replace original file.
8. Re-read metadata/hash.
9. Mark buffer clean only after success.
10. Delete matching recovery buffer.
```

#### Conflict states

```swift
enum DocumentSaveState: Codable {
    case clean
    case dirty
    case conflicted
    case deletedOnDisk
    case readOnly
    case unsavedUntitled
}
```

#### External modification behavior

| State | External file changed | Behavior |
|---|---|---|
| Clean buffer | Yes | Reload or show subtle “file updated from disk” banner |
| Dirty buffer | Yes | Mark conflicted; do not overwrite silently |
| File deleted | Yes | Keep tab open; allow Save As / recreate / close |
| File moved | Yes | Mark missing; allow locate file / Save As |
| Permission lost | Yes | Prompt to reselect workspace/file |

---

### 4. Editor Implementation

Recommended v1 editor:

```text
MarkdownEditorView
└── NSScrollView
    └── NSTextView
        ├── NSTextStorage
        ├── NSLayoutManager
        └── NSTextContainer
```

Do not start with full Markdown rendering.

For v1:

```text
# Heading
**bold**
`code`
[link](url)
```

Not v1:

```text
Rendered preview
WYSIWYG editing
Block editor
AST editor
Notion-style editor
```

#### Syntax highlighting strategy

v1 scanner/regex tokenizer for:

- headings
- bold
- italic
- inline code
- fenced code blocks
- links
- blockquotes
- lists
- horizontal rules
- YAML frontmatter

Guardrails:

```text
- Debounce highlighting 100–300ms.
- Do not mutate actual string during highlighting.
- Preserve selected range.
- Preserve scroll position.
- Disable or simplify highlighting above size threshold.
- Highlight visible range first if needed.
```

Later upgrade to `tree-sitter-markdown` only when regex highlighting becomes a real bottleneck.

---

### 5. Workspace and File Tree

Correct build order:

```text
1. Open single file
2. Edit
3. Save safely
4. Dirty state
5. Then open folder/workspace
6. Then sidebar file tree
```

#### v1 visible file types

```text
.md
.markdown
.mdown
.txt
```

#### Optional open-as-text

```text
.json
.yaml
.yml
.toml
.swift
.js
.ts
.py
```

#### Ignore by default

```text
.git
.DS_Store
node_modules
.build
DerivedData
dist
out
target
venv
.env
```

#### Sidebar operations

| Operation | v1? | Reason |
|---|---:|---|
| Open file | Yes | Core |
| Reveal in Finder | Yes | Simple/native |
| Copy path | Yes | Useful for developers |
| Rename | Maybe | Risky before tabs/session are solid |
| Delete / move to trash | Maybe later | Destructive |
| New file | Yes, after save model stable | Useful |
| New folder | Later | Not mandatory |

---

### 6. Quick Switcher and Recents

Kimi had the best quick-switcher interaction design, but shortcut choices need cleanup.

Final shortcuts:

```text
Cmd+P        Quick Open
Cmd+Shift+O  Open Workspace
Cmd+O        Open File
```

Fuzzy scoring:

| Match type | Score |
|---|---:|
| Exact filename | 100 |
| Prefix filename | 80 |
| Consecutive chars | 60 |
| Subsequence chars | 40 |
| Path segment match | +15 |
| Recently opened | +10 |
| Currently open tab | +5 |

---

### 7. Themes, Fonts, and Layout

v1 themes:

```text
System
Light
Dark
Paper
Midnight
High Contrast
```

v1 controls:

```text
Font family
Font size
Line height
Paragraph spacing
Editor max width
Text alignment
Line wrapping
Sidebar visibility
```

Defaults:

```text
Font: SF Mono or New York/SF Pro depending on theme
Size: 15–16
Line height: 1.45
Max width: 760–860 px
Alignment: left by default, centered readable column optional
Sidebar width: 240 px
```

Avoid in v1:

```text
Custom theme editor
Theme marketplace
CSS-like theme language
Plugin-controlled themes
```

---

## Document-by-Document Review

### 1. GPT-5.5-Council-Synthesis — A- / 92

#### Strengths

- Best executive recommendation.
- Strongest product framing.
- Strong v1 scope discipline.
- Correctly rejects Electron/Tauri/WYSIWYG/plugins/AI/Pandoc/live preview for v1.
- Good architecture map.
- Good module boundaries.
- Good acceptance criteria.
- Good post-v1 roadmap.
- Correctly emphasizes “boring but safe.”

#### Weaknesses

- Less copy-paste implementation-ready than Kimi.
- Some sections are broad rather than operational.
- Could be sharper on implementation order: single-file loop should come before full workspace complexity.

#### Keep

```text
- v1 promise
- mandatory/deferred feature split
- SwiftUI shell + NSTextView core
- JSON app state
- Developer ID notarized DMG first
- AI role split
- acceptance criteria
- final build philosophy
```

---

### 2. GPT-5.5-Local-First — A- / 91

#### Strengths

- Best engineering detail.
- Best data-loss risk thinking.
- Best file safety rules.
- Best testing matrix.
- Best implementation order.
- Explicitly avoids SwiftData/Core Data for v1.
- Strong manual QA list.
- Strong agent workflow.
- Good “narrow task” prompt discipline.

#### Weaknesses

- Long and repetitive.
- Less polished as a high-level pitch.
- No STTextView/tree-sitter exploration, which is acceptable for v1 but conservative.

#### Keep

```text
- JSON over SwiftData for v1
- atomic saves
- recovery buffers
- hot exit saves recovery copies, not original files
- external modification flow
- risk register
- implementation order
- manual QA checklist
- Definition of Done
```

---

### 3. Kimi-K2.6 — B+ / 86

#### Strengths

- Best AI-agent sprint prompts.
- Best concrete prompt packets.
- Strong project directory structure.
- Strong security-scoped bookmark code pattern.
- Good hot-exit details.
- Good quick switcher details.
- Good polish/hardening checklist.
- Strong future roadmap.

#### Risks

- Overcommits to STTextView.
- Overcommits to tree-sitter.
- Overcommits to SwiftData.
- Pulls in too many dependencies too early.
- Treats macOS 15+ as Tahoe.
- Adds FSEvents, Sparkle, drag/drop, and command-palette-like behavior too soon.

#### Keep

```text
- sprint prompt format
- security-scoped bookmark helper pattern
- session recovery flow
- quick switcher UX
- polish checklist
- AI orchestration playbook
```

---

### 4. DeepSeek-V4-Pro — B / 82

#### Strengths

- Easy to read.
- Sensible phases.
- Good native SwiftUI/AppKit recommendation.
- Good UI sketch.
- Good basic testing outline.
- Good future vision without making it v1.

#### Weaknesses

- Not enough file-safety detail.
- No atomic save plan.
- No security-scoped bookmark detail.
- No risk register.
- No conflict handling.
- No acceptance criteria per phase.
- Phase order puts workspace/file tree before proving the single-file editor/save loop.

#### Keep

```text
- readable format
- phase framing
- AI context file idea
- UI sketch
- simple agent cheat sheet
```

---

### 5. Grok-4.3 — C+ / 76

#### Strengths

- Concise.
- Good non-negotiables.
- Good one-page vision.
- Mentions sandbox-friendly design.
- Has a simple stage roadmap.

#### Weaknesses

- Too shallow for execution.
- Weak data-loss model.
- No atomic save details.
- No security-scoped bookmark depth.
- No real acceptance criteria.
- Adds export to PDF/HTML in v1 polish, which should be deferred.
- Mentions NSFilePresenter but does not explain enough to make it actionable.
- Uses outdated AI model suggestions.

#### Keep

```text
- concise executive summary
- non-negotiables
- keyboard-first/minimal chrome principle
```

---

## Final Recommendation

Use this hierarchy:

```text
MASTER PLAN:
GPT-5.5-Council-Synthesis

ENGINEERING RULES:
GPT-5.5-Local-First

AGENT PROMPT PACK:
Kimi-K2.6

READABLE EXEC SUMMARY:
DeepSeek

REFERENCE ONLY:
Grok
```

Strongest path:

```text
single file → safe save → NSTextView → workspace → tabs → recovery → quick switcher → highlighting → themes → polish → notarized release
```

Do not start with STTextView, tree-sitter, SwiftData, live preview, plugins, AI, or Sparkle unless you explicitly run a spike and prove they reduce risk. For v1, the product wins by being **fast, native, local, safe, and hard to break**.
