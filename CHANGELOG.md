# Changelog

## 1.0.0 — 2026-07-13

### Features
- **Zen scratch window** — `⌃⌥Space` global hotkey summons a clean Markdown scratchpad; `⌘⏎` or `Esc` dismisses it
- **Scratch-first editing** — open plain-text buffers persist via recovery across restarts, no save required
- **File open/save** — `⌘O` to open `.md`/`.txt` files; `⌘S` to save; `⇧⌘S` for Save As
- **Tabs** — multi-buffer editing with tab bar (appears at 2+ buffers); `⌘W` closes with dirty-save prompt; `⌘{`/`⌘}` switching
- **Workspace sidebar** — `⇧⌘O` opens a folder; file tree in sidebar (`⌘\` toggle); context menus for Open, Reveal, Copy Path, New File
- **⌘P Quick Switcher** — fuzzy search across open buffers and workspace files; `↑↓⏎` navigation
- **Markdown syntax highlighting** — headings, bold, italic, inline code, fenced code blocks, blockquotes, lists, horizontal rules, frontmatter
- **4 themes** — Scratch Dark (default), Scratch Light, System, High Contrast; live theme switching; configurable padding
- **Status bar** — word count, line:column, save state (saved/unsaved/conflicted/deleted)
- **External change detection** — silent reload of clean files; conflict marking for dirty files; deleted-on-disk notification
- **Hot exit** — all unsaved text automatically recovered on relaunch

### Architecture
- Swift 6 + SwiftUI + AppKit `NSTextView` (TextKit 2)
- Zero third-party runtime dependencies
- Atomic file writes, security-scoped bookmarks, session/recovery persistence
- macOS 26+, hardened runtime
