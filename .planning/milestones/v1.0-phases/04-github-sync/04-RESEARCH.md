# Phase 4: GitHub Sync - Research

**Researched:** 2026-03-22
**Domain:** GitHub REST API + GraphQL, Supabase Storage, Flutter async/http, content hash dedup
**Confidence:** HIGH

## Summary

Phase 4 moves the sync logic that already exists in `freecell/tool/sync_bug_reports_to_github.dart` and `puzzlenook/tool/sync_bug_reports_to_github.dart` into the issueinator app UI. The CLI tools provide a near-complete algorithm; the primary engineering challenge is adapting from CLI/service-role-key environment to mobile/user-JWT environment and replacing the `gh` binary with direct REST+GraphQL API calls.

The key architectural decisions are: (1) screenshot upload uses the Supabase Dart SDK's `uploadBinary` method — the `bug-screenshots` bucket is already public and accepts uploads from authenticated user JWTs; (2) content hash dedup must use GitHub's **GraphQL** search API because the REST `/search/issues` endpoint does NOT work for private repos even with `repo` scope; (3) GitHub issue creation uses a plain REST POST with the token stored by `GitHubAuthServiceImpl`; (4) the source_app → GitHub repo mapping must be hardcoded in the app because the `products` table has no `github_repo` column and the shared schema must not be modified.

**Primary recommendation:** Port the CLI tool algorithm directly into a new `GitHubSyncService` + `SyncController`, replacing `gh` CLI calls with direct HTTP/GraphQL calls using the stored OAuth token. The existing `GitHubAuthService` already provides token retrieval and 401 → Device Flow re-auth.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SYNC-01 | Developer can sync "issue"-tagged reports to the correct GitHub repo based on source_app | Hardcoded source_app→repo map; sync button in report detail when triage_tag == 'issue' |
| SYNC-02 | Sync uses content hash dedup — hash embedded in issue body as HTML comment — to prevent duplicates | GraphQL search `hash:VALUE in:body` confirmed working on private repos; hash format `<!-- hash:XXXXXXXXXXXX -->` already in all existing issues |
| SYNC-03 | After creating a GitHub issue, github_issue_url is written back to Supabase | REST PATCH bug_reports with user JWT confirmed working (admin UUID has RLS access) |
| SYNC-04 | Sync uploads screenshot to Supabase Storage and embeds public URL in GitHub issue body | `bug-screenshots` bucket is public; upload with user JWT (anon key + Bearer) confirmed working; Dart SDK `uploadBinary` available |
| SYNC-05 | Sync routes to correct repo per product (e.g., freecell → tinkerplexlabs/freecell) | Hardcoded map: `freecell → tinkerplexlabs/freecell`, `puzzle_nook → tinkerplexlabs/puzzlenook`; only these two repos exist on GitHub |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `http` | 1.6.0 (in pubspec.lock) | GitHub REST API calls (POST create issue, PATCH update Supabase) | Already in pubspec; used by GitHubAuthServiceImpl |
| `supabase_flutter` | 2.12.0 | Supabase Storage upload + bug_reports PATCH | Already integrated; `storage_client` 2.4.1 bundled |
| `crypto` | 3.0.7 | SHA-256 content hash (first 12 hex chars) | Already in pubspec; used for same purpose in CLI tools |
| `get_it` | 7.6.0 | DI for new SyncController | Already integrated |
| `provider` | 6.1.0 | Reactive UI for sync progress | Already integrated |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `dart:convert` | SDK | base64Decode for screenshot, jsonEncode for API bodies | Always needed for this phase |
| `flutter/foundation.dart` | SDK | `compute()` for background base64 decode | Prevents UI jank during screenshot decode |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Direct GraphQL HTTP call for dedup | GitHub REST `/search/issues` | REST search API returns 422 for private repos even with `repo` scope — GraphQL is the only option |
| Hardcoded source_app→repo map | Adding `github_repo` column to `products` table | Schema is shared and must not be modified per CLAUDE.md constraint |
| Supabase Dart SDK for screenshot upload | Direct `http` POST (as CLI tool does) | Dart SDK is simpler, already present, handles retries, uses user session auth automatically |

**Installation:** No new packages required. All dependencies already present.

## Architecture Patterns

### Recommended Project Structure
```
lib/
├── domain/
│   ├── models/
│   │   └── sync_result.dart          # SyncResult sealed class (success/duplicate/error)
│   └── services/
│       └── github_sync_service.dart  # Abstract GitHubSyncService
├── infrastructure/
│   └── services/
│       └── github_sync_service_impl.dart  # Concrete impl: hash, upload, create, update
└── application/
    └── controllers/
        └── sync_controller.dart      # ChangeNotifier for UI sync state
```

### Pattern 1: Content Hash Dedup via GraphQL Search
**What:** Compute SHA-256 of `description + device_info + platform + app_version`, take first 12 hex chars, embed as `<!-- hash:XXXXXXXXXXXX -->` in issue body. Before creating, search GitHub GraphQL for existing issues containing that hash.

**When to use:** Always, before calling the create issue endpoint.

**Verified behavior:** `hash:VALUE in:body` query in GraphQL search finds content inside HTML comments. Tested on live `tinkerplexlabs/freecell` repo.

```dart
// Content hash — identical to CLI tool algorithm
String _contentHash(String description, String deviceInfo, String platform, String appVersion) {
  final input = '$description\n$deviceInfo\n$platform\n$appVersion';
  final digest = sha256.convert(utf8.encode(input));
  return digest.toString().substring(0, 12);
}

// GraphQL dedup search — the ONLY approach that works for private repos
Future<String?> _findExistingIssue(String hash, String repo, String token) async {
  const url = 'https://api.github.com/graphql';
  final query = '''
  {
    search(query: "hash:$hash in:body repo:$repo", type: ISSUE, first: 1) {
      nodes {
        ... on Issue { url }
      }
    }
  }
  ''';
  final response = await http.post(
    Uri.parse(url),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'query': query}),
  );
  // parse response.body['data']['search']['nodes'][0]['url']
}
```

### Pattern 2: Screenshot Upload via Supabase Dart SDK
**What:** Decode base64 screenshot to `Uint8List`, upload to `bug-screenshots` bucket using `SupabaseConfig.client.storage.from('bug-screenshots').uploadBinary(...)`, then call `getPublicUrl()`.

**Verified behavior:** The `bug-screenshots` bucket is public. Upload with the user's JWT (which supabase_flutter sends automatically) succeeds. The public URL is immediately accessible.

```dart
// Upload screenshot and get public URL
Future<String?> _uploadScreenshot(String reportId, String base64Data) async {
  final bytes = await compute(base64Decode, base64Data);
  final path = '$reportId.png';
  try {
    await SupabaseConfig.client.storage
        .from('bug-screenshots')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );
    return SupabaseConfig.client.storage
        .from('bug-screenshots')
        .getPublicUrl(path);
  } catch (e) {
    // Non-fatal: sync proceeds without screenshot URL
    return null;
  }
}
```

### Pattern 3: GitHub REST Issue Creation
**What:** POST to `https://api.github.com/repos/{owner}/{repo}/issues` with the stored GitHub token. Return the issue's `html_url`.

**Verified behavior:** Tested live against `tinkerplexlabs/freecell`. Response includes `html_url` (the GitHub web URL) and `url` (API URL). Issue body format identical to existing CLI tools.

```dart
Future<String> _createGitHubIssue(String repo, String title, String body, String token) async {
  final response = await http.post(
    Uri.parse('https://api.github.com/repos/$repo/issues'),
    headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'title': title,
      'body': body,
      'labels': ['bug', 'bug-report'],
    }),
  );
  if (response.statusCode == 401) throw GitHubAuthException();
  if (response.statusCode != 201) throw Exception('GitHub API error: ${response.statusCode}');
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  return json['html_url'] as String; // NOT 'url' — html_url is the web link
}
```

### Pattern 4: Source App → GitHub Repo Routing
**What:** Hardcoded map in `GitHubSyncServiceImpl`. The two repos that exist are `tinkerplexlabs/freecell` and `tinkerplexlabs/puzzlenook`.

```dart
static const Map<String, String> _repoMap = {
  'freecell': 'tinkerplexlabs/freecell',
  'puzzle_nook': 'tinkerplexlabs/puzzlenook',
  // Future apps added here
};

String? repoForApp(String sourceApp) => _repoMap[sourceApp];
```

### Pattern 5: 401 → Device Flow Re-auth
**What:** When any GitHub API call returns 401, catch `GitHubAuthException`, revoke the stored token, and trigger `GitHubDeviceFlowSheet.show(context)` — the existing dialog.

**Important:** Do NOT silently swallow 401s. SYNC-05 success criterion requires prompting re-auth.

### Pattern 6: Supabase Write-Back for github_issue_url
**What:** After successful issue creation OR dedup detection, PATCH `bug_reports` to set `github_issue_url`. This uses the existing `SupabaseConfig.client` with the admin user JWT — RLS allows updates because the admin UUID matches.

**Note:** The `BugReportRepository` should get a new `updateGithubIssueUrl(String reportId, String url)` method. This is a direct write to `bug_reports`, not `bug_report_triage`.

### Pattern 7: SyncResult sealed class
```dart
sealed class SyncResult { const SyncResult(); }
class SyncSuccess extends SyncResult {
  final String issueUrl;
  const SyncSuccess(this.issueUrl);
}
class SyncDuplicate extends SyncResult {
  final String existingUrl;
  const SyncDuplicate(this.existingUrl);
}
class SyncError extends SyncResult {
  final String message;
  final bool requiresReAuth;
  const SyncError(this.message, {this.requiresReAuth = false});
}
```

### Pattern 8: Issue Body Format (carry forward from CLI tools)
The body format is already established and battle-tested. Use it verbatim:
- Metadata table: Platform, Device, App Version, Report ID
- HTML comment: `<!-- hash:XXXXXXXXXXXX -->`
- Description section
- Screenshot section (if URL available)
- Logs section in `<details>` collapse (last 512 KB)

### Anti-Patterns to Avoid
- **Using REST `/search/issues` for dedup:** Returns 422 for private repos. Must use GraphQL.
- **Using `gh` CLI binary:** Not available in mobile app. Use direct HTTP/GraphQL.
- **Service role key in mobile app:** Not present in issueinator. Use user session JWT for Supabase, stored OAuth token for GitHub.
- **Fetching `screenshot_base64` in list queries:** Already excluded by column projection. Only fetch for the specific report being synced, using the existing `getReportScreenshot()` method.
- **Blocking the UI during sync:** Run sync in async method, show progress via `SyncController` ChangeNotifier.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Screenshot upload | Custom multipart HTTP POST | `SupabaseConfig.client.storage.from(...).uploadBinary()` | Handles retries, auth headers, upsert |
| Base64 decode | Sync on main thread | `compute(base64Decode, b64)` | Large screenshots cause jank on main thread |
| GitHub token retrieval | Re-implement storage | `GetIt.instance<GitHubAuthService>().getStoredToken()` | Already implemented in `GitHubAuthServiceImpl` |
| Device flow re-auth trigger | Build new dialog | `GitHubDeviceFlowSheet.show(context)` | Already implemented and tested |
| Content hash | Custom hash | `sha256.convert(utf8.encode(...)).toString().substring(0, 12)` from `crypto` package | Identical to CLI tool — maintains dedup compatibility with existing issues |

## Common Pitfalls

### Pitfall 1: REST Search API Silently Fails for Private Repos
**What goes wrong:** `GET /search/issues?q=hash%3AVALUE+in%3Abody+repo%3Aowner%2Frepo` returns 422 Validation Failed, not 401 or a meaningful error. You get no results and might conclude "no duplicate" when one exists.

**Why it happens:** GitHub's REST search API does not support private repo searches, regardless of token scope.

**How to avoid:** Use GraphQL `search(query: "hash:VALUE in:body repo:owner/repo", type: ISSUE)`. Confirmed working on private repos with `repo` scope token.

**Warning signs:** 422 response from `/search/issues` endpoint.

### Pitfall 2: Using `url` Instead of `html_url` in Issue Creation Response
**What goes wrong:** GitHub API returns both `url` (API URL: `https://api.github.com/repos/.../issues/N`) and `html_url` (web URL: `https://github.com/.../issues/N`). Storing the API URL means the "View GitHub Issue" button in the app navigates to JSON, not the issue page.

**How to avoid:** Always use `html_url` from the creation response and the GraphQL `url` field (GraphQL returns the web URL in the `url` field of an Issue node).

**Warning signs:** Stored `github_issue_url` starts with `https://api.github.com/` instead of `https://github.com/`.

### Pitfall 3: Sync Button Available for Non-"Issue"-Tagged Reports
**What goes wrong:** Reports tagged 'duplicate' or 'feedback' get synced to GitHub, creating noise.

**How to avoid:** The sync button must only appear (or be enabled) when `triage_tag == 'issue'`. TRIA-04 already establishes that duplicates are excluded. The UI should enforce this.

### Pitfall 4: Race Condition on Double-Tap Sync
**What goes wrong:** User taps sync twice quickly, creating two GitHub issues before the dedup can detect the first.

**How to avoid:** `SyncController` should set `_isSyncing = true` at the start and guard against re-entry. The button should be disabled while `isSyncing`.

### Pitfall 5: Screenshot Fetch in Sync Without On-Demand Load
**What goes wrong:** The report detail view loads without screenshot (on-demand only). Sync must fetch `screenshot_base64` explicitly because it's not in `_detail`.

**How to avoid:** In `GitHubSyncService.syncReport()`, call `repo.getReportScreenshot(reportId)` explicitly before uploading. The `BugReportDetail` model already has `screenshotBase64` field but it won't be populated unless fetched separately.

### Pitfall 6: Missing State Refresh After Sync
**What goes wrong:** After successful sync, the report detail still shows "Not synced to GitHub" because `_detail.githubIssueUrl` is stale.

**How to avoid:** After sync, call `_fetchDetail()` to reload the report, or update `_detail` in place with the new URL. The report list also needs refresh to show the sync status in list items.

### Pitfall 7: 401 on GraphQL Dedup Search Not Handled
**What goes wrong:** The dedup search returns 401 (token expired), but the code treats it as "no duplicate found" and proceeds to create a new issue, then hits 401 again on create.

**How to avoid:** Check for 401 on the GraphQL search response before interpreting the results. Throw `GitHubAuthException` on 401 in all GitHub API calls, not just issue creation.

### Pitfall 8: GitHub Search Rate Limit (30 req/min)
**What goes wrong:** Batch syncing many reports rapidly hits the 30 req/min GraphQL search limit.

**How to avoid:** Phase 4 syncs one report at a time (single tap from detail view). This is unlikely to hit rate limits. If batch sync is ever added, add a 2-second delay between operations.

## Code Examples

### Full Sync Flow
```dart
// Source: derived from freecell/tool/sync_bug_reports_to_github.dart (verified working)
Future<SyncResult> syncReport(String reportId, BugReportDetail detail) async {
  // 1. Get stored token — throws if not authenticated
  final token = await _githubAuthService.getStoredToken();
  if (token == null) return const SyncError('Not authenticated', requiresReAuth: true);

  // 2. Route to correct repo
  final repo = _repoMap[detail.sourceApp];
  if (repo == null) return SyncError('No GitHub repo mapped for "${detail.sourceApp}"');

  // 3. Compute content hash
  final hash = _contentHash(
    detail.description,
    detail.deviceInfo ?? '',
    detail.platform ?? '',
    detail.appVersion ?? '',
  );

  // 4. Check for existing issue (GraphQL)
  try {
    final existingUrl = await _findExistingIssue(hash, repo, token);
    if (existingUrl != null) {
      await _repository.updateGithubIssueUrl(reportId, existingUrl);
      return SyncDuplicate(existingUrl);
    }
  } on GitHubAuthException {
    await _githubAuthService.revokeToken();
    return const SyncError('GitHub token expired', requiresReAuth: true);
  }

  // 5. Upload screenshot (non-fatal if fails)
  final screenshotB64 = await _repository.getReportScreenshot(reportId);
  String? screenshotUrl;
  if (screenshotB64 != null && screenshotB64.isNotEmpty) {
    screenshotUrl = await _uploadScreenshot(reportId, screenshotB64);
  }

  // 6. Build issue body (identical to CLI tool format)
  final title = _issueTitle(detail.description);
  final body = _issueBody(
    platform: detail.platform ?? 'Unknown',
    deviceInfo: detail.deviceInfo ?? 'Unknown',
    appVersion: detail.appVersion ?? 'Unknown',
    reportId: reportId,
    contentHash: hash,
    description: detail.description,
    screenshotUrl: screenshotUrl,
    logs: detail.logs ?? '',
  );

  // 7. Create GitHub issue
  try {
    final issueUrl = await _createGitHubIssue(repo, title, body, token);
    await _repository.updateGithubIssueUrl(reportId, issueUrl);
    return SyncSuccess(issueUrl);
  } on GitHubAuthException {
    await _githubAuthService.revokeToken();
    return const SyncError('GitHub token expired', requiresReAuth: true);
  }
}
```

### GraphQL Search (verified working on private repo)
```dart
// Source: verified via gh graphql API call against tinkerplexlabs/freecell
Future<String?> _findExistingIssue(String hash, String repo, String token) async {
  final response = await http.post(
    Uri.parse('https://api.github.com/graphql'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'query': '''
        {
          search(query: "hash:$hash in:body repo:$repo", type: ISSUE, first: 1) {
            nodes {
              ... on Issue {
                url
              }
            }
          }
        }
      ''',
    }),
  );
  if (response.statusCode == 401) throw GitHubAuthException();
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  final nodes = (data['data']?['search']?['nodes'] as List?) ?? [];
  if (nodes.isEmpty) return null;
  return nodes[0]['url'] as String?;
}
```

### SyncController (ChangeNotifier)
```dart
class SyncController extends ChangeNotifier {
  final GitHubSyncService _syncService;
  SyncController(this._syncService);

  bool _isSyncing = false;
  SyncResult? _lastResult;

  bool get isSyncing => _isSyncing;
  SyncResult? get lastResult => _lastResult;

  Future<SyncResult> sync(BugReportDetail detail) async {
    if (_isSyncing) return const SyncError('Already syncing');
    _isSyncing = true;
    _lastResult = null;
    notifyListeners();

    try {
      final result = await _syncService.syncReport(detail.id, detail);
      _lastResult = result;
      return result;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
```

### UI Integration in ReportDetailScreen
The sync button goes in `_buildStatusBar()`, in the slot already reserved with the comment "Phase 4 will add sync button":
```dart
// Replace the "Not synced to GitHub" text with:
else if (currentTag == TriageTag.issue)
  FilledButton.icon(
    onPressed: _isSyncing ? null : () => _syncReport(context),
    icon: _isSyncing
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.upload),
    label: Text(_isSyncing ? 'Syncing…' : 'Sync to GitHub'),
  )
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CLI tool with `gh` binary + service role key | In-app HTTP/GraphQL with stored OAuth token | Phase 4 (now) | No CLI needed; works on mobile |
| REST `/search/issues` (doesn't work for private repos) | GraphQL search | Discovered during research | Must use GraphQL for private repo search |
| `Process.run('gh', [...])` | `http.post(...)` | Phase 4 | Direct API calls; no subprocess |

**Deprecated/outdated:**
- `freecell/tool/sync_bug_reports_to_github.dart`: Will become obsolete after Phase 4
- `puzzlenook/tool/sync_bug_reports_to_github.dart`: Same

## Open Questions

1. **Products table `github_repo` column — schema modification allowed?**
   - What we know: CLAUDE.md says "Do not modify the Supabase schema — it's fixed across all apps". The `products` table has `id, name, description, created_at, updated_at`. No `github_repo` column. The shared tables (bug_reports, game_sessions) clearly can't be modified. The `products` table was created by issueinator itself.
   - What's unclear: Whether `products` is off-limits or whether a new column there is acceptable.
   - Recommendation: **Use hardcoded map** to stay safe. `freecell` and `puzzle_nook` are the only repos that exist. The map can be updated in code when new apps are added. This avoids the schema question entirely.

2. **GitHub Search indexing lag for new issues**
   - What we know: STATE.md notes "GitHub Search API indexing speed for fingerprint dedup — validate during Phase 4 planning." GitHub's search index is not real-time; newly created issues may not be searchable for 30–60 seconds.
   - What's unclear: Exact indexing delay for private repos.
   - Recommendation: The primary dedup mechanism is `github_issue_url IS NOT NULL` in the DB. The hash search is a secondary safety net for cases where the DB write failed but the issue was created. If a user taps sync, sees it "succeed", and immediately taps again, the DB check will catch it before the hash search. The indexing lag is unlikely to cause real duplicates in normal use.

3. **What to show in list items for synced reports**
   - What we know: `BugReportSummary` already has `githubIssueUrl` field. The list item shows triage tag but not sync status.
   - What's unclear: Success criterion 4 says "github_issue_url is visible in the report detail AND in the list item."
   - Recommendation: Add a small GitHub icon or "Synced" badge to list items where `githubIssueUrl != null`. This is a UI-only change in `report_list_screen.dart`.

## Validation Architecture

> nyquist_validation is false in .planning/config.json — skipping this section.

## Sources

### Primary (HIGH confidence)
- Live Supabase API test: `bug-screenshots` bucket accepts user JWT uploads and is publicly readable — confirmed HTTP 200
- Live GitHub GraphQL API: `hash:VALUE in:body repo:tinkerplexlabs/freecell` search returns correct issue — confirmed
- Live GitHub REST API: 401 response format confirmed with `{"message": "Bad credentials", "status": "401"}`
- `/home/daniel/work/tinkerplexlabs/demos/freecell/tool/sync_bug_reports_to_github.dart` — existing battle-tested algorithm
- `/home/daniel/work/tinkerplexlabs/demos/puzzlenook/tool/sync_bug_reports_to_github.dart` — identical algorithm
- `storage_client-2.4.1/lib/src/storage_file_api.dart` — Dart SDK `uploadBinary()` and `getPublicUrl()` signatures
- Supabase products table contents: `puzzle_nook`, `freecell`, `issueinator` — no `github_repo` column

### Secondary (MEDIUM confidence)
- GitHub REST API docs (docs.github.com): Create issue endpoint POST `/repos/{owner}/{repo}/issues`, response includes `html_url` field
- GitHub REST API docs: Search issues uses `in:body` qualifier; GraphQL needed for private repos

### Tertiary (LOW confidence)
- GitHub search indexing lag estimate (30–60 seconds): based on general GitHub documentation knowledge, not verified for this specific repo

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies verified in pubspec.lock; storage upload verified live
- Architecture: HIGH — GraphQL dedup verified working; REST create issue tested live; source_app values confirmed from DB
- Pitfalls: HIGH — REST search 422 failure confirmed live; html_url vs url distinction confirmed from live API response

**Research date:** 2026-03-22
**Valid until:** 2026-06-22 (90 days — GitHub API stable, Supabase SDK stable)
