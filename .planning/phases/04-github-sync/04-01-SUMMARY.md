---
phase: 04-github-sync
plan: 01
subsystem: github-sync-backend
tags: [github, sync, sealed-class, graphql, supabase-storage, di]
dependency_graph:
  requires: [GitHubAuthService, BugReportRepository, SupabaseConfig]
  provides: [GitHubSyncService, SyncController, SyncResult, updateGithubIssueUrl]
  affects: [lib/config/dependencies.dart, lib/infrastructure/repositories/bug_report_repository.dart]
tech_stack:
  added: []
  patterns: [sealed-class, repository-write-back, changenotifier-guard, graphql-search, supabase-storage-uploadbinary]
key_files:
  created:
    - lib/domain/models/sync_result.dart
    - lib/domain/services/github_sync_service.dart
    - lib/infrastructure/services/github_sync_service_impl.dart
    - lib/application/controllers/sync_controller.dart
  modified:
    - lib/infrastructure/repositories/bug_report_repository.dart
    - lib/config/dependencies.dart
decisions:
  - "GraphQL search used for dedup (not REST /search/issues) — REST returns 422 for private repos"
  - "html_url from REST issue create response (not url) — url is the API URL, html_url is the web URL"
  - "Screenshot upload is non-fatal — sync proceeds without screenshot if upload fails"
  - "compute(base64Decode, ...) used for screenshot decode — prevents UI jank on large images"
  - "401 on any GitHub API call triggers revokeToken() + requiresReAuth: true in SyncError"
metrics:
  duration: "~2 min"
  completed: 2026-03-22
  tasks_completed: 2
  files_changed: 6
---

# Phase 4 Plan 1: GitHub Sync Backend Summary

**One-liner:** SHA-256 content hash dedup via GraphQL, Supabase Storage screenshot upload, GitHub REST issue creation, and SyncController with double-tap guard — all wired in GetIt.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | SyncResult model + GitHubSyncService abstract + impl | d8af08c | sync_result.dart, github_sync_service.dart, github_sync_service_impl.dart |
| 2 | BugReportRepository write-back + SyncController + DI | 6a61f3d | bug_report_repository.dart, sync_controller.dart, dependencies.dart |

## What Was Built

### SyncResult sealed class (`lib/domain/models/sync_result.dart`)
Three variants covering all sync outcomes:
- `SyncSuccess(String issueUrl)` — new issue created
- `SyncDuplicate(String existingUrl)` — hash matched existing issue, URL written back
- `SyncError(String message, {bool requiresReAuth})` — failure, with optional re-auth trigger

### GitHubSyncService abstract + GitHubAuthException (`lib/domain/services/github_sync_service.dart`)
Abstract service with `syncReport(reportId, detail)` and `repoForApp(sourceApp)`. `GitHubAuthException` defined here as a simple Exception subclass used to signal 401 responses.

### GitHubSyncServiceImpl (`lib/infrastructure/services/github_sync_service_impl.dart`)
Concrete implementation executing the 7-step sync flow:
1. Get stored OAuth token via `GitHubAuthService.getStoredToken()`
2. Route to GitHub repo via hardcoded `_repoMap` (`freecell`, `puzzle_nook`)
3. Compute SHA-256 content hash (first 12 hex chars) — matches CLI tool algorithm exactly
4. GraphQL dedup search via `POST https://api.github.com/graphql`
5. Fetch + upload screenshot to `bug-screenshots` Supabase bucket (non-fatal)
6. Build issue body (metadata table, `<!-- hash:... -->` comment, description, screenshot, logs)
7. Create GitHub issue via REST + DB write-back via `updateGithubIssueUrl`

Private helpers: `_contentHash`, `_findExistingIssue`, `_uploadScreenshot`, `_createGitHubIssue`, `_issueTitle`, `_issueBody`.

### BugReportRepository.updateGithubIssueUrl (`lib/infrastructure/repositories/bug_report_repository.dart`)
Single new method: PATCH `bug_reports.github_issue_url` for the given `reportId`. Used by both dedup path (write existing URL) and new issue path (write new URL).

### SyncController (`lib/application/controllers/sync_controller.dart`)
ChangeNotifier with:
- `isSyncing` bool guard preventing double-tap (returns `SyncError('Already syncing')` immediately)
- `lastResult` state for UI to react to sync outcome
- `clearResult()` for dismissing result state
- `sync(reportId, detail)` method delegating to `GitHubSyncService`

### GetIt registrations (`lib/config/dependencies.dart`)
`GitHubSyncService` (impl) registered before `SyncController` — correct dependency order.

## Verification Results

All 10 plan verification checks passed:
1. `flutter analyze`: No issues found
2. SyncResult: three sealed variants confirmed
3. `_repoMap`: freecell + puzzle_nook entries present
4. `_contentHash`: sha256 + substring(0, 12)
5. `_findExistingIssue`: GraphQL POST to api.github.com/graphql
6. `_uploadScreenshot`: `uploadBinary` on `bug-screenshots` bucket
7. `_createGitHubIssue`: returns `html_url`
8. SyncController: `_isSyncing` guard at entry + finally block
9. `updateGithubIssueUrl`: `.update({'github_issue_url': url}).eq('id', reportId)`
10. DI: GitHubSyncService registered before SyncController

## Deviations from Plan

**Auto-fixed: unnecessary `dart:typed_data` import**
- Found during: Task 1 (flutter analyze)
- Issue: `dart:typed_data` was imported but `Uint8List` is already provided by `package:flutter/foundation.dart`
- Fix: Removed the redundant import
- Files modified: `lib/infrastructure/services/github_sync_service_impl.dart`
- Commit: d8af08c (fixed before commit)

No architectural deviations — plan executed as specified.

## Self-Check: PASSED

All 5 created files confirmed on disk. Both task commits (d8af08c, 6a61f3d) confirmed in git log.
