---
phase: 02-bug-report-read-path
plan: 01
subsystem: api
tags: [supabase, flutter, getit, provider, changenotifier, column-projection]

# Dependency graph
requires:
  - phase: 01-auth-foundation
    provides: Supabase admin RLS session, SupabaseConfig.client, AuthController pattern

provides:
  - BugReportSummary domain model (column-projected, no screenshot)
  - BugReportDetail domain model (full record including screenshotBase64)
  - ProductReportCount domain model (total + unprocessed counts)
  - BugReportRepository with getProductCounts, getReportsByProduct, getReportDetail
  - DashboardController (ChangeNotifier, loading/error/data state)
  - ReportListController (ChangeNotifier, loading/error/data state, refresh for pull-to-refresh)
  - GetIt registrations for all new types

affects: [02-02, 02-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Column projection for Supabase list queries (never select('*') on bug_reports lists)
    - CountOption.exact for per-product total and unprocessed counts
    - ChangeNotifier controller pattern with loading/error/data state (matches AuthController)
    - Constructor injection via GetIt for repository-to-controller wiring

key-files:
  created:
    - lib/domain/models/bug_report_summary.dart
    - lib/domain/models/bug_report_detail.dart
    - lib/domain/models/product_report_count.dart
    - lib/infrastructure/repositories/bug_report_repository.dart
    - lib/application/controllers/dashboard_controller.dart
    - lib/application/controllers/report_list_controller.dart
  modified:
    - lib/config/dependencies.dart

key-decisions:
  - "Column projection enforced: getReportsByProduct uses explicit column list omitting screenshot_base64 (166-350 KB per row); select('*') only in getReportDetail"
  - "Unprocessed proxy: github_issue_url IS NULL used as Phase 2 proxy for unprocessed status; comment placed to replace with triage_tag in Phase 3"

patterns-established:
  - "Column projection pattern: always pass explicit comma-separated columns to .select() for bug_reports list queries"
  - "ChangeNotifier controller pattern: _isLoading/_error/_data fields, notifyListeners at start and in finally block"
  - "Repository-first DI: register BugReportRepository before controllers that depend on it in configureDependencies()"

requirements-completed: [DASH-01, DASH-03, LIST-01, LIST-03, LIST-04]

# Metrics
duration: 2min
completed: 2026-03-22
---

# Phase 2 Plan 01: Bug Report Read Path — Data Layer Summary

**Supabase data layer with column-projected list query, CountOption.exact dashboard counts, and ChangeNotifier controllers wired via GetIt — UI plans can bind directly to controllers**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-22T18:40:42Z
- **Completed:** 2026-03-22T18:42:19Z
- **Tasks:** 3
- **Files modified:** 7 (6 created, 1 updated)

## Accomplishments

- Three domain models (BugReportSummary, BugReportDetail, ProductReportCount) with fromJson factories
- BugReportRepository enforcing column projection on list queries and CountOption.exact for dashboard counts
- DashboardController and ReportListController extending ChangeNotifier with full loading/error/data state lifecycle
- All types registered in GetIt with correct dependency order (repository before controllers)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create domain models and BugReportRepository** - `a30a390` (feat)
2. **Task 2: Create DashboardController and ReportListController** - `bdf24b4` (feat)
3. **Task 3: Register new types in GetIt** - `24c378d` (chore)

**Plan metadata:** _(docs commit follows)_

## Files Created/Modified

- `lib/domain/models/bug_report_summary.dart` - List projection model with descriptionPreview getter (120 char truncation)
- `lib/domain/models/bug_report_detail.dart` - Full detail model including screenshotBase64, deviceInfo, logs, userId
- `lib/domain/models/product_report_count.dart` - Per-product counts with processedCount computed getter
- `lib/infrastructure/repositories/bug_report_repository.dart` - Three Supabase queries: getProductCounts (CountOption.exact x2 per product), getReportsByProduct (column projection), getReportDetail (select *)
- `lib/application/controllers/dashboard_controller.dart` - ChangeNotifier loading product counts
- `lib/application/controllers/report_list_controller.dart` - ChangeNotifier loading report list with refresh() for pull-to-refresh
- `lib/config/dependencies.dart` - Added BugReportRepository, DashboardController, ReportListController registrations

## Decisions Made

- Column projection is strictly enforced: `select('*')` appears exactly once in the repository, in `getReportDetail`. All list and count queries use explicit column lists or `select('id')` only.
- "Unprocessed" definition for Phase 2: `github_issue_url IS NULL`. A comment marks the Phase 3 replacement point (`triage_tag IS NULL`).

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- All controllers and repository registered and ready for UI binding
- Plan 02-02 (dashboard screen) and 02-03 (report list/detail screens) can resolve DashboardController and ReportListController directly from GetIt
- No blockers for UI plans

## Self-Check: PASSED

All 7 files exist on disk. All 3 task commits verified (a30a390, bdf24b4, 24c378d).
