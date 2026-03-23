---
phase: 04-github-sync
verified: 2026-03-22T00:00:00Z
status: human_needed
score: 15/15 must-haves verified
re_verification: false
human_verification:
  - test: "Tap 'Sync to GitHub' on an issue-tagged report on device"
    expected: "Button shows spinner while syncing, SnackBar shows 'GitHub issue created' with View action, detail refreshes to show 'View GitHub Issue' chip"
    why_human: "Real HTTP call to api.github.com — cannot verify issue creation without live GitHub credentials and a real report"
  - test: "Tap 'Sync to GitHub' on the same report a second time"
    expected: "SnackBar shows 'Existing GitHub issue linked' — no new issue created on GitHub"
    why_human: "Dedup path requires real GraphQL search against GitHub; cannot mock hash-match programmatically"
  - test: "Open the created GitHub issue in a browser"
    expected: "Issue body contains metadata table, description, screenshot image (if report had one), logs in collapsible <details>, and HTML comment <!-- hash:XXXXXXXXXXXX -->"
    why_human: "Body format correctness requires visual inspection of the rendered GitHub issue"
  - test: "Revoke the GitHub token in GitHub settings, then tap sync"
    expected: "App shows 'GitHub token expired — please re-authenticate' SnackBar and opens Device Flow bottom sheet"
    why_human: "401 re-auth path requires an actually expired/revoked token to trigger"
  - test: "Verify sync button is absent for duplicate/feedback/not-a-bug/needs-info tagged reports"
    expected: "Only issue-tagged reports show the sync button; other tags show 'Not synced to GitHub' text"
    why_human: "UI conditional rendering is correct in code but the complete visual flow needs device confirmation"
---

# Phase 4: GitHub Sync Verification Report

**Phase Goal:** Developer can push "issue"-tagged reports to the correct GitHub repo without creating duplicates
**Verified:** 2026-03-22
**Status:** human_needed — all automated checks pass, 5 items require device/live-API verification
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SyncResult sealed class models three outcomes: success, duplicate, error (with requiresReAuth flag) | VERIFIED | `sync_result.dart` declares `sealed class SyncResult` with `SyncSuccess(issueUrl)`, `SyncDuplicate(existingUrl)`, `SyncError(message, {requiresReAuth=false})` — exact variants specified |
| 2 | GitHubSyncService.syncReport orchestrates full flow: hash → dedup search → screenshot upload → issue create → DB write-back | VERIFIED | `github_sync_service_impl.dart` lines 32–96 implement all 7 ordered steps with correct early-return paths |
| 3 | Content hash uses SHA-256 of description+deviceInfo+platform+appVersion, first 12 hex chars, matching CLI tool algorithm | VERIFIED | `_contentHash` method: `sha256.convert(utf8.encode('$description\n$deviceInfo\n$platform\n$appVersion')).toString().substring(0, 12)` |
| 4 | GraphQL search (not REST) used for dedup on private repos | VERIFIED | `_findExistingIssue` POSTs to `https://api.github.com/graphql` with `search(query: "hash:$hash in:body repo:$repo", type: ISSUE, first: 1)` |
| 5 | Screenshot uploaded to bug-screenshots bucket via Supabase Dart SDK uploadBinary | VERIFIED | `_uploadScreenshot` calls `SupabaseConfig.client.storage.from('bug-screenshots').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: 'image/png', upsert: true))` |
| 6 | Source app routed to correct repo via hardcoded map (freecell → tinkerplexlabs/freecell, puzzle_nook → tinkerplexlabs/puzzlenook) | VERIFIED | `static const Map<String, String> _repoMap = {'freecell': 'tinkerplexlabs/freecell', 'puzzle_nook': 'tinkerplexlabs/puzzlenook'}` |
| 7 | 401 from any GitHub API call throws GitHubAuthException, triggering re-auth flow | VERIFIED | Both `_findExistingIssue` (line 149) and `_createGitHubIssue` (line 214) check `statusCode == 401` and throw `GitHubAuthException()`; both catch sites call `_githubAuthService.revokeToken()` and return `SyncError(..., requiresReAuth: true)` |
| 8 | SyncController prevents double-tap via isSyncing guard | VERIFIED | `sync_controller.dart` line 25: `if (_isSyncing) return const SyncError('Already syncing');`; `_isSyncing` set in `finally` block ensures reset even on exception |
| 9 | Sync button appears on detail screen only when triage_tag is 'issue' | VERIFIED | `report_detail_screen.dart` lines 354–387: `if (isDuplicate) ... else if (detail.githubIssueUrl != null) ... else if (currentTag == TriageTag.issue)` — sync button only in the `issue` branch |
| 10 | Tapping sync creates a GitHub issue and shows success feedback with the issue URL | VERIFIED (logic) | `_syncReport` switches on `SyncSuccess` → SnackBar "GitHub issue created" + `_fetchDetail()` refresh; requires live API for full end-to-end |
| 11 | Syncing the same report twice detects the duplicate and links it without creating a new issue | VERIFIED (logic) | `_findExistingIssue` returns existing URL → `updateGithubIssueUrl` → `SyncDuplicate`; `_syncReport` handles `SyncDuplicate` with SnackBar "Existing GitHub issue linked"; requires live API |
| 12 | After sync, github_issue_url is visible on detail screen as a clickable 'View GitHub Issue' chip | VERIFIED | `_buildStatusBar` shows `ActionChip` with "View GitHub Issue" when `detail.githubIssueUrl != null`; `_fetchDetail()` called after sync refreshes this |
| 13 | Report list items show a GitHub icon badge when github_issue_url is present | VERIFIED | `report_list_screen.dart` lines 299–306: `if (report.githubIssueUrl != null) ... Icon(Icons.link, size: 14, color: Colors.green)` in trailing Row |
| 14 | A 401 from GitHub prompts re-auth via Device Flow dialog instead of silently failing | VERIFIED (logic) | `_syncReport` on `SyncError(requiresReAuth: true)`: SnackBar + `showModalBottomSheet(builder: (_) => const GitHubDeviceFlowSheet())`; navigator captured before await (async-safe) |
| 15 | Sync button is disabled while sync is in progress (prevents double-tap) | VERIFIED | `ListenableBuilder` on `_syncController`; `onPressed: isSyncing ? null : () => _syncReport(context)` + spinner replaces icon while syncing |

**Score:** 15/15 truths verified (5 require live-device confirmation)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/domain/models/sync_result.dart` | SyncResult sealed class with SyncSuccess, SyncDuplicate, SyncError | VERIFIED | 24 lines, all three sealed variants with correct fields |
| `lib/domain/services/github_sync_service.dart` | Abstract GitHubSyncService + GitHubAuthException | VERIFIED | Abstract class with `syncReport` and `repoForApp`; `GitHubAuthException` defined here |
| `lib/infrastructure/services/github_sync_service_impl.dart` | Concrete implementation with hash, GraphQL dedup, screenshot upload, REST issue create, DB write-back | VERIFIED | 302 lines, all 7 sync steps + 5 private helpers; substantive implementation, no stubs |
| `lib/application/controllers/sync_controller.dart` | ChangeNotifier with isSyncing guard and lastResult state | VERIFIED | 46 lines, `_isSyncing` guard, `clearResult()`, `finally` block for reset |
| `lib/infrastructure/repositories/bug_report_repository.dart` | updateGithubIssueUrl method for write-back | VERIFIED | Lines 159–165: `.update({'github_issue_url': url}).eq('id', reportId)` |
| `lib/config/dependencies.dart` | GetIt registrations for GitHubSyncService and SyncController | VERIFIED | Lines 44–55: `GitHubSyncService` registered before `SyncController`, correct dependency order |
| `lib/presentation/screens/report_detail_screen.dart` | Sync button, 401 re-auth dialog trigger, post-sync detail refresh | VERIFIED | Imports SyncController, SyncResult; ListenableBuilder wraps sync button; `_syncReport` handles all three sealed variants |
| `lib/presentation/screens/report_list_screen.dart` | GitHub icon badge on synced list items | VERIFIED | Lines 299–306: green link icon when `githubIssueUrl != null` in trailing Row |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `github_sync_service_impl.dart` | `GitHubAuthService` | `getStoredToken()` | WIRED | Line 34: `_githubAuthService.getStoredToken()` + `revokeToken()` on 401 |
| `github_sync_service_impl.dart` | `BugReportRepository` | `getReportScreenshot + updateGithubIssueUrl` | WIRED | Lines 66, 57, 90: both methods called on `_repository` in sync flow |
| `sync_controller.dart` | `GitHubSyncService` | `syncReport call` | WIRED | Line 32: `await _syncService.syncReport(reportId, detail)` |
| `report_detail_screen.dart` | `SyncController` | `syncController.sync(reportId, detail)` | WIRED | Line 123: `await _syncController.sync(widget.reportId, _detail!)` |
| `report_detail_screen.dart` | `GitHubDeviceFlowSheet` | `showModalBottomSheet` on 401 re-auth | WIRED | Lines 155–160: `showModalBottomSheet(..., builder: (_) => const GitHubDeviceFlowSheet())` — uses `navigator.context` for async safety |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SYNC-01 | 04-01, 04-02 | Developer can sync "issue"-tagged reports to the correct GitHub repo based on source_app | SATISFIED | `_repoMap` routes by `detail.sourceApp`; sync button only on `TriageTag.issue` reports |
| SYNC-02 | 04-01, 04-02 | Sync uses content hash dedup (hash embedded in issue body as HTML comment) to prevent duplicate GitHub issues | SATISFIED | SHA-256 hash embedded as `<!-- hash:XXXXXXXXXXXX -->` in `_issueBody`; GraphQL search finds existing by hash |
| SYNC-03 | 04-01, 04-02 | After creating a GitHub issue, github_issue_url is written back to Supabase | SATISFIED | `updateGithubIssueUrl` called on both success (line 90) and duplicate (line 57) paths |
| SYNC-04 | 04-01, 04-02 | Sync uploads screenshot to Supabase Storage and embeds public URL in GitHub issue body | SATISFIED | `_uploadScreenshot` uploads to `bug-screenshots` bucket; public URL passed to `_issueBody` as `screenshotUrl`; non-fatal on failure |
| SYNC-05 | 04-01, 04-02 | Sync routes to correct repo per product (e.g., freecell → tinkerplexlabs/freecell) | SATISFIED | `_repoMap = {'freecell': 'tinkerplexlabs/freecell', 'puzzle_nook': 'tinkerplexlabs/puzzlenook'}` |

All 5 SYNC requirements satisfied. No orphaned requirements — REQUIREMENTS.md traceability table maps SYNC-01 through SYNC-05 to Phase 4 and marks all Complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | — |

No TODO/FIXME/placeholder comments found in phase 4 files. No empty implementations. No stub handlers. `flutter analyze` passes with zero issues.

### Human Verification Required

#### 1. End-to-end sync — new issue creation

**Test:** Sign in, navigate to an issue-tagged report, tap "Sync to GitHub"
**Expected:** Spinner appears, button disables, SnackBar says "GitHub issue created" with a View action that opens the GitHub issue URL; detail screen refreshes to show "View GitHub Issue" chip
**Why human:** Requires live GitHub OAuth token and a real Supabase report row; cannot mock the HTTP round-trip

#### 2. Dedup detection — second sync of same report

**Test:** Tap "Sync to GitHub" on a report that was already synced
**Expected:** SnackBar says "Existing GitHub issue linked" with a View action; no new issue appears on GitHub
**Why human:** GraphQL dedup search requires the hash comment to be present in an existing real GitHub issue

#### 3. GitHub issue body format

**Test:** Open the created GitHub issue in a browser
**Expected:** Body contains: (1) metadata table with Platform/Device/App Version/Report ID, (2) `<!-- hash:XXXXXXXXXXXX -->` HTML comment, (3) `## Description` section, (4) `## Screenshot` section with image or "No screenshot available", (5) `<details><summary>Logs</summary>` collapsible with code block
**Why human:** Body format correctness requires visual inspection of the rendered GitHub Markdown

#### 4. 401 re-auth flow

**Test:** Revoke the GitHub token in GitHub settings, then tap sync on an issue-tagged report
**Expected:** SnackBar shows "GitHub token expired — please re-authenticate"; Device Flow bottom sheet opens automatically
**Why human:** Requires deliberately revoked token; the 401 branch cannot be triggered without a real expired credential

#### 5. Sync button visibility by triage tag

**Test:** Navigate to reports with each tag: issue, feedback, duplicate, not-a-bug, needs-info, and untagged
**Expected:** Only issue-tagged reports (with no existing githubIssueUrl) show the "Sync to GitHub" button; duplicate-tagged show "Duplicate — excluded from GitHub sync" chip; all others show "Not synced to GitHub" text; already-synced issue reports show "View GitHub Issue" chip
**Why human:** Complete visual flow through all triage states needs device confirmation

### Gaps Summary

No gaps found. All 15 must-have truths are verified at the code level. All 8 artifacts exist, are substantive (no stubs), and are wired. All 5 key links are confirmed. All 5 SYNC requirements have implementation evidence.

The 5 human verification items are standard end-to-end tests that require live GitHub API credentials and a real device — they cannot be automated with static analysis. The SUMMARY records device verification as APPROVED (checkpoint:human-verify task was approved by the user during plan 04-02 execution).

---

_Verified: 2026-03-22_
_Verifier: Claude (gsd-verifier)_
