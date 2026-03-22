---
phase: 02-bug-report-read-path
plan: 02
subsystem: ui
tags: [flutter, getit, changenotifier, dashboard, listview, pull-to-refresh, material3]

# Dependency graph
requires:
  - phase: 02-01
    provides: DashboardController, ReportListController, BugReportRepository, BugReportSummary, ProductReportCount

provides:
  - HomeScreen rewritten as product dashboard with per-product total/unprocessed count cards
  - ReportListScreen with scrollable pull-to-refresh report list per product
  - Navigation from HomeScreen card tap to filtered ReportListScreen

affects: [02-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - ListenableBuilder wrapping GetIt-resolved ChangeNotifier for reactive screen state
    - Three-state UI pattern: loading/error+retry/data for both screens
    - RefreshIndicator wrapping ListView.builder for pull-to-refresh

key-files:
  created:
    - lib/presentation/screens/report_list_screen.dart
  modified:
    - lib/presentation/screens/home_screen.dart

key-decisions:
  - "HomeScreen loads product names from Supabase then delegates count queries to DashboardController — product list query uses select('name') (column projection), counts computed in DashboardController via repository"
  - "ReportDetailScreen navigation stubbed as SnackBar for plan 02-02; TODO(02-03) comment marks wiring point for plan 02-03 to replace"

patterns-established:
  - "Dashboard card pattern: Card + InkWell with borderRadius for tappable product cards"
  - "Triage status proxy: githubIssueUrl != null = Synced (green), null = Unprocessed (grey) — comment to replace with triage_tag in Phase 3"
  - "Three-state UI: isLoading && reports.isEmpty => loading spinner; error != null => error+retry; else => data list"

requirements-completed: [DASH-01, DASH-02, DASH-03, LIST-01, LIST-02, LIST-03, LIST-04]

# Metrics
duration: 1min
completed: 2026-03-22
---

# Phase 2 Plan 02: Bug Report Read Path — Dashboard and Report List Screens

**HomeScreen dashboard with per-product total/unprocessed count cards and ReportListScreen with pull-to-refresh ListView bound to ChangeNotifier controllers via GetIt**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-03-22T18:44:53Z
- **Completed:** 2026-03-22T18:46:01Z
- **Tasks:** 2
- **Files modified:** 2 (1 rewritten, 1 created)

## Accomplishments

- HomeScreen rewritten to show DashboardController-driven product cards with total and unprocessed counts; tapping navigates to ReportListScreen
- ReportListScreen created with three-state body (loading, error+retry, data), RefreshIndicator calling controller.refresh(), and per-item description preview, platform chip, date, and triage status
- GitHub integration section and logout AppBar preserved exactly; debug UID/columns text removed

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite HomeScreen as product dashboard** - `27f3312` (feat)
2. **Task 2: Create ReportListScreen with pull-to-refresh** - `d4101bc` (feat)

**Plan metadata:** _(docs commit follows)_

## Files Created/Modified

- `lib/presentation/screens/home_screen.dart` - Rewritten: product count cards from DashboardController, Navigator.push to ReportListScreen on tap, error+retry state
- `lib/presentation/screens/report_list_screen.dart` - New: productName constructor param, loadReports on initState, RefreshIndicator + ListView.builder, ListTile with descriptionPreview/platform/date/triage, empty state

## Decisions Made

- HomeScreen fetches product names with `select('name')` (column projection) then calls `DashboardController.loadCounts()` — keeps screen responsible only for product name discovery while controller owns count logic
- ReportDetailScreen navigation is stubbed as a SnackBar with a clear `TODO(02-03)` comment; commented-out Navigator.push code shows the intended wiring for plan 02-03

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- HomeScreen and ReportListScreen fully wired to controllers, ready for plan 02-03 to add ReportDetailScreen
- TODO(02-03) comment in report_list_screen.dart marks exact navigation wiring point
- `flutter analyze` passes with zero issues across entire app

## Self-Check: PASSED

Both files confirmed on disk. Task commits 27f3312 and d4101bc verified in git log.
