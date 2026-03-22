---
phase: 03-triage-actions
plan: 03
subsystem: ui
tags: [flutter, multi-select, batch-tag, supabase, triage, provider, getit]

# Dependency graph
requires:
  - phase: 03-triage-actions
    plan: 03-01
    provides: "batchSaveTriage in BugReportRepository and triage data layer"
  - phase: 03-triage-actions
    plan: 03-02
    provides: "ReportListController with refresh(), ReportListScreen list items"
provides:
  - "Multi-select mode on report list (long-press to enter, tap to toggle)"
  - "Batch tag picker bottom sheet applying one tag to all selected reports"
  - "Selection-aware AppBar with count display and clear/select-all actions"
  - "Bottom action bar with 'Tag selected' FilledButton"
  - "Back button interception via PopScope — clears selection instead of navigating back"
  - "Cross-product selection leak prevention via clearSelection in loadReports"
affects: [04-github-sync]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Set<String> selectedIds in ChangeNotifier for multi-select state"
    - "PopScope(canPop: !isSelectionMode) pattern for intercepting back navigation"
    - "Conditional AppBar title and leading based on selection state"
    - "Bottom sheet tag picker reused from detail screen via inline _showBatchTagPicker"

key-files:
  created: []
  modified:
    - lib/application/controllers/report_list_controller.dart
    - lib/presentation/screens/report_list_screen.dart

key-decisions:
  - "clearSelection called at start of loadReports — prevents selected IDs from a previous product leaking into a new product's list view"
  - "PopScope(canPop: !isSelectionMode) with onPopInvokedWithResult — replaces deprecated WillPopScope; clears selection on back press without exiting screen"
  - "_showBatchTagPicker inlined in report_list_screen.dart rather than extracted to a shared utility — plan explicitly deferred extraction to Phase 3; keeps scope tight"
  - "Bottom action bar uses SafeArea inside Container — ensures bar renders above system navigation gesture area on modern Android"

patterns-established:
  - "Multi-select ChangeNotifier pattern: Set<String> _selectedIds + bool _isSelectionMode + enterSelectionMode/toggleSelection/clearSelection methods"
  - "Batch operation pattern: batchTag collects IDs, calls repo method, clears selection, calls refresh()"

requirements-completed: [TRIA-03]

# Metrics
duration: ~10min
completed: 2026-03-22
---

# Phase 3 Plan 03: Batch Triage Summary

**Long-press multi-select mode with batch tag picker that applies one triage tag to all selected reports via batchSaveTriage, with selection-aware AppBar and PopScope back-button handling**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-22
- **Completed:** 2026-03-22
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 2

## Accomplishments

- Added `enterSelectionMode`, `toggleSelection`, `clearSelection`, and `batchTag` methods to `ReportListController` backed by `Set<String> _selectedIds`
- Wired selection UI in `ReportListScreen`: checkboxes on list items, selection-count AppBar title, select-all action, bottom action bar with "Tag selected" button
- Batch tag picker bottom sheet applies a single chosen tag to all selected reports, then clears selection and refreshes the list
- PopScope intercepts back navigation to clear selection rather than exit the screen
- clearSelection called at the top of `loadReports` to prevent cross-product selection leaks
- End-to-end device verification approved for the full Phase 3 triage workflow (TRIA-01 through TRIA-04)

## Task Commits

Each task was committed atomically:

1. **Task 1: Multi-select state + batch tag UI** - `1d5cf28` (feat)
2. **Task 2: End-to-end device verification** - approved (no code commit — checkpoint only)

## Files Created/Modified

- `lib/application/controllers/report_list_controller.dart` - Added multi-select state fields and methods: `selectedIds`, `isSelectionMode`, `selectedCount`, `enterSelectionMode`, `toggleSelection`, `clearSelection`, `batchTag`; added `clearSelection()` call at the start of `loadReports`
- `lib/presentation/screens/report_list_screen.dart` - Added long-press enter selection, tap-to-toggle, checkboxes on ListTile leading, selection-count AppBar title, close and select-all AppBar actions, bottom action bar, `_showBatchTagPicker` method, and PopScope back-button interception

## Decisions Made

- **clearSelection in loadReports:** Prevents selected IDs from a previous product persisting when the user navigates to a different product's report list — research doc (Pitfall 4) flagged this explicitly.
- **PopScope over WillPopScope:** WillPopScope is deprecated in Flutter 3.x; PopScope with `canPop: !isSelectionMode` and `onPopInvokedWithResult` is the current API.
- **Inline _showBatchTagPicker:** Plan explicitly noted that extracting tag icon/color helpers to a shared utility was out of scope for Phase 3; inline keeps the diff minimal.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None — flutter analyze passed cleanly after Task 1 implementation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 3 (Triage Actions) is fully complete: TRIA-01, TRIA-02, TRIA-03, TRIA-04 all verified on device
- Phase 4 (GitHub Sync) can begin: triage tags are persisted in `bug_report_triage`, duplicate exclusion is in place, and reports tagged as duplicate are visually excluded from the sync action
- The `batchSaveTriage` repository method is stable and ready for any additional bulk operations Phase 4 may require

## Self-Check: PASSED

- FOUND: .planning/phases/03-triage-actions/03-03-SUMMARY.md
- FOUND: lib/application/controllers/report_list_controller.dart
- FOUND: lib/presentation/screens/report_list_screen.dart
- FOUND: commit 1d5cf28

---
*Phase: 03-triage-actions*
*Completed: 2026-03-22*
