# Roadmap: IssueInator

## Overview

IssueInator has a working scaffold — GitHub Device Flow auth, anonymous Supabase connection, clean architecture skeleton — but zero core features. This milestone builds the complete triage workflow: unlock data access via Google Sign-In, read all bug reports, tag and comment on them, then push actionable ones to the right GitHub repo. The dependency chain is strict and non-negotiable: auth unlocks data, data reading enables triage, triage enables safe GitHub sync.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Auth Foundation** - Replace anonymous auth with Google Sign-In so RLS grants bug_reports access
- [x] **Phase 2: Bug Report Read Path** - Dashboard summary, filterable report list, and full detail view with screenshots (completed 2026-03-22)
- [ ] **Phase 3: Triage Actions** - Tag reports, add comments, batch-tag multiple reports
- [ ] **Phase 4: GitHub Sync** - Push "issue"-tagged reports to the correct GitHub repo with dedup protection

## Phase Details

### Phase 1: Auth Foundation
**Goal**: Developer can sign in as the admin identity so Supabase RLS permits reading bug reports
**Depends on**: Nothing (first phase)
**Requirements**: AUTH-01, AUTH-02
**Success Criteria** (what must be TRUE):
  1. Developer can tap "Sign in with Google" and complete the OAuth flow without error
  2. After signing in, the app navigates to the main UI and the admin UUID is the authenticated user
  3. After closing and reopening the app cold, the developer is still signed in — no sign-in prompt appears
  4. The bug_reports table returns rows (not an empty list) after sign-in completes
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md — Firebase/Android config: google-services.json, SHA-1 fingerprint, Gradle plugin wiring
- [x] 01-02-PLAN.md — Dart implementation: add google_sign_in package, replace signInAnonymously() with signInWithGoogle(), update AuthScreen button, device verification

### Phase 2: Bug Report Read Path
**Goal**: Developer can see all bug reports across products with enough context to decide what to triage
**Depends on**: Phase 1
**Requirements**: DASH-01, DASH-02, DASH-03, LIST-01, LIST-02, LIST-03, LIST-04, DETL-01, DETL-02, DETL-03
**Success Criteria** (what must be TRUE):
  1. Home screen shows a count of total and unprocessed reports for each TinkerPlex product
  2. Tapping a product opens a scrollable list of its reports showing description preview, platform, date, and triage status
  3. The report list loads without noticeable lag (screenshot_base64 is not fetched in list queries)
  4. Developer can pull-to-refresh the list to see newly submitted reports
  5. Tapping a report opens full detail including logs, device info, and an inline zoomable screenshot
**Plans**: 3 plans

Plans:
- [x] 02-01-PLAN.md — Domain models, BugReportRepository, controllers, and DI registration
- [x] 02-02-PLAN.md — Dashboard HomeScreen rewrite with product counts + ReportListScreen with pull-to-refresh
- [x] 02-03-PLAN.md — ReportDetailScreen with zoomable screenshot + end-to-end device verification

### Phase 3: Triage Actions
**Goal**: Developer can categorize and annotate every report so nothing is left unprocessed
**Depends on**: Phase 2
**Requirements**: TRIA-01, TRIA-02, TRIA-03, TRIA-04
**Success Criteria** (what must be TRUE):
  1. Developer can apply exactly one triage tag (issue / feedback / duplicate / not-a-bug / needs-info) to a report and it persists after app restart
  2. Developer can add a text comment to a report and it appears on subsequent visits to that report
  3. Developer can select multiple reports and apply a tag to all of them in one action
  4. Reports tagged "duplicate" are visually excluded from the GitHub sync action (no sync button shown or it is disabled)
**Plans**: 3 plans

Plans:
- [x] 03-01-PLAN.md — Supabase migration (bug_report_triage table + RLS), TriageTag enum, BugReportTriage model, repository CRUD, TriageController, DI registration, updated unprocessed count
- [ ] 03-02-PLAN.md — Triage UI: tag picker and comment field on ReportDetailScreen
- [ ] 03-03-PLAN.md — Bulk triage: multi-select on report list + batch apply tag

### Phase 4: GitHub Sync
**Goal**: Developer can push "issue"-tagged reports to the correct GitHub repo without creating duplicates
**Depends on**: Phase 3
**Requirements**: SYNC-01, SYNC-02, SYNC-03, SYNC-04, SYNC-05
**Success Criteria** (what must be TRUE):
  1. Tapping sync on an "issue"-tagged report creates a GitHub issue in the repo matching that report's source_app
  2. The created GitHub issue body contains the report description, device info, platform, app version, and an embedded screenshot URL
  3. Syncing the same report a second time does not create a duplicate GitHub issue — the existing one is detected and linked instead
  4. After a successful sync, the report's github_issue_url is visible in the report detail and in the list item
  5. A 401 from the GitHub API prompts the developer to re-authenticate via Device Flow rather than silently failing
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Auth Foundation | 2/2 | Complete | 2026-03-22 |
| 2. Bug Report Read Path | 3/3 | Complete   | 2026-03-22 |
| 3. Triage Actions | 1/3 | In progress | - |
| 4. GitHub Sync | 0/? | Not started | - |
