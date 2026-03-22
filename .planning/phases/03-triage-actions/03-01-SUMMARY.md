---
phase: 03-triage-actions
plan: 01
subsystem: database
tags: [supabase, dart, flutter, triage, repository-pattern, getit]

requires:
  - phase: 02-bug-report-read-path
    provides: BugReportRepository, BugReportSummary, DI setup, Supabase auth

provides:
  - TriageTag enum (5 values: issue, feedback, duplicate, not-a-bug, needs-info)
  - BugReportTriage model with fromJson factory
  - BugReportRepository.saveTriage (upsert with conditional field spread)
  - BugReportRepository.getTriageForReport
  - BugReportRepository.batchSaveTriage
  - BugReportRepository.getProductCounts using triage_tag set-difference (replaces github_issue_url proxy)
  - BugReportRepository.getReportsByProduct with parallel triage enrichment
  - TriageController (applyTag, saveComment, getTriage)
  - bug_report_triage Supabase table with RLS (admin-only: a672276e UUID)

affects:
  - 03-02 (triage UI builds on TriageController and TriageTag)
  - 03-03 (bulk triage uses batchSaveTriage)
  - dashboard counts now reflect actual triage state

tech-stack:
  added: []
  patterns:
    - Parallel Future.wait fetch with set-difference for unprocessed count
    - Triage side table enrichment via copyWith on immutable model
    - Conditional map spread (if (x != null) 'key': x) in upsert payloads

key-files:
  created:
    - lib/domain/models/bug_report_triage.dart
    - lib/application/controllers/triage_controller.dart
  modified:
    - lib/domain/models/bug_report_summary.dart
    - lib/infrastructure/repositories/bug_report_repository.dart
    - lib/config/dependencies.dart

key-decisions:
  - "Unprocessed count changed from github_issue_url IS NULL proxy to triage_tag set-difference: fetch all triaged IDs once, then intersect per product"
  - "getReportsByProduct uses Future.wait parallel fetch (bug_reports + bug_report_triage) with in-memory join — avoids N+1 and keeps screenshot exclusion intact"
  - "saveTriage uses conditional spread pattern so partial updates (tag-only or comment-only) are supported without overwriting existing values"

patterns-established:
  - "Parallel Future.wait + set-difference for cross-table unprocessed count"
  - "copyWith on immutable domain models for side-table enrichment"
  - "TriageController: thin ChangeNotifier wrapping repository, isSaving+error state, returns bool success"

requirements-completed: [TRIA-01, TRIA-02]

duration: 2min
completed: 2026-03-22
---

# Phase 03 Plan 01: Triage Data Layer Summary

**TriageTag enum, BugReportTriage model, repository CRUD (saveTriage/getTriageForReport/batchSaveTriage), parallel triage enrichment in getReportsByProduct, set-difference unprocessed count, and TriageController registered in GetIt**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-22T21:18:24Z
- **Completed:** 2026-03-22T21:20:39Z
- **Tasks:** 2 (Task 1 via MCP, Task 2 code implementation)
- **Files modified:** 5

## Accomplishments

- Triage data layer complete: domain model, three repository methods, controller, and DI wiring
- Dashboard unprocessed counts now reflect actual triage state (triage_tag presence) instead of github_issue_url proxy
- getReportsByProduct enriches summaries with triage data via parallel fetch — no extra round trips in UI

## Task Commits

1. **Task 1: Create bug_report_triage table** — completed via MCP (no code commit)
2. **Task 2: Triage data layer** - `70a6ca9` (feat)

## Files Created/Modified

- `lib/domain/models/bug_report_triage.dart` — TriageTag enum (5 values) and BugReportTriage model
- `lib/domain/models/bug_report_summary.dart` — Added optional triageTag field and copyWith method
- `lib/infrastructure/repositories/bug_report_repository.dart` — saveTriage, getTriageForReport, batchSaveTriage; updated getProductCounts and getReportsByProduct
- `lib/application/controllers/triage_controller.dart` — ChangeNotifier wrapping triage repository writes
- `lib/config/dependencies.dart` — TriageController registered as GetIt singleton

## Decisions Made

- Unprocessed count now uses triage_tag set-difference: fetch all triaged IDs once (full bug_report_triage table scan — expected tiny), intersect with per-product report IDs. Removed github_issue_url proxy entirely.
- getReportsByProduct uses Future.wait to fetch bug_reports and bug_report_triage in parallel, builds a Map<String, String?> for O(1) lookup, then applies copyWith. Keeps screenshot exclusion and ordering intact.
- saveTriage uses Dart conditional spread (`if (x != null) 'key': x`) so callers can update tag-only or comment-only without needing to know or preserve the other field.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

Task 1 (Supabase migration) was completed by the human operator via MCP tool before this continuation agent was spawned. The bug_report_triage table with RLS policy (admin UUID a672276e-b2bd-403e-912c-040251c1063f) was confirmed to exist.

## Next Phase Readiness

- Plans 03-02 and 03-03 can build triage UI directly on top of TriageController and TriageTag enum
- batchSaveTriage is ready for bulk-tag workflows in 03-03
- getProductCounts and getReportsByProduct are enriched — dashboard and list screens will reflect triage state without any additional data layer work

## Self-Check: PASSED

All created files verified on disk. Commit 70a6ca9 confirmed in git log.

---
*Phase: 03-triage-actions*
*Completed: 2026-03-22*
