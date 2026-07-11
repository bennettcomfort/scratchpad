**macOS Markdown Workspace — v1 Release Plan**  
**Product:** Local-first, plain-text Markdown workspace (macOS Tahoe only)  
**Team:** Solo developer (you) + AI agents  
**Machine:** M3 Max, 64 GB RAM

---

### 1. Project Vision & Constraints

**Core Promise**  
A fast, native, file-system-native Markdown workspace that feels like a souped-up version of BBEdit + Obsidian’s file handling but stays 100% local and lightweight.

**Non-negotiables for v1**
- Pure native Swift/SwiftUI (no Electron/Tauri)
- Sandbox-friendly (App Store ready)
- Everything stored as plain `.md`/`.txt` files
- Session state survives quit/crash
- Keyboard-first, minimal UI chrome

---

### 2. Recommended Technology Stack (v1)

| Layer              | Technology                          | Reason |
|--------------------|-------------------------------------|--------|
| Language           | Swift 6 + SwiftUI                   | Native performance, Tahoe features |
| Editor             | `TextKit 2` + `NSTextView` (wrapped) | Best syntax highlighting + performance |
| Syntax Highlighting| Tree-sitter or Highlightr           | Fast, themeable |
| File System        | `FileManager` + `NSFilePresenter`   | Live folder watching |
| State Persistence  | `Codable` + `UserDefaults` + JSON   | Session recovery |
| Theming            | SwiftUI `Color` + `Font` + CSS subset | Easy custom themes later |
| Build System       | Xcode + Swift Package Manager       | Simple |
| AI Assistance      | Cursor + Claude 3.5 Sonnet / GPT-4o | Agentic coding |

**Future (post-v1)**: SwiftData for metadata index, Apple Intelligence integration, Swift Macros for commands.

---

### 3. High-Level Architecture

```
App
├── WorkspaceManager (opens folders, watches files)
├── DocumentStore (in-memory + file sync)
├── EditorCoordinator (manages tabs + state)
├── ThemeEngine
├── LayoutEngine (font size, line height, width, etc.)
└── SessionRestorer
```

**Key Design Decisions**
- Single-window app with detachable tabs (Tahoe style)
- Sidebar = file tree (lazy-loaded)
- Editor = one `TextKit 2` view per tab
- All state serializable to JSON for hot exit

---

### 4. Staged Development Roadmap (Agentic)

#### Stage 0 – Setup & Scaffolding (1–2 days)
- Create Xcode project with Swift 6, strict concurrency
- Set up App Sandbox + File Access entitlements
- Add Swift Package dependencies: `Highlightr`, `TreeSitter`, `SwiftLint`
- Initialize Git + `.gitignore`

**Agent Prompt Example**  
> “Create a new macOS SwiftUI app called ‘Plain’ with proper Sandbox entitlements and a basic three-column layout (sidebar + editor + inspector).”

#### Stage 1 – Core File System (3–4 days)
- Open folder as workspace
- Recursive file tree (lazy)
- Create / rename / delete files from sidebar
- Live file watching with `NSFilePresenter`

#### Stage 2 – Editor Foundation (4–5 days)
- Raw Markdown editing with syntax highlighting
- Open / edit / save `.md` and plain text
- Multiple tabs + drag-to-reorder
- Basic undo/redo with `TextKit 2`

#### Stage 3 – Session Recovery (2–3 days)
- Save: open tabs, cursor positions, scroll position, split state
- Restore on launch (even after crash)
- “Reopen windows” behavior

#### Stage 4 – Productivity Features (3–4 days)
- Quick file switcher (`⌘P`)
- Recent files list (persistent)
- Command palette skeleton

#### Stage 5 – Theming & Layout (3 days)
- 4–5 built-in themes (including a “Writer” and “Code” theme)
- Font picker + size, line height, editor width, alignment
- Real-time layout updates

#### Stage 6 – Polish & Release Prep (4–5 days)
- Menu bar + keyboard shortcuts
- About window, acknowledgments
- Export to PDF / HTML (basic)
- App Store / notarization pipeline
- Sparkle or manual update mechanism

---

### 5. Agentic Development Workflow (Recommended)

**Primary Tools**
- **Cursor** (main IDE) – best agentic experience
- **Claude Projects** – keep full architecture + spec in context
- **Custom GPT** – “macOS Tahoe SwiftUI Expert”

**Daily Loop**
1. Write detailed prompt describing the next small slice
2. Ask agent to generate + explain
3. Review + iterate in Cursor
4. Run tests / build
5. Commit with conventional commits

**Useful Prompt Template**
> “You are a senior macOS engineer. Implement [feature] using SwiftUI + TextKit 2. Follow these constraints: [list]. Make it testable. Include comments.”

---

### 6. UI/UX & Design System

**Design Principles**
- Maximum text, minimum chrome
- Consistent 8-point spacing
- Two accent colors max

**Layout Controls (v1)**
- Font family + size
- Line height (1.2 – 2.0)
- Content width (narrow / comfortable / wide / full)
- Alignment (left / justified)

**Theme Format** (simple JSON)
```json
{
  "name": "Writer",
  "background": "#FFFBF0",
  "text": "#1F1F1F",
  "accent": "#0066FF",
  "syntax": { ... }
}
```

---

### 7. Testing Strategy

- Unit tests: `WorkspaceManager`, `SessionRestorer`
- UI tests: Tab management, file operations
- Manual: Open 500-file folder, crash app mid-edit, restart

---

### 8. Build, Source Control & Release

**Git Workflow**
- `main` protected
- Feature branches: `feat/session-recovery`
- Conventional commits

**Release Process**
1. Archive in Xcode
2. Notarize
3. DMG + App Store version
4. Update `CHANGELOG.md`

**Distribution Options**
- Direct DMG (simplest for v1)
- Mac App Store (add receipt validation later)

---

### 9. Future Phases (Post-v1)

**Phase 2** — Live preview pane + WYSIWYG toggle  
**Phase 3** — AI sidebar (local models via MLX or Ollama)  
**Phase 4** — Plugin system + custom commands  
**Phase 5** — Pandoc export + TextBundle support

---

### 10. Immediate Next Steps (Start Today)

1. Create Xcode project with the exact name and bundle ID you want
2. Set up Cursor + Claude project with this entire spec
3. Implement **Stage 0** scaffolding
4. Commit and push to GitHub (private repo)

Would you like me to generate the exact **Stage 0 prompt pack** (ready to paste into Cursor) or the **detailed architecture document** (with class names and data models) next?
