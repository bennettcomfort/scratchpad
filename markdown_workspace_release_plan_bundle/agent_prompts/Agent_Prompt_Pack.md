# Agent Prompt Pack — macOS Markdown Workspace

## Global Agent Rules

```markdown
You are implementing a native macOS Markdown workspace in Swift.

Hard rules:
- Use SwiftUI for app shell.
- Use AppKit NSTextView for editor core.
- Do not use Electron, Tauri, WYSIWYG, plugin system, AI sidebar, Pandoc, SwiftData, or tree-sitter unless explicitly requested for a spike.
- User documents remain plain files on disk.
- Do not silently overwrite user files.
- Hot exit saves recovery buffers, not original files.
- Keep changes small, testable, and reviewable.
- Before implementing, explain touched files and acceptance criteria.
```

---

## Stage 1 Prompt — Native App Shell

```markdown
You are a senior macOS Swift engineer.

Implement Stage 1: Native App Shell.

Requirements:
1. Create/maintain a SwiftUI macOS app shell.
2. Add an AppDelegate bridge for lifecycle events.
3. Add MainWindowView with placeholder sidebar and editor area.
4. Add menu commands for Open File, Open Workspace, Save, Settings.
5. Add Settings placeholder.
6. Add ApplicationSupportPaths helper.
7. Add Logger utility.

Do not implement file opening or editor logic yet.

Acceptance:
- App launches.
- Window opens.
- Menu bar exists.
- Settings placeholder opens.
- No warnings caused by this change.
```

---

## Stage 2 Prompt — Single File Open/Edit/Save

```markdown
Implement Stage 2: Single-file open/edit/save.

Requirements:
1. Add FileService for reading text files.
2. Open .md, .markdown, .mdown, .txt using NSOpenPanel.
3. Decode UTF-8 first.
4. Display loaded text in temporary basic editor.
5. Track dirty state.
6. Implement Cmd+S.
7. Add AtomicFileWriter:
   - write temp file in same directory
   - atomically replace original
   - mark clean only after success
8. Handle missing/read-only file errors.

Do not add workspace or tabs yet.

Acceptance:
- Open Markdown file.
- Edit and save.
- Failed save does not mark clean.
- Reopen externally and verify content.
```

---

## Stage 3 Prompt — NSTextView Editor Core

```markdown
Implement Stage 3: AppKit NSTextView editor core.

Requirements:
1. Create MarkdownEditorView as NSViewRepresentable.
2. Wrap NSScrollView + NSTextView.
3. Bind text two-way without update loops.
4. Preserve selected range and scroll offset.
5. Support undo/redo.
6. Report cursor position and dirty changes.
7. Avoid resetting text view content unless external text changed.

Do not implement syntax highlighting yet.

Acceptance:
- Typing feels native.
- Undo/redo works.
- Cursor does not jump.
- Scroll does not reset during updates.
```

---

## Stage 6 Prompt — Session Recovery

```markdown
Implement Stage 6: Session Recovery and Hot Exit.

Requirements:
1. Add AppSession Codable model.
2. Add EditorSession Codable model.
3. Add SessionManager.
4. Add RecoveryBufferStore.
5. Save session metadata:
   - workspace bookmark if present
   - open tabs
   - active tab
   - cursor positions
   - scroll positions
   - window frame
   - sidebar width
   - theme/layout IDs
6. Save dirty buffers to recovery JSON every 1–3 seconds after text changes.
7. On launch, restore session and dirty buffers.
8. Use didCloseCleanly flag to detect crash/force quit.

Rule:
- Do not overwrite original files during hot exit restore.
- Restored dirty buffers should remain dirty until user saves.

Acceptance:
- Quit without saving restores dirty text.
- Force quit restores dirty text.
- Cursor/scroll/sidebar/window state restore.
```

---

## Stage 8 Prompt — Markdown Highlighting

```markdown
Implement Stage 8: Markdown syntax highlighting.

Requirements:
1. Add MarkdownHighlighter.
2. Highlight:
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
3. Debounce highlighting 100–300ms.
4. Never mutate actual string.
5. Preserve selected range.
6. Add file-size threshold where highlighter simplifies/disables.
7. Add unit tests for tokenizer ranges.

Do not add tree-sitter yet.

Acceptance:
- Styling appears.
- Cursor does not jump.
- Highlighting never changes text.
- Large file does not freeze editor.
```
