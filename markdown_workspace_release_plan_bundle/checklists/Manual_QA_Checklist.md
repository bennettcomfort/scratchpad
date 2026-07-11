# Manual QA Checklist — Data Loss and Release Readiness

## Critical Data-Loss Tests

- [ ] Open file, edit, save, verify external file contents.
- [ ] Open file, edit, failed save due to permission issue, verify dirty state remains.
- [ ] Open file, edit, quit without save, relaunch, verify dirty text restored.
- [ ] Open file, edit, force quit, relaunch, verify dirty text restored.
- [ ] Open file, edit, external file changes, save attempt shows conflict.
- [ ] Open file, external delete, app keeps buffer open.
- [ ] Deleted file can be saved as new copy.
- [ ] Recovery buffers are deleted after successful save.
- [ ] Clean saved file does not reopen as dirty.
- [ ] Cursor and scroll position restore after quit/relaunch.

## Workspace Tests

- [ ] Open workspace folder.
- [ ] Relaunch and restore workspace via bookmark.
- [ ] Missing workspace prompts reselect.
- [ ] Hidden folders excluded.
- [ ] Large workspace does not freeze UI.
- [ ] File tree sorts folders first.
- [ ] Unsupported binary files are not opened as text by accident.

## Editor Tests

- [ ] Typing feels native.
- [ ] Undo/redo works.
- [ ] Cursor does not jump after syntax highlighting.
- [ ] Scroll does not reset on text state update.
- [ ] Large Markdown file remains usable.
- [ ] Syntax highlighter never changes document text.

## Navigation Tests

- [ ] Cmd+P opens quick switcher.
- [ ] Fuzzy search finds files by filename.
- [ ] Fuzzy search finds files by path segment.
- [ ] Enter opens selected file.
- [ ] Escape closes overlay.
- [ ] Empty query shows recent files.

## Settings and Layout Tests

- [ ] Theme changes apply immediately.
- [ ] Font size persists after relaunch.
- [ ] Line height persists after relaunch.
- [ ] Readable width mode centers editor.
- [ ] Dark mode looks credible.
- [ ] High contrast theme is usable.

## Release Tests

- [ ] Release build archives successfully.
- [ ] App is signed.
- [ ] App is notarized.
- [ ] DMG opens and installs.
- [ ] App launches after install.
- [ ] No critical crash on clean machine.
