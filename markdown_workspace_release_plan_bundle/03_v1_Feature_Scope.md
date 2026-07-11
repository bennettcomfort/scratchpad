# v1 Feature Scope

## Must Ship

| Feature | v1 Direction |
|---|---|
| Native macOS app shell | SwiftUI app shell |
| Raw Markdown editor | AppKit `NSTextView` |
| Open file | `NSOpenPanel` |
| Open workspace | Folder picker + bookmark |
| Safe save | Atomic writer |
| Dirty state | Hash-based dirty tracking |
| Tabs | DocumentManager |
| Session restore | JSON session store |
| Recovery buffers | JSON recovery files |
| Quick switcher | `Cmd+P` fuzzy search |
| Recent files/workspaces | JSON/UserDefaults + optional NSDocumentController |
| Built-in themes | Hardcoded or bundled definitions |
| Font/layout controls | Settings panel |
| Basic syntax highlighting | Regex/token scanner |

## Defer

| Feature | Reason |
|---|---|
| Live preview | Scope creep |
| WYSIWYG | Editor complexity |
| Plugins | Architecture risk |
| AI sidebar | Not core to v1 |
| MCP | Not core to v1 |
| Pandoc export | Release blocker risk |
| SwiftData metadata store | Unnecessary complexity |
| tree-sitter parser | Optional later optimization |
| Sparkle updates | Post-v1 distribution polish |
| Custom theme editor | Not needed for v1 |
