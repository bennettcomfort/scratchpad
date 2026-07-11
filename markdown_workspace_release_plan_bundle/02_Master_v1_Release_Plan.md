# Master v1 Release Plan — Native macOS Markdown Workspace

## Product Definition

**Product:** Native macOS Markdown workspace  
**Primary mode:** Raw Markdown source editing  
**Storage model:** Local files and folders  
**Core promise:** Open a folder, edit files, save safely, switch quickly, quit/crash/reopen without losing work.

---

## Non-Negotiables

```text
- Native macOS app
- Plain-text files remain plain files
- No proprietary content database for user documents
- No network requirement
- No Electron/Tauri
- No WYSIWYG in v1
- No AI/plugin system in v1
- No silent data loss
- No silent overwrite of external changes
```

---

## Final Architecture

```text
App/
  MarkdownWorkspaceApp.swift
  AppDelegate.swift
  AppCommands.swift
  MainWindowView.swift

Domain/
  Workspace.swift
  FileNode.swift
  DocumentBuffer.swift
  DocumentSaveState.swift
  AppSession.swift
  EditorSettings.swift
  Theme.swift
  RecentItem.swift

Services/
  WorkspaceManager.swift
  FileTreeBuilder.swift
  FileIndexer.swift
  DocumentManager.swift
  FileService.swift
  SessionManager.swift
  RecoveryBufferStore.swift
  BookmarkManager.swift
  RecentItemsManager.swift
  ThemeManager.swift
  ExternalChangeMonitor.swift

Editor/
  MarkdownEditorView.swift
  MarkdownTextViewCoordinator.swift
  MarkdownHighlighter.swift
  EditorViewModel.swift
  EditorStatusBar.swift

Features/
  Welcome/
  Workspace/
  Sidebar/
  Tabs/
  QuickSwitcher/
  Settings/

Persistence/
  ApplicationSupportPaths.swift
  JSONStore.swift
  AtomicFileWriter.swift
  PreferencesStore.swift

Utilities/
  Debouncer.swift
  FuzzySearch.swift
  FileEncodingDetector.swift
  Logger.swift
  Hashing.swift

Tests/
  UnitTests/
  IntegrationTests/
  UITests/
  ManualQA.md
```

---

# Implementation Roadmap

## Stage 0 — Product Lock and Repo Setup

### Goal

Prevent scope creep before code starts.

### Tasks

- Create `PRODUCT.md`
- Create `SPEC.md`
- Create `ARCHITECTURE.md`
- Create `RULES.md`
- Create `TODO.md`
- Create `AGENTS.md`
- Decide app name and bundle ID
- Decide minimum macOS target
- Initialize Git repo
- Add `.gitignore`
- Add `CHANGELOG.md`

### Acceptance Criteria

- v1 scope is frozen.
- Deferred features are explicitly listed.
- App name and bundle ID are chosen.
- Repo builds from a blank Xcode project.

---

## Stage 1 — Native App Shell

### Goal

A compiling macOS app with correct structure.

### Tasks

- Create SwiftUI macOS app.
- Add AppDelegate bridge.
- Add main window.
- Add menu commands.
- Add placeholder sidebar/editor/settings.
- Add Application Support path helpers.
- Add logging utility.

### Acceptance Criteria

- App launches.
- Window opens.
- Menu bar exists.
- Settings window placeholder opens.
- No editor/file logic yet.

---

## Stage 2 — Single-File Open/Edit/Save

### Goal

Prove the core file loop before workspace complexity.

### Tasks

- Implement `FileService`.
- Open `.md`/`.txt` file with `NSOpenPanel`.
- Read UTF-8 text.
- Show text in basic editor.
- Save with `Cmd+S`.
- Track dirty state.
- Add atomic writer.
- Add read-only/missing-file error handling.

### Acceptance Criteria

- Open a Markdown file.
- Edit it.
- Save it.
- Reopen externally and verify content.
- Dirty indicator is correct.
- Failed saves do not mark clean.

---

## Stage 3 — AppKit Editor Core

### Goal

Replace basic text area with real `NSTextView`.

### Tasks

- Implement `NSViewRepresentable` wrapper.
- Use `NSScrollView + NSTextView`.
- Preserve text selection.
- Preserve cursor position.
- Preserve scroll position.
- Support undo/redo.
- Add editor settings plumbing.

### Acceptance Criteria

- Typing feels native.
- `Cmd+Z` / `Cmd+Shift+Z` work.
- Cursor does not jump.
- Scroll does not reset on state updates.
- Large text file does not instantly freeze.

---

## Stage 4 — Workspace Opening and Bookmarks

### Goal

Open a folder as a workspace.

### Tasks

- Use `NSOpenPanel` for folder selection.
- Create security-scoped bookmark.
- Persist workspace bookmark.
- Resolve bookmark on relaunch.
- Build recursive file tree.
- Ignore excluded dirs/files.
- Add Welcome screen with recent workspaces.

### Acceptance Criteria

- Open folder.
- Sidebar shows supported files.
- Relaunch restores workspace access.
- Missing/moved workspace prompts reselect.

---

## Stage 5 — Tabs and Document Manager

### Goal

Support multiple open files safely.

### Tasks

- Add `DocumentBuffer` model.
- Add `DocumentManager`.
- Open files into tabs.
- Track active tab.
- Track dirty state per tab.
- Close clean tab.
- Prompt on dirty close.
- Save current file.
- Save all.

### Acceptance Criteria

- Open multiple files.
- Switch tabs.
- Dirty dot appears per tab.
- Closing dirty tab prompts correctly.
- Saving one tab does not affect others.

---

## Stage 6 — Session Recovery and Hot Exit

### Goal

Make unsaved work survive quit/crash.

### Tasks

- Add `AppSession` model.
- Add `SessionManager`.
- Add `RecoveryBufferStore`.
- Snapshot session metadata.
- Snapshot dirty buffers every 1–3 seconds after changes.
- Save cursor/scroll/sidebar/window state.
- Detect unclean shutdown.
- Restore dirty buffers on launch.

### Acceptance Criteria

- Edit file, quit without saving, relaunch: dirty text restored.
- Force quit, relaunch: dirty text restored.
- Cursor position restored.
- Scroll position restored.
- Sidebar width restored.
- Saved files stay clean.
- Recovery buffers deleted after successful save.

---

## Stage 7 — Quick Switcher and Recents

### Goal

Make navigation fast.

### Tasks

- Add `FileIndexer`.
- Add `FuzzySearch`.
- Add QuickSwitcher overlay.
- Support `Cmd+P`.
- Show relative paths.
- Add recent files.
- Add recent workspaces.
- Boost recent matches.

### Acceptance Criteria

- `Cmd+P` opens under 100ms on normal workspace.
- Typing fuzzy query filters instantly.
- Arrow keys navigate.
- Enter opens selected file.
- Escape closes overlay.
- Empty query shows recent files.

---

## Stage 8 — Markdown Syntax Highlighting

### Goal

Add useful source-mode highlighting without destabilizing editor.

### Tasks

- Add `MarkdownHighlighter`.
- Tokenize headings, emphasis, code, links, lists, quotes, frontmatter.
- Debounce highlighting.
- Preserve selection.
- Add file-size threshold.
- Add highlighter tests.

### Acceptance Criteria

- Markdown tokens styled.
- Cursor does not jump.
- Selection does not break.
- Large file threshold disables expensive highlighting.
- Highlighter never changes document text.

---

## Stage 9 — Themes, Fonts, and Layout

### Goal

Make the app pleasant to write in.

### Tasks

- Add `Theme` model.
- Add built-in themes.
- Add font picker or simple font list.
- Add font size controls.
- Add line height.
- Add editor max width.
- Add line wrapping.
- Persist settings.

### Acceptance Criteria

- Theme changes immediately.
- Font/layout settings apply to active editor.
- Settings persist after relaunch.
- Dark/light mode looks credible.

---

## Stage 10 — External File Changes and Conflict Handling

### Goal

Avoid overwriting outside edits.

### Tasks

- Track file modification date/hash.
- Detect external changes before save.
- Detect deleted files.
- Add conflict banner/alert.
- Add options: Reload, Keep Mine, Save As, Cancel.

### Acceptance Criteria

- Clean open file changed externally: app handles it.
- Dirty open file changed externally: app warns before overwrite.
- Deleted file stays open as buffer.
- Save As works from missing/deleted state.

---

## Stage 11 — Native Polish and Hardening

### Goal

Make it feel like a serious macOS app.

### Tasks

- Complete menu commands.
- Add status bar: word count, line/column, save state.
- Add Reveal in Finder.
- Add Copy Path.
- Add keyboard shortcuts.
- Add error banners.
- Add app icon.
- Test full screen.
- Test multiple monitors.
- Test dark/light mode.

### Acceptance Criteria

- App has no obvious rough edges.
- Errors are understandable.
- Native menus work.
- Keyboard workflow is credible.
- App feels stable.

---

## Stage 12 — Release Preparation

### Goal

Ship v1.

### Tasks

- Set bundle ID.
- Set version/build numbers.
- Configure signing.
- Archive release build.
- Notarize app.
- Create DMG.
- Create release notes.
- Create changelog.
- Run final QA matrix.

### Acceptance Criteria

- App is signed.
- App is notarized.
- DMG opens/installs correctly.
- No known critical data-loss bugs.
- Manual QA passes.

---

# Final v1 Feature List

## Must Ship

```text
- Native macOS app shell
- Open file
- Open folder/workspace
- Security-scoped workspace access
- Sidebar file tree
- Raw Markdown editor
- Safe save
- Dirty state
- Tabs
- Quick file switcher
- Recent files/workspaces
- Session restore
- Dirty buffer recovery
- Cursor/scroll restore
- Built-in themes
- Font/layout controls
- Basic syntax highlighting
- Signed/notarized DMG
```

## Should Ship If Not Risky

```text
- Status bar
- Reveal in Finder
- Copy path
- Basic external-change warning
- Basic find
- New file
```

## Defer

```text
- Live preview
- WYSIWYG
- Plugins
- AI sidebar
- MCP
- Terminal
- Pandoc export
- Custom theme editor
- Tree-sitter-based full Markdown parser
- SwiftData metadata store
- Sparkle auto-update
- Command palette beyond file switching
```
