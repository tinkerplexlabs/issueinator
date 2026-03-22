# Architecture Research

**Domain:** Mobile bug triage tool — Flutter/Dart, Supabase backend, GitHub Issues integration
**Researched:** 2026-03-21
**Confidence:** HIGH (existing codebase examined directly; GitHub REST API verified from official docs)

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                    Presentation Layer                            │
│  ┌───────────┐  ┌───────────┐  ┌──────────────┐  ┌──────────┐  │
│  │ Dashboard │  │ReportList │  │ ReportDetail │  │ AuthGate │  │
│  │  Screen   │  │  Screen   │  │   Screen     │  │ Widget   │  │
│  └─────┬─────┘  └─────┬─────┘  └──────┬───────┘  └────┬─────┘  │
├────────┴───────────────┴───────────────┴───────────────┴────────┤
│                    Application Layer                             │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐    │
│  │AuthController│  │TriageContrlr │  │ GitHubSyncController│    │
│  │(ChangeNotif.)│  │(ChangeNotif.)│  │  (ChangeNotifier)  │    │
│  └──────┬───────┘  └──────┬───────┘  └─────────┬──────────┘    │
├─────────┴─────────────────┴──────────────────────┴──────────────┤
│                    Domain Layer                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │   BugReport     │  │  TriageTag enum │  │  GitHubIssue   │  │
│  │   AppUser       │  │  TriageComment  │  │  GitHubRepo    │  │
│  │  GitHubTokenData│  │  (pure models)  │  │  (pure models) │  │
│  └─────────────────┘  └─────────────────┘  └────────────────┘  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  BugReportRepository (abstract)                         │    │
│  │  GitHubIssueService (abstract)                          │    │
│  │  GitHubAuthService (abstract) — already exists          │    │
│  └─────────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────────┤
│                    Infrastructure Layer                         │
│  ┌──────────────────────┐  ┌──────────────────────────────┐    │
│  │SupabaseBugReport     │  │ GitHubIssueServiceImpl       │    │
│  │RepositoryImpl        │  │ (http package → REST API)    │    │
│  │(supabase_flutter)    │  │ POST /repos/{owner}/{repo}/  │    │
│  │                      │  │   issues                     │    │
│  └──────────────────────┘  │ GET /search/issues           │    │
│  ┌──────────────────────┐  └──────────────────────────────┘    │
│  │GitHubAuthServiceImpl │  ┌──────────────────────────────┐    │
│  │(already built)       │  │ LocalStorage / SecureStorage │    │
│  └──────────────────────┘  └──────────────────────────────┘    │
├─────────────────────────────────────────────────────────────────┤
│                    Config Layer                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ GetIt (dependencies.dart) — registers all singletons     │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

External:
  ┌─────────────────────┐      ┌────────────────────────────────┐
  │  Supabase           │      │  GitHub REST API               │
  │  bug_reports table  │      │  POST /repos/{owner}/{repo}/   │
  │  (RLS: admin UUID)  │      │    issues                      │
  │  + triage columns   │      │  GET /search/issues?q=...      │
  │  or triage_tags     │      │  POST /.../issues/{n}/comments │
  │  related table      │      │  (scope: repo)                 │
  └─────────────────────┘      └────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Communicates With |
|-----------|----------------|-------------------|
| `AuthGate` widget | Routes to AuthScreen or HomeScreen based on Supabase + GitHub auth state | AuthController |
| `AuthController` | Supabase session management, GitHub Device Flow coordination | SupabaseConfig, GitHubAuthService |
| `DashboardScreen` | Shows report counts per product, entry point for drill-down | TriageController |
| `ReportListScreen` | Scrollable, filterable list of bug reports for a product | TriageController |
| `ReportDetailScreen` | Full report view; triggers triage actions (tag, comment, sync, dismiss) | TriageController, GitHubSyncController |
| `TriageController` | Owns bug report list state, filter state, tag/comment mutations | BugReportRepository |
| `GitHubSyncController` | Owns sync state, deduplication check, issue creation result | GitHubIssueService, GitHubAuthService |
| `BugReportRepository` (abstract) | Fetch reports, apply triage tags, save comments, link duplicates | — |
| `SupabaseBugReportRepositoryImpl` | Implements BugReportRepository against Supabase `bug_reports` table | SupabaseConfig.client |
| `GitHubIssueService` (abstract) | Create GitHub issue, search for duplicates, post comment | — |
| `GitHubIssueServiceImpl` | Implements GitHubIssueService via GitHub REST API with Bearer token | http package |
| `GitHubAuthServiceImpl` | Device Flow OAuth, token storage/validation | FlutterSecureStorage, http |
| `SupabaseConfig` | Static Supabase client initialization and session refresh | supabase_flutter |
| `GetIt` (dependencies.dart) | Wires all singletons at startup | All services, controllers |

## Recommended Project Structure

The existing skeleton already follows clean architecture. Extend it with these additions:

```
lib/
├── config/
│   └── dependencies.dart          # Add new service/controller registrations here
├── core/
│   └── dev_log.dart               # Already exists
├── domain/
│   ├── models/
│   │   ├── app_user.dart          # Already exists
│   │   ├── bug_report.dart        # NEW — maps bug_reports table row
│   │   ├── triage_tag.dart        # NEW — enum: issue/feedback/duplicate/not_a_bug/needs_info
│   │   ├── triage_comment.dart    # NEW — developer comment on a report
│   │   └── github_issue.dart      # NEW — GitHub issue response model
│   ├── repositories/
│   │   └── bug_report_repository.dart   # NEW — abstract interface
│   └── services/
│       ├── github_auth_service.dart     # Already exists
│       └── github_issue_service.dart    # NEW — abstract interface
├── application/
│   └── controllers/
│       ├── auth_controller.dart         # Already exists
│       ├── triage_controller.dart       # NEW — report list + mutation state
│       └── github_sync_controller.dart  # NEW — sync state per report
├── infrastructure/
│   ├── persistence/
│   │   └── local_storage.dart           # Already exists
│   └── services/
│       ├── supabase_config.dart                 # Already exists
│       ├── github_auth_service_impl.dart         # Already exists
│       ├── supabase_bug_report_repository_impl.dart  # NEW
│       └── github_issue_service_impl.dart            # NEW
└── presentation/
    ├── screens/
    │   ├── auth_screen.dart         # Already exists (will swap auth method)
    │   ├── home_screen.dart         # Already exists (will become Dashboard)
    │   ├── report_list_screen.dart  # NEW
    │   └── report_detail_screen.dart # NEW
    └── widgets/
        ├── auth_gate.dart           # Already exists
        ├── github_device_flow_dialog.dart  # Already exists
        ├── triage_tag_chip.dart     # NEW — visual tag selector
        ├── report_card.dart         # NEW — list tile for a report
        └── github_sync_button.dart  # NEW — sync/status indicator
```

### Structure Rationale

- **domain/repositories/ vs domain/services/:** Repositories own Supabase data (CRUD on `bug_reports`). Services own external API calls (GitHub REST). This keeps the two external systems independently testable.
- **Two controllers:** `TriageController` drives the UI for reading/tagging/commenting (Supabase-facing). `GitHubSyncController` drives sync operations (GitHub-facing). Splitting avoids one mega-controller with 15 methods.
- **No new top-level features folder:** Project is single-feature (bug triage). Feature-based folders would add overhead with no benefit at this scale.

## Architectural Patterns

### Pattern 1: Repository Wraps Supabase, Returns Domain Models

**What:** `SupabaseBugReportRepositoryImpl` queries Supabase and returns `List<BugReport>` (pure domain model), never exposing `PostgrestList` to the application layer.

**When to use:** Any time Supabase data needs to reach a controller or screen.

**Trade-offs:** Slight mapping overhead; pays off in testability and insulation from Supabase SDK changes.

**Example:**
```dart
// domain/repositories/bug_report_repository.dart
abstract class BugReportRepository {
  Future<List<BugReport>> fetchReports({String? sourceApp});
  Future<void> applyTag(String reportId, TriageTag tag);
  Future<void> addComment(String reportId, String text);
  Future<void> linkDuplicate(String reportId, String canonicalId);
  Future<void> markSynced(String reportId, String githubIssueUrl);
}

// infrastructure/services/supabase_bug_report_repository_impl.dart
class SupabaseBugReportRepositoryImpl implements BugReportRepository {
  @override
  Future<List<BugReport>> fetchReports({String? sourceApp}) async {
    var query = SupabaseConfig.client.from('bug_reports').select();
    if (sourceApp != null) query = query.eq('source_app', sourceApp);
    final rows = await query.order('created_at', ascending: false);
    return rows.map(BugReport.fromJson).toList();
  }
}
```

### Pattern 2: Service Wraps GitHub REST API with Stored Bearer Token

**What:** `GitHubIssueServiceImpl` retrieves the stored token from `GitHubAuthService` at call time and injects it as `Authorization: Bearer <token>` on every request. No token stored in the service itself.

**When to use:** All GitHub API calls (create issue, search issues, post comment).

**Trade-offs:** Slight coupling to `GitHubAuthService`; avoids token duplication and staleness bugs.

**Example:**
```dart
// domain/services/github_issue_service.dart
abstract class GitHubIssueService {
  Future<GitHubIssue> createIssue({
    required String owner,
    required String repo,
    required String title,
    required String body,
    List<String> labels,
  });
  Future<List<GitHubIssue>> searchSimilar({
    required String owner,
    required String repo,
    required String keywords,
  });
}

// infrastructure/services/github_issue_service_impl.dart
class GitHubIssueServiceImpl implements GitHubIssueService {
  final GitHubAuthService _auth;
  GitHubIssueServiceImpl(this._auth);

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getStoredToken();
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
  }
}
```

### Pattern 3: Product-to-Repo Mapping in Domain

**What:** A static map in the domain layer translates `source_app` values from `bug_reports` to the correct GitHub `owner/repo` pair. Not hardcoded in the infrastructure layer.

**When to use:** Before creating any GitHub issue. Also used by `DashboardScreen` to show per-product counts.

**Trade-offs:** Static map must be updated when new TinkerPlex games ship. Easy to change in one place.

**Example:**
```dart
// domain/models/tinkerplex_product.dart
enum TinkerplexProduct {
  puzzleNook('puzzlenook', 'tinkerplexlabs', 'puzzlenook'),
  freecell('freecell', 'tinkerplexlabs', 'freecell'),
  paint('paint', 'tinkerplexlabs', 'paint'),
  blocks('blocks', 'tinkerplexlabs', 'blocks'),
  reader('reader', 'tinkerplexlabs', 'reader');

  final String sourceApp;  // matches bug_reports.source_app
  final String githubOwner;
  final String githubRepo;

  const TinkerplexProduct(this.sourceApp, this.githubOwner, this.githubRepo);

  static TinkerplexProduct? fromSourceApp(String sourceApp) =>
      values.firstWhereOrNull((p) => p.sourceApp == sourceApp);
}
```

### Pattern 4: TriageController Holds Filters as State

**What:** `TriageController` (ChangeNotifier) holds the active `sourceApp` filter and fetches/re-fetches reports when the filter changes. Screens call `controller.setFilter(app)` and rebuild via `Consumer`.

**When to use:** Dashboard drill-down, product filter chip selection.

**Trade-offs:** Simple; re-fetches from Supabase on filter change (acceptable for this data volume and single-admin use case; no real-time subscription needed).

## Data Flow

### Read Flow: Dashboard to Report Detail

```
User opens app
    ↓
AuthGate checks AuthController.isAuthenticated (Supabase)
  + AuthController.isGitHubAuthenticated
    ↓ (both true)
HomeScreen / DashboardScreen mounted
    ↓
TriageController.loadDashboard()
    ↓
BugReportRepository.fetchReports() — Supabase query, RLS grants access (admin UUID)
    ↓
List<BugReport> returned, grouped by source_app
    ↓
DashboardScreen shows count cards per product
    ↓
User taps product card → ReportListScreen(sourceApp: 'freecell')
    ↓
TriageController.setFilter('freecell') → re-fetch
    ↓
ReportListScreen renders report cards
    ↓
User taps report → ReportDetailScreen(report: report)
    ↓
Full report displayed (description, device_info, platform, logs, screenshot_base64)
```

### Write Flow: Triage Action

```
User selects tag (e.g., "issue") on ReportDetailScreen
    ↓
TriageController.applyTag(reportId, TriageTag.issue)
    ↓
BugReportRepository.applyTag() — UPDATE bug_reports SET triage_tag = 'issue'
    ↓
TriageController.notifyListeners() → UI shows tag applied
    ↓ (if tag == issue)
GitHubSyncButton becomes active
    ↓
User taps "Sync to GitHub"
    ↓
GitHubSyncController.syncReport(report)
    ↓
GitHubIssueService.searchSimilar() — GET /search/issues?q=title+repo:owner/repo
    ↓ (no duplicates found)
GitHubIssueService.createIssue() — POST /repos/{owner}/{repo}/issues
    ↓
BugReportRepository.markSynced(reportId, githubIssueUrl)
    — UPDATE bug_reports SET github_issue_url = '...'
    ↓
UI shows GitHub link, sync button replaced with "View on GitHub"
```

### State Management

```
GetIt singleton registry
    ↓ (injects into)
Controllers (ChangeNotifier)
    ↓ (notifyListeners)
Consumer<TriageController> / Consumer<GitHubSyncController>
    ↓ (rebuilds)
Screen widgets
```

Controllers are registered as lazy singletons in GetIt. Screens access them via `context.read<TriageController>()` (Provider) or `getIt<TriageController>()` where context is unavailable.

### Key Data Flows

1. **Auth gate:** Both Supabase session (admin UUID) AND GitHub token must be valid before the main UI loads. Missing either redirects to the appropriate auth step.
2. **Triage tag persistence:** Tags and comments written directly to Supabase; `github_issue_url` column updated post-sync. All writes go through the repository interface, not raw Supabase calls in controllers.
3. **GitHub deduplication:** `GET /search/issues` is called with extracted keywords from the report description before creating any issue. Rate limit is 30 req/min (authenticated) — not a concern for single-admin use.
4. **Source app routing:** `TinkerplexProduct.fromSourceApp(report.sourceApp)` resolves the GitHub `owner/repo` before any API call. Null result = known product gap, shown as error in UI.

## Scaling Considerations

This is a single-admin internal tool. The following applies:

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1 admin, ~53–500 reports | Current approach is correct. Fetch-on-demand, no real-time subscription, no pagination initially needed. |
| 500–5000 reports | Add cursor-based pagination to `BugReportRepository.fetchReports()`. Supabase supports `.range(from, to)` natively. |
| Multiple admins | Remove hardcoded admin UUID from RLS. Introduce a `developer_users` table, update RLS policy. Auth flow unchanged. |

### Scaling Priorities

1. **First bottleneck:** Report list performance with many rows. Fix: add `.range()` pagination and a `triage_tag` index in Supabase.
2. **Second bottleneck:** GitHub API rate limits during bulk sync. Fix: queue sync operations and add per-request delay, or use GitHub's conditional requests (`If-None-Match`).

## Anti-Patterns

### Anti-Pattern 1: Direct Supabase Calls in Controllers

**What people do:** Call `Supabase.instance.client.from('bug_reports').select()` directly inside `TriageController`.

**Why it's wrong:** Couples business logic to Supabase SDK types. Makes controllers untestable without a live Supabase connection. Any schema change ripples into controller code.

**Do this instead:** Controllers call `BugReportRepository` (the abstract interface). The repository handles all Supabase specifics.

### Anti-Pattern 2: One God Controller

**What people do:** Put auth, triage list management, detail view state, and GitHub sync all into a single `AppController`.

**Why it's wrong:** The controller becomes >400 lines. State changes in one area (e.g., sync progress) cause unnecessary rebuilds in unrelated widgets (e.g., the report list).

**Do this instead:** Three focused controllers — `AuthController` (exists), `TriageController` (reports + tags + comments), `GitHubSyncController` (sync state per report). Each controller owns one cohesive concern.

### Anti-Pattern 3: Hardcoding GitHub Owner/Repo Strings in Infrastructure

**What people do:** Scatter `'tinkerplexlabs/freecell'` strings directly in `GitHubIssueServiceImpl`.

**Why it's wrong:** When a new game ships or a repo is renamed, you hunt through infrastructure code to find all the strings.

**Do this instead:** `TinkerplexProduct` enum in the domain layer owns all `sourceApp → owner/repo` mappings. Infrastructure receives resolved values, never raw `source_app` strings.

### Anti-Pattern 4: Storing Triage State Only in Flutter Memory

**What people do:** Hold triage tags in controller state without persisting immediately to Supabase.

**Why it's wrong:** App kill or navigation pop loses unsaved tags. For a triage tool, this means silent data loss — the exact problem the tool is designed to prevent.

**Do this instead:** Every tag and comment write fires a Supabase mutation immediately (optimistic UI update + persist in the same operation). The `github_issue_url` column is the source of truth for sync status.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Supabase | `supabase_flutter` SDK, PKCE auth flow, RLS via admin UUID JWT | Client already initialized in `SupabaseConfig`. Repository calls `.from('bug_reports')`. No schema changes to existing columns. New columns (`triage_tag`, `triage_comment`) or a new `bug_report_tags` table must be backward-compatible. |
| GitHub REST API | `http` package with Bearer token from `GitHubAuthServiceImpl`. Scope `repo` (already requested in device flow). API version header `2022-11-28`. | Endpoints used: `POST /repos/{owner}/{repo}/issues`, `GET /search/issues`, `POST /repos/{owner}/{repo}/issues/{n}/comments`. Rate limit: 30 req/min (search), 5000 req/hr (core). |
| Google Sign-In | Copy pattern from FreeCell app. `google_sign_in` + `signInWithIdToken()` on Supabase client. Required so admin authenticates as UUID `65ad7649-...` and RLS grants access. | Currently app uses anonymous auth — this is the first thing to fix before any triage features work. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Presentation ↔ Application | `Consumer<Controller>` via Provider; `context.read<Controller>()` for one-shot calls | Consistent with existing `AuthController` usage pattern |
| Application ↔ Domain | Direct method calls on repository/service interfaces; controllers hold no Supabase or HTTP types | Abstract interfaces enforce this boundary |
| Domain ↔ Infrastructure | GetIt injects concrete impls at startup; domain never imports infrastructure packages | `dependencies.dart` is the only place concrete types appear |
| TriageController ↔ GitHubSyncController | No direct coupling. `ReportDetailScreen` holds references to both and coordinates them in the UI layer only. | This keeps sync state separate from triage state |

## Build Order Implications

Dependencies between components determine build order:

1. **Domain models first** (`BugReport`, `TriageTag`, `TinkerplexProduct`) — everything else depends on these.
2. **Repository and service interfaces** (`BugReportRepository`, `GitHubIssueService`) — contracts that both application and infrastructure depend on.
3. **Infrastructure impls** (`SupabaseBugReportRepositoryImpl`, `GitHubIssueServiceImpl`) — implement the interfaces; depend on Supabase SDK and http package.
4. **Controllers** (`TriageController`, `GitHubSyncController`) — depend on repository/service interfaces; can be built once interfaces are stable.
5. **Supabase schema extension** — `triage_tag` column (or related table) must exist before the repository impl can write tags. This is a blocking prerequisite for any triage writes.
6. **Google Sign-In** — blocks access to `bug_reports` entirely (RLS). Must be in place before any read feature works. Build this in phase 1.
7. **Presentation screens** — built last, after controllers confirm data flows correctly.

## Sources

- GitHub REST API — Issues: https://docs.github.com/en/rest/issues/issues (verified 2026-03-21, API version 2026-03-10)
- GitHub Search API — Issues: https://docs.github.com/en/rest/search (verified 2026-03-21; 30 req/min authenticated)
- GitHub Changelog — Advanced search, duplicate detection, sub-issues: https://github.blog/changelog/2025-03-06-github-issues-projects-api-support-for-issues-advanced-search-and-more/
- Supabase Realtime + RLS: https://supabase.com/docs/guides/realtime/authorization (MEDIUM confidence — RLS must be respected by realtime subscriptions)
- Existing issueinator codebase — `lib/` directory examined directly (HIGH confidence for current state)
- TinkerPlex CLAUDE.md — Clean architecture conventions, GetIt + Provider pattern (HIGH confidence)

---
*Architecture research for: IssueInator — Flutter bug triage tool*
*Researched: 2026-03-21*
