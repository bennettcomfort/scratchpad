# Scratchpad Recovery Regression Matrix

> This matrix assigns proof. A scenario becomes verified only when its named automated test and manual check both have fresh evidence in `TRACKER.md`.

| Scenario | Owning stage | Automated proof | Manual proof | Current state |
|---|---:|---|---|---|
| Active editor owns exactly one document's storage | 1 | `DocumentSessionTests.testEachSessionOwnsDistinctTextStorage` and `EditorHostTests.testHostUsesTextKit2AndSessionStorage` | Type in a document, replace it, and confirm old text cannot appear or change | pending |
| Two concurrent future opens for one URL produce one document | deferred tabs | `DocumentRegistryTests.testConcurrentOpenDeduplicatesCanonicalURL` | Double-open one file and observe one tab | pending |
| Save-and-Close waits and remains open on save failure | 3 | `DocumentDecisionCoordinatorTests.testFailedSaveCancelsCloseAndKeepsDocumentEdited` | Induce a write failure and confirm text remains open and edited | pending |
| Recovery work is isolated per document identity | 3 | `RecoveryCoordinatorTests.testDebounceTasksAreIndependentByDocumentID` | Covered again when multi-document returns | pending |
| Clean file restoration reads disk rather than empty recovery text | 3 | `RecoveryCoordinatorTests.testCleanFileBackedLaunchReopensDiskInsteadOfRecoveryText` | Relaunch a clean file-backed document and compare its contents | pending |
| Dirty restoration retains base metadata and enters conflict flow | 3 | `SessionRepositoryTests.testRecoveryRoundTripsEveryField` and `DocumentDecisionCoordinatorTests.testConflictSupportsOverwriteReloadSaveAsAndCancel` | Edit, terminate, change disk externally, relaunch, and resolve conflict | pending |
| Graceful termination persists the latest keystroke | 3 | `RecoveryCoordinatorTests.testExplicitFlushCancelsPendingTaskAndWritesLatestText` and `ApplicationLifecycleTests.testTerminationReturnsLaterAndRepliesTrueAfterFlush` | Type a unique suffix, Quit immediately, and relaunch | pending |
| Security-scoped access survives sandboxed relaunch | 3 | `BookmarkStoreTests.testReferenceLookupUsesPersistedPathHintWithoutDirectAccess` | Open outside the container, quit, relaunch, and save successfully | pending |
| Each editor command fires once and remains undoable | 2 | focused router tests plus `ScratchTextViewCommandTests.testEveryTextChangingCommandUndoesInOneOperation` and `AppCommandsTests.testResponderActionReachesFocusedScratchTextViewExactlyOnce` | Run the full shortcut matrix and undo every transformation | pending |
| Information metrics update without a SwiftUI text copy | 4 | `DocumentMetricsTests` plus `MetricsCoordinatorTests.testCoordinatorDiscardsDifferentIdentityOrGenerationResult` | Type continuously and inspect correct counts without UI stalls | pending |
| Settings changes avoid global defaults notifications | 4 | `SettingsStoreTests.testSettingsChangesPublishOneTypedSnapshotWithoutNotificationCenter` | Change each setting and observe only its intended UI effect | pending |
| Future sidebar resizing uses native split view | deferred workspace | `WorkspaceSplitViewTests.testResizePersistsOnlyOnCommit` | Drag repeatedly with no shaking or pointer drift | pending |
| Future hotkey registration has one owner and visible failures | deferred Zen | `HotkeyManagerTests.testRegistrationFailureIsPublished` | Rebind to a conflicting shortcut and observe an actionable error | pending |
| Future highlighting discards stale generations | deferred highlighting | `HighlightPipelineTests.testStaleGenerationIsDiscarded` | Paste a large document while typing and observe responsive correct styling | pending |
