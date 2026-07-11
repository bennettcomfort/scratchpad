# Risk Register

| Risk | Probability | Impact | Mitigation |
|---|---:|---:|---|
| Data loss from bad save path | Medium | Critical | Atomic writes, dirty-state tests, recovery buffers |
| Silent overwrite of external edits | Medium | Critical | Track hash/mod date, conflict flow |
| Cursor jump in `NSTextView` wrapper | High | Medium | Preserve selection, avoid full text reset in update cycle |
| Syntax highlighter causes lag | Medium | Medium | Debounce, file-size threshold, visible-range highlighting |
| Security-scoped bookmarks fail after relaunch | Medium | High | Dedicated BookmarkManager, explicit reselect flow |
| Workspace scan freezes UI | Medium | Medium | Background scan, ignore heavy dirs, lazy tree loading |
| Too many dependencies slow v1 | High | High | Start vanilla; spike dependencies only |
| SwiftData adds unnecessary complexity | Medium | Medium | Use JSON/UserDefaults for v1 |
| Platform target confusion | Medium | Medium | Decide minimum macOS target before code |
| Scope creep into preview/WYSIWYG/AI | High | High | Defer list in PRODUCT.md and RULES.md |
| Agent-generated code creates architecture drift | High | Medium | AGENTS.md, small slices, review diffs, tests |
