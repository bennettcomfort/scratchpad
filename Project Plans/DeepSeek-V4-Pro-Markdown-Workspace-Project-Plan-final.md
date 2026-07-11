```markdown
# 📋 **Inkflow** (codename)
### **A Local-First Markdown Workspace for macOS**

---

> **Role:** Expert Software Architect & AI-Assisted Development Lead  
> **Product Goal:** Ship a polished v1 macOS app (Tahoe) that feels native, fast, and delightful for writers and developers.  
> **Timeline:** Solo, agentic development, ~6–8 weeks to v1 release candidate.  
> **Hardware:** Apple M3 Max, 64 GB RAM, macOS Tahoe.

---

## 🧭 **Table of Contents**

1. [Ideation & Clarification](#1-ideation--clarification)  
2. [Architecture & Technology Decisions](#2-architecture--technology-decisions)  
3. [UI/UX Design Blueprint](#3-uiux-design-blueprint)  
4. [Staged Development Roadmap (Agentic Workflow)](#4-staged-development-roadmap-agentic-workflow)  
   - [Phase 0: Project Setup & Tooling](#phase-0-project-setup--tooling)  
   - [Phase 1: Core Engine & Document Model](#phase-1-core-engine--document-model)  
   - [Phase 2: Workspace & File Tree](#phase-2-workspace--file-tree)  
   - [Phase 3: Editor & Syntax Highlighting](#phase-3-editor--syntax-highlighting)  
   - [Phase 4: Session Recovery & Hot Exit](#phase-4-session-recovery--hot-exit)  
   - [Phase 5: Quick Navigation & Recent Files](#phase-5-quick-navigation--recent-files)  
   - [Phase 6: Themes & Layout Controls](#phase-6-themes--layout-controls)  
   - [Phase 7: Integration, Polish & App Delivery](#phase-7-integration-polish--app-delivery)  
5. [Agentic Development Cheat Sheet](#5-agentic-development-cheat-sheet)  
6. [Testing Strategy](#6-testing-strategy)  
7. [Source Control & Release Flow](#7-source-control--release-flow)  
8. [Future Vision (v2+)](#8-future-vision-v2)

---

## 1. **Ideation & Clarification**

**Core identity:** A *local-first*, *plain-text* workspace that respects text files and folders. No proprietary databases or cloud. Everything is `.md` or `.txt` on disk.

**Differentiator from existing tools (Bear, Obsidian, iA Writer, etc.):**  
- **True local** – zero network permission needed.  
- **Workspace based** – open a folder → see its entire Markdown forest.  
- **Session resilience** – never lose a thought even if the app crashes or you force quit.  
- **Developer-friendly** – syntax highlighting, quick file switching, font/layout control.  

We will lean into macOS-native technologies (AppKit + SwiftUI mixing) for performance and system integration.

---

## 2. **Architecture & Technology Decisions**

### 2.1 **Language & UI Framework**
- **Swift** (latest, 6.0+)
- **Primary UI:** `SwiftUI` for most views (sidebar, toolbar, settings)  
- **Core text editor:** `NSTextView` inside `AppKit` view representable (for performance, syntax highlighting, and fine-grained text layout).  

**Why not pure SwiftUI for the editor?**  
- `TextEditor` lacks programmatic control over text storage, custom attributes, and efficient syntax highlighting for large files.  
- `NSTextView` gives us `NSTextStorage`, `NSLayoutManager`, `NSTextContainer` – the foundation for syntax highlighting, line numbers, and advanced layout.

### 2.2 **Document Model**
- **Adopt `NSDocument` (SwiftUI DocumentGroup) with `Data`/file wrapper?**  
  *No.* We'll go **custom** because our "document" is a workspace, not a single file.  
- Instead, use a custom `Workspace` model that watches a folder and manages multiple `FileDocument` instances.

```
Workspace
├── rootURL: URL
├── watchedFolders: Set<URL>
├── openTabs: [FileDocument]
├── recentFiles: [URL]
└── session: SessionState
```

### 2.3 **File Monitoring**
- `DispatchSource` for file system events or `FSEvents` API via `FileMonitor` class, wrapped in Combine publishers for SwiftUI reactivity.

### 2.4 **Session Recovery / Hot Exit**
- Store session state as `JSON` inside `~/Library/Application Support/Inkflow/Sessions/`.  
- On quit, snapshot: open tabs, unsaved changes (as temp blobs), window frame, cursor positions, sidebar state.  
- On launch, check for session and restore. If app crashes, the unsaved changes are preserved in an `~unsaved_changes.json` file.

### 2.5 **Syntax Highlighting**
- Use `NSTextStorage` subclass (`MarkdownTextStorage`) that parses Markdown tokens (using a lightweight, hand-rolled parser or a library like `MarkdownKit`) and applies attributes (bold, italic, headers, code, links).  
- Highlighting runs on a background queue to keep UI responsive.

### 2.6 **Theme System**
- Define `Theme` struct with `Color`, `Font`, spacing properties.  
- Store as JSON asset or Codable, allowing future custom themes.

### 2.7 **Layout Controls**
- Editor width: adjustable via slider (like iA Writer). Use `NSTextView`'s `textContainerInset` and `NSTextContainer.size`.  
- Line height: `NSMutableParagraphStyle.lineSpacing`  
- Font size: `NSFont` scaling.

### 2.8 **Project Structure (Xcode)**
```plaintext
Inkflow/
├── Models/          # Workspace, FileDocument, Session, Theme, LayoutSettings
├── ViewModels/     # WorkspaceViewModel, EditorViewModel, SidebarViewModel
├── Views/
│   ├── Sidebar/    # FileTree, RecentFiles
│   ├── Editor/     # MarkdownEditor (AppKit wrapper), SourceEditor, SplitView
│   ├── Settings/   # Themes, Font, Layout panels
│   └── App/        # MenuBar, Commands, QuickSwitch
├── Services/       # FileMonitor, SyntaxHighlighter, SessionManager, ThemeManager
├── Utilities/      # Extensions, Parsers, Helpers
└── Resources/      # Themes, Default fonts, Assets
```

---

## 3. **UI/UX Design Blueprint**

**Inspiration:** iA Writer’s focus mode, Sublime Text’s file tree + tabs, VS Code’s quick open.

### Layout (Default)
```
┌─────────────────────────────────────────────┐
│ File  Edit  View  Go  Window  Help           │ <- Native Menu
├─────────────────────────────────────────────┤
│ [Sidebar] │ Tab Bar (open documents)         │
│           ├─────────────────────────────────┤
│ ■ Workspace│  Inkflow v1 Roadmap.md          │
│   ├─ blog/ │  # Inkflow                    │
│   ├─ docs/ │  ... content ...               │
│   └─ ideas/│                                │
│───────   │                                │
│ Recent   │                                │
│ Files     │                                │
│           │                                │
├───────────┴─────────────────────────────────┤
│ Status Bar: cursor pos, word count, theme,name│
└─────────────────────────────────────────────┘
```
- Sidebar width adjustable.  
- Tabs can be reordered, closed with middle-click.  
- Split view optional (for preview later).  

### Quick File Switching (⌘P)
- Modal overlay, list files in workspace + recent, fuzzy search.  
- Pure SwiftUI, floating window.

---

## 4. **Staged Development Roadmap (Agentic Workflow)**

Each phase is designed to be completed by a human guiding an AI agent (like Cursor or Copilot Chat) while reviewing every generated code block.

### **Phase 0: Project Setup & Tooling** *(Day 1–2)*
**Objectives:** Blank Xcode project with custom build settings, source control, and agent guidelines.

- [ ] Create Xcode project: macOS > App, use SwiftUI life cycle, Swift.
- [ ] Initialize Git repository locally, add `.gitignore` for Xcode.  
- [ ] Set up AI context file: `AI_CONTEXT.md` outlining architecture, naming conventions, rules for AppKit/SwiftUI bridging.  
  *This file will be pasted into agent chats to maintain consistency.*
- [ ] Configure `Sandbox` entitlement: `com.apple.security.files.user-selected.read-write` (for opening folders), disable network.  
- [ ] Add basic `Workspace` model struct, `Theme` struct, placeholder views.

**Agent prompts example:**
> "Create a macOS SwiftUI app target named Inkflow. Add a Sandbox capability with file read/write access. Set deployment target to macOS 14.0. Create a Models group with a Workspace.swift file containing a struct with a rootURL property."

---

### **Phase 1: Core Engine & Document Model** *(Day 3–6)*
**Objectives:** Open folders, read/write Markdown files, in-memory representation.

- [ ] Implement `WorkspaceManager` (singleton) that holds the current workspace.
- [ ] Add `FileDocument` class (ObservableObject): `url`, `content`, `isDirty`.
- [ ] Implement folder enumeration using `FileManager` with `.md` and `.txt` filters.
- [ ] Rudimentary file saving/loading with `String(contentsOf:)` and `write(to:)`.
- [ ] Unit tests for file read/write.

**Key AI assistance:**  
- Generate SwiftUI wrapper that opens an `NSOpenPanel` to pick a folder.  
- Broadcast changes via `Combine` `@Published` properties.

---

### **Phase 2: Workspace & File Tree** *(Day 7–10)*
**Objectives:** Sidebar with collapsible file tree, context menu actions.

- [ ] Build `FileTreeView` in SwiftUI using `OutlineGroup` with a recursive `FileItem` struct.
- [ ] Implement `FileMonitor` using `DispatchSource` to watch the workspace folder for additions/deletions (trigger recomputation of tree).
- [ ] Add context menu: create new file/folder, rename, delete, open in Finder.
- [ ] Connect double-click on file to open it as a new tab in the editor area.

**Agent involvement:**  
- Generate the `FileItem` tree from `FileManager` enumeration.  
- Build `FileMonitor` class that emits Combine events.

---

### **Phase 3: Editor & Syntax Highlighting** *(Day 11–16)*
**Objectives:** Full Markdown source editor with syntax coloring.

- [ ] Create `MarkdownEditorView`: `NSViewRepresentable` wrapping `NSTextView` inside an `NSScrollView`.
- [ ] Subclass `NSTextStorage` (`MarkdownTextStorage`) and integrate with `NSLayoutManager`.
- [ ] Implement background parser (regex-based) that finds headers, bold, italic, links, code blocks and assigns attributes.
- [ ] Wire up `textDidChange` to update `FileDocument` content and set `isDirty`.
- [ ] Add line numbers gutter (optional but nice for v1).

**Syntax Highlighting Details:**
```
Pattern priority:
1. Fenced code blocks (```)
2. Headers (# …)
3. Bold/italic (**…**, *…*)
4. Inline code (`…`)
5. Links ([text](url))
```
Apply colors from current theme.

**Agent prompts:**  
> "Create a Swift view named MarkdownEditorView that wraps NSTextView. Use NSViewRepresentable and provide bindings for text content and font size."

---

### **Phase 4: Session Recovery & Hot Exit** *(Day 17–21)*
**Objectives:** Never lose unsaved work.

- [ ] Design `SessionState` struct (Codable): open tab URLs, cursor positions, unsaved content (as base64 or temp file path), window frame, sidebar state.
- [ ] Implement `SessionManager`: save state on NSApplicationWillTerminate notification; save periodic snapshots (every 30 sec) for crash recovery.
- [ ] On app launch, check for `session.json` and prompt restore.
- [ ] Handle unsaved changes on quit: `NSDocument`-like "Do you want to save?" dialog, but custom because we use custom document model.
- [ ] Test scenario: force quit the app, reopen, see all tabs and unsaved content.

**Agent-assisted generation:**  
- Codable session struct.  
- Combine-based auto-save.  
- Window frame capture via `NSWindow.frameAutosaveName`.

---

### **Phase 5: Quick Navigation & Recent Files** *(Day 22–25)*
**Objectives:** ⌘P quick open, recent files list.

- [ ] `QuickSwitchView`: SwiftUI sheet with text field and dynamic list filtered by fuzzy matching (use a simple algorithm).
- [ ] Register `RecentFilesService` that persists an ordered list of opened file URLs to UserDefaults.
- [ ] Add sidebar section “Recent Files” reusing file tree items but with recency sorting.
- [ ] Keyboard shortcut management via `KeyboardShortcuts` package or manual key equivalent setup.

---

### **Phase 6: Themes & Layout Controls** *(Day 26–30)*
**Objectives:** Look and feel customization.

- [ ] Define 3–4 built-in themes (Light, Dark, Solarized, High Contrast). Theme data: JSON files in bundle.
- [ ] `ThemeManager` publishes current theme applied globally.
- [ ] `AppearanceSettingsView`: theme picker grid, font picker (system fonts), size slider, line height stepper, editor width slider.
- [ ] Propagate changes to all open editors via `Environment`.
- [ ] Ensure NSTextView text attributes refresh when theme changes.

**UI for layout:**  
- Use `Form`-style in a preferences window or as a sidebar pane.
- Preview live in a small editor sample.

---

### **Phase 7: Integration, Polish & App Delivery** *(Day 31–40)*
**Objectives:** Make it shippable.

- [ ] Menu bar integration: File > New, Open, Open Folder, Open Recent, Save, Close Tab, Preferences.  
- [ ] Closing tabs correctly handles unsaved changes (use alert).  
- [ ] Window title reflects current document name + workspace name.  
- [ ] App icon (temporary) and about panel.  
- [ ] Performance profiling with Instruments; ensure large files (1MB) are highlighted without lag.  
- [ ] Accessibility: VoiceOver labels, keyboard navigation in sidebar.  
- [ ] Code signing & notarization (for distribution outside App Store).  
- [ ] Create a DMG installer.  
- [ ] Write a `README.md` and basic user guide.  
- [ ] Prepare release notes.

---

## 5. **Agentic Development Cheat Sheet**

**When to use AI:**  
- Boilerplate SwiftUI views.  
- Complex Combine pipelines.  
- Generating test stubs.  
- Regex patterns for syntax highlighting.  
- Documentation strings.

**How to prompt effectively:**  
Always start with:  
> “Using Swift 6 and macOS 14+, implement [feature] with AppKit/SwiftUI as described. Follow MVVM, use Combine, and avoid force unwrapping. Include error handling and unit tests.”

**Review pipeline:**  
1. AI generates code.  
2. Run in Xcode – check for build errors.  
3. Manually review memory management (retain cycles in Combine).  
4. Test edge cases.  
5. Commit with descriptive message.

**Tools recommended:**  
- **Cursor** or **GitHub Copilot X** for inline generation.  
- **Xcode 16+** with integrated swift-format.  
- **Playgrounds** for quick prototyping of text storage logic.

---

## 6. **Testing Strategy**

- **Unit Tests:**  
  - Markdown parser output against known strings.  
  - File tree logic (mocked FileManager).  
  - Session serialization/deserialization.  
  - Theme application correctness.

- **Integration Tests:** (using `XCTest` with temporary directories)  
  - Workspace opening, file creation, monitoring.  
  - Saving unsaved changes on quit simulation.

- **UI/Performance Testing:**  
  - Large file (10k lines) editing responsiveness.  
  - Session recovery time.

- **Manual QA checklist:**  
  - Launch with no workspace, open folder → file tree populates.  
  - Edit file, force quit, reopen → unsaved changes still there.  
  - Switch themes while editing → no loss of cursor.

---

## 7. **Source Control & Release Flow**

- **Branching:** `main` (stable), `develop` (integration), feature branches per phase.  
- **Protection:** Require all unit tests to pass locally before merge.  
- **Tagging:** Semantic version `v1.0.0-beta.1`, then `v1.0.0`.  
- **CI/CD (optional later):** GitHub Actions to run tests on push.

**Commit conventions:**  
`[Phase2] Add FileTreeView with recursive outline group`  
`[Phase3] Fix syntax highlighter regex for bold patterns`

---

## 8. **Future Vision (v2+)**

While v1 is strict, the architecture leaves hooks for expansion:

- **Preview Mode**: Add a second `WebView` (or `NSTextView` with different rendering) that shows rendered Markdown in real-time. Already have parsed tokens.  
- **Visual Editing**: Use the same token stream to selectively replace raw markdown with styled versions (WYSIWYM).  
- **Custom Plugins**: Expose a scripting API (AppleScript or JavaScript) that can manipulate the editor.  
- **AI Tools**: Run a local LLM via `llama.cpp` and integrate with the editor to suggest completions, summarization, etc. MCP servers could be clients.  
- **Pandoc Export**: Call `pandoc` binary bundled or detected in PATH.  
- **Terminal Integration**: Embed a terminal pane using `SwiftTerm` library.  

All these can be built as separate agent-driven phases following the same methodology.

---

## 🧰 **Final Checklist for Launch**

- [ ] App passes App Translocation (Gatekeeper notarization).  
- [ ] No disk writes outside of sandbox-approved directories.  
- [ ] All mandatory features implemented.  
- [ ] README and basic doc.  
- [ ] DMG with background image.  
- [ ] Version compatible with macOS Tahoe (ensure no deprecated APIs for that release).  

---

> **Your mission:** Print this plan, tape it to your secondary monitor, and attack one phase at a time. Use AI as your tireless junior developer, but you are the architect. Ship v1, then iterate.

---

*“The best writing app is the one that gets out of the way.”* – that’s Inkflow.

```
