# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-21)

**Core value:** Every bug report gets triaged — tagged, commented, and either synced to the right GitHub repo or dismissed with reason
**Current focus:** Phase 4 — GitHub Sync

## Current Position

Phase: 4 of 4 (GitHub Sync) — In Progress
Plan: 3 of 3 in current phase (04-02 complete, device verification APPROVED; ready for 04-03)
Status: Phase 4 Plan 2 complete and verified — moving to 04-03 (final plan)
Last activity: 2026-03-22 — 04-02 device verification approved by user; sync button, dedup, re-auth, list badge all confirmed working on device

Progress: [█████████░] ~85% (11 plans complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 6
- Average duration: ~28 min
- Total execution time: ~72 min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-auth-foundation | 2 | ~70 min | ~35 min |
| 02-bug-report-read-path | 3 | ~48 min | ~16 min |
| 03-triage-actions | 3 | ~14 min | ~5 min |

**Recent Trend:**
- Last 5 plans: 02-03 (~45 min), 03-01 (~2 min), 03-02 (~2 min), 03-03 (~10 min)
- Trend: fast execution on well-defined UI tasks

*Updated after each plan completion*
| Phase 04-github-sync P01 | 2 | 2 tasks | 6 files |
| Phase 04-github-sync P02 | 1 | 1 task | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-work]: Google SSO required before any data feature — RLS silently blocks anonymous sessions
- [Pre-work]: Column projection mandatory in list queries — screenshot_base64 must never be fetched in list
- [Pre-work]: Fingerprint-based dedup required for GitHub sync before writing any sync code
- [Pre-work]: Prefer bug_report_triage side table over adding columns to bug_reports (shared schema safety)
- [01-01]: Defer google_play_services_version meta-data to plan 02 — adding @integer/google_play_services_version before play-services-auth library is on classpath causes AAPT resource link failure
- [01-01]: Google Services plugin pattern: buildscript classpath in root build.gradle.kts, id() apply in app/build.gradle.kts — matches puzzlenook reference exactly
- [01-02]: Use upload keystore for debug builds — Google Sign-In silently fails when APK SHA-1 doesn't match Firebase-registered fingerprint; default debug keystore SHA-1 was not registered
- [01-02]: key.properties at android/ loaded in build.gradle.kts with graceful fallback; both debug and release build types use upload signingConfig when key.properties is present
- [02-01]: Column projection strictly enforced — select('*') only in getReportDetail; list query uses explicit column string omitting screenshot_base64
- [02-01]: Unprocessed proxy for Phase 2 is github_issue_url IS NULL; comment placed in repository to replace with triage_tag in Phase 3
- [02-02]: HomeScreen loads product names with select('name') then delegates to DashboardController.loadCounts() — screen owns name discovery, controller owns count logic
- [02-02]: ReportDetailScreen navigation stubbed as SnackBar in 02-02; TODO(02-03) comment marks exact wiring point in report_list_screen.dart
- [02-03]: Screenshot fetch split from metadata fetch — on-demand load + compute() decode on background isolate avoids jank on large images
- [02-03]: Log truncation to last 512KB — prevents UI freeze on multi-MB log payloads; expand button reveals full content
- [02-03]: Admin UUID updated to tinkertestautomation@gmail.com to match Supabase RLS policy
- [03-01]: Unprocessed count changed from github_issue_url IS NULL proxy to triage_tag set-difference (fetch all triaged IDs once, intersect per product)
- [03-01]: getReportsByProduct uses Future.wait parallel fetch with in-memory join — no N+1 queries
- [03-01]: saveTriage uses conditional spread so partial updates (tag-only or comment-only) work without overwriting existing values
- [03-02]: Capture ScaffoldMessenger before async gaps — lint requires context not used after await; store ref in local var before first await
- [03-02]: Detail screen fetches triage sequentially after detail load in single _fetchDetail — simpler lifecycle, no separate triggers
- [03-02]: List refresh uses Navigator.push(...).then((_) => controller.refresh()) — avoids BuildContext async gap, integrates with existing controller.refresh()
- [Phase 03-triage-actions]: clearSelection called at start of loadReports to prevent cross-product selection leaks
- [Phase 03-triage-actions]: PopScope(canPop: !isSelectionMode) replaces deprecated WillPopScope for back-button selection clear
- [Phase 04-github-sync]: GraphQL search used for dedup (not REST /search/issues) — REST returns 422 for private repos
- [Phase 04-github-sync]: html_url from REST issue create response (not url) — url is API URL, html_url is web URL
- [Phase 04-github-sync]: Screenshot upload is non-fatal — sync proceeds without screenshot if upload fails
- [Phase 04-github-sync]: 401 on any GitHub API call triggers revokeToken() + requiresReAuth: true
- [04-02]: Capture Navigator.of(context) before await for Device Flow sheet — avoids use_build_context_synchronously lint error; use navigator.context to open modal after async gap

### Pending Todos

None yet.

### Blockers/Concerns

- ~~[Phase 1]: google-services.json and OAuth client ID setup for com.tinkerplexlabs.issueinator needs verification before Phase 1 plan executes~~ RESOLVED in 01-01
- [Phase 2]: Schema decision (columns vs. side table) must be finalized before any write migration is run
- [Phase 4]: GitHub Search API indexing speed for fingerprint dedup — validate during Phase 4 planning

## Session Continuity

Last session: 2026-03-22
Stopped at: Completed 04-02-PLAN.md — Sync UI verified on device; ready for 04-03
Resume file: None
