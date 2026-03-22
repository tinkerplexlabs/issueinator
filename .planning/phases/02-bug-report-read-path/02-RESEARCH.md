# Phase 2: Bug Report Read Path - Research

**Researched:** 2026-03-22
**Domain:** Flutter UI (Provider/GetIt), Supabase PostgREST column projection, base64 image decoding
**Confidence:** HIGH

## Summary

Phase 2 builds three screens on top of the authenticated Supabase session from Phase 1: a dashboard (counts per product), a report list (no screenshot), and a report detail (full data including screenshot). All data comes from two existing tables — `bug_reports` and `products` — that are already accessible via the admin RLS policy confirmed in Phase 1. No migrations are required for the read path; the `bug_report_triage` side table (planned for Phase 3) does not yet exist.

The biggest implementation risk is screenshot handling: every single bug_reports row has `screenshot_base64` populated, and individual values measure 166–350 KB of text (base64-encoded). Fetching this column in list queries would multiply that per row and make the list query extremely slow. Column projection (`select: 'id,description,...'` without `screenshot_base64`) is mandatory for LIST-03 and is the primary performance gate the planner must enforce as a hard constraint. In detail view, a single screenshot decodes fine in memory using `dart:convert` + `Image.memory()`.

The dashboard counts (DASH-01, DASH-03) require a `COUNT(*)` and an "unprocessed" count per product. Since the `bug_report_triage` side table does not yet exist, "unprocessed" in Phase 2 means "no `github_issue_url` set" — a reasonable approximation using existing data. The planner should use this definition for Phase 2 and plan to revisit when Phase 3 adds triage status.

**Primary recommendation:** Build in three plans: (1) dashboard screen with product counts, (2) report list screen with column-projected query and pull-to-refresh, (3) report detail screen with full fields and zoomable screenshot.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DASH-01 | Developer sees per-product report counts on home screen | Two-query approach: `products` (already loaded) + `bug_reports` grouped by source_app with COUNT(*). Can be a single aggregated query. |
| DASH-02 | Developer can tap a product to drill into its report list | Navigator.push with product id/name argument to ReportListScreen |
| DASH-03 | Dashboard shows unprocessed vs total counts per product | "Unprocessed" = `github_issue_url IS NULL` in Phase 2. Single query groups by source_app with conditional count. |
| LIST-01 | Developer sees scrollable list of bug reports filtered by product | Supabase `.from('bug_reports').select(projected_columns).eq('source_app', productName).order('created_at', ascending: false)` |
| LIST-02 | Each list item shows description preview, platform, date, and triage status | All four fields present in bug_reports (description, platform, created_at, github_issue_url as proxy for triage). Truncate description to ~120 chars for preview. |
| LIST-03 | List excludes screenshot_base64 from query (column projection for performance) | CRITICAL: screenshots average 166–350 KB each; all 60 rows have screenshots. Explicit select string must omit this column. |
| LIST-04 | Developer can pull-to-refresh the report list | Flutter built-in `RefreshIndicator` widget wrapping the `ListView`. Call controller reload on onRefresh callback. |
| DETL-01 | Developer can tap a report to see full detail: description, device_info, app_version, platform, logs | Second query fetches all columns by id (including screenshot_base64). All fields present in schema. |
| DETL-02 | Developer can view screenshot rendered from base64 (decoded only in detail view) | `base64Decode(screenshotBase64)` from `dart:convert`, then `Image.memory(bytes)`. Wrap in `InteractiveViewer` for zoom. |
| DETL-03 | Report detail shows current triage tag and GitHub issue link if synced | `github_issue_url` is already in schema. No triage tag yet (Phase 3). Show github link if non-null; show "Not yet triaged" placeholder for tag. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| supabase_flutter | ^2.0.0 (already in pubspec) | PostgREST queries with column projection, RLS enforcement | Already integrated in Phase 1; admin RLS confirmed working |
| provider | ^6.1.0 (already in pubspec) | ChangeNotifier reactive state for controllers | Project standard; AuthController already uses this pattern |
| get_it | ^7.6.0 (already in pubspec) | DI for controller lookup in widgets | Project standard; already wired in dependencies.dart |
| intl | ^0.19.0 (already in pubspec) | Date formatting for report timestamps | Already in pubspec |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| dart:convert (stdlib) | built-in | base64Decode for screenshot rendering in detail view | No additional package needed |
| url_launcher | ^6.2.0 (already in pubspec) | Open github_issue_url in external browser from detail view | For DETL-03 GitHub link tap |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dart:convert base64Decode + Image.memory | photo_view package | photo_view adds pinch-zoom and better UX but is an extra dependency; InteractiveViewer from Flutter SDK is sufficient for a single-developer tool |
| Hardcoding "unprocessed = no github_issue_url" | Waiting for triage side table | Triage table doesn't exist yet; this proxy is accurate for current data (52/60 rows have github_issue_url) |

**Installation:** No new packages required. All needed libraries are already in pubspec.yaml.

## Architecture Patterns

### Recommended Project Structure
```
lib/
├── application/controllers/
│   ├── auth_controller.dart         # existing
│   ├── dashboard_controller.dart    # NEW: product counts
│   └── report_list_controller.dart  # NEW: list + pull-to-refresh
├── domain/models/
│   ├── app_user.dart                # existing
│   ├── bug_report_summary.dart      # NEW: list projection (no screenshot)
│   └── bug_report_detail.dart       # NEW: full detail (with screenshot)
├── infrastructure/repositories/
│   └── bug_report_repository.dart   # NEW: Supabase queries
├── presentation/screens/
│   ├── auth_screen.dart             # existing
│   ├── home_screen.dart             # REWRITE: add product count cards
│   ├── report_list_screen.dart      # NEW
│   └── report_detail_screen.dart    # NEW
└── config/
    └── dependencies.dart            # UPDATE: register new controllers/repos
```

### Pattern 1: Column Projection in Supabase Flutter
**What:** Pass explicit comma-separated column list to `.select()` to exclude `screenshot_base64`
**When to use:** All list queries — never use `select('*')` for bug_reports

```dart
// For list queries — screenshot_base64 MUST be excluded
final rows = await SupabaseConfig.client
    .from('bug_reports')
    .select('id, description, app_version, platform, created_at, github_issue_url, source_app')
    .eq('source_app', productName)
    .order('created_at', ascending: false);

// For detail query — fetch ALL columns including screenshot_base64
final row = await SupabaseConfig.client
    .from('bug_reports')
    .select('*')
    .eq('id', reportId)
    .single();
```

### Pattern 2: Dashboard Count Query
**What:** Aggregate counts from `bug_reports` grouped by `source_app`
**When to use:** Dashboard loading to populate per-product totals and unprocessed counts

```dart
// Single query returns both counts per product using PostgREST
// Note: PostgREST does not support GROUP BY directly — use two queries
// or count in Dart from a lightweight select

// Option A: Two targeted counts per product (simple, predictable)
final total = await SupabaseConfig.client
    .from('bug_reports')
    .select('id')
    .eq('source_app', productSlug)
    .count(CountOption.exact);

final unprocessed = await SupabaseConfig.client
    .from('bug_reports')
    .select('id')
    .eq('source_app', productSlug)
    .isFilter('github_issue_url', null)
    .count(CountOption.exact);
```

### Pattern 3: Pull-to-Refresh
**What:** Flutter `RefreshIndicator` widget that calls controller reload
**When to use:** Report list screen (LIST-04)

```dart
RefreshIndicator(
  onRefresh: () => controller.loadReports(productName),
  child: ListView.builder(...),
)
```

### Pattern 4: Screenshot Rendering in Detail
**What:** Decode base64 to bytes, render with Image.memory inside InteractiveViewer
**When to use:** Detail screen only (DETL-02)

```dart
import 'dart:convert';

final bytes = base64Decode(screenshotBase64);
InteractiveViewer(
  child: Image.memory(bytes),
)
```

### Pattern 5: ChangeNotifier Controller
**What:** Controller holds loading/error/data state, notifyListeners on change
**When to use:** All new controllers — matches AuthController pattern in Phase 1

```dart
class ReportListController extends ChangeNotifier {
  List<BugReportSummary> _reports = [];
  bool _isLoading = false;
  String? _error;

  List<BugReportSummary> get reports => _reports;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadReports(String productName) async {
    _isLoading = true;
    notifyListeners();
    try {
      // query...
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

### Anti-Patterns to Avoid
- **`select('*')` on bug_reports for list queries:** Every row has a 166–350 KB screenshot_base64. With 60 rows, a wildcard list query would fetch ~10–20 MB of base64 text over the network before any UI renders.
- **Decoding screenshot_base64 in the list layer:** Even if the column were fetched, calling base64Decode inside ListView.builder would stall the UI thread per item.
- **Navigator.push with raw Map:** Pass typed model objects, not raw `Map<String, dynamic>`, to avoid runtime key-access errors in screens.
- **Loading detail data in the list controller:** Keep list and detail controllers separate — detail fetch is expensive (includes screenshot).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pull-to-refresh | Custom scroll listener | Flutter `RefreshIndicator` | Built-in, handles all edge cases, matches Material spec |
| Zoomable image | Custom gesture detector | Flutter `InteractiveViewer` | SDK widget, handles pinch/pan/scale, no dep |
| Base64 decode | Custom decoder | `dart:convert` `base64Decode()` | Standard library, well-tested |
| Date formatting | String slicing | `intl` `DateFormat` | Already in pubspec; handles locale and timezone |

**Key insight:** This phase is pure read — Flutter SDK + supabase_flutter covers everything. No new packages needed.

## Common Pitfalls

### Pitfall 1: screenshot_base64 Fetched in List Query
**What goes wrong:** List appears to load (spinner disappears) then hangs or crashes; network traffic is enormous; UI freezes during parsing.
**Why it happens:** Forgetting to specify column projection when the natural reflex is `select('*')`.
**How to avoid:** Every `from('bug_reports')` call must have an explicit `.select(...)` with columns listed. Code review gate: grep for `.from('bug_reports').select('*')` — must never appear except in the detail fetch.
**Warning signs:** Report list takes >2s to load on a fast connection.

### Pitfall 2: source_app Does Not Match products.name
**What goes wrong:** Dashboard counts show 0 for all products even though reports exist.
**Why it happens:** `bug_reports.source_app` values are `"freecell"` and `"puzzle_nook"` — but `products.name` values are also `"freecell"` and `"puzzle_nook"`. These match, but if any future product adds reports with a different slug, counts silently drop to 0.
**How to avoid:** Join on `source_app = products.name` conceptually; treat products.name as the canonical slug for matching. Document this convention.
**Warning signs:** A product shows 0 reports when the Supabase console shows rows for that source_app.

### Pitfall 3: "Unprocessed" Definition Changes in Phase 3
**What goes wrong:** Phase 2 uses `github_issue_url IS NULL` as unprocessed proxy. Phase 3 adds a triage tag. After Phase 3, a report can be tagged "duplicate" (processed) but still have no GitHub URL — the proxy breaks.
**Why it happens:** Premature definition hardened into the dashboard query.
**How to avoid:** In the dashboard controller, define a named method `_isUnprocessed(report)` or a query filter that can be swapped in Phase 3. Add a comment: `// Phase 2 proxy: replace with triage_tag IS NULL in Phase 3`.
**Warning signs:** Dashboard counts don't match expected after triage is added.

### Pitfall 4: Detail Screen Blocking UI Thread on base64Decode
**What goes wrong:** Screen freezes for 1–2 seconds when opening a detail with a large screenshot.
**Why it happens:** `base64Decode()` of a 350 KB string is synchronous and runs on the main isolate.
**How to avoid:** Wrap decode in `compute()` or use `FutureBuilder` + `Future.microtask` to decode off the main thread. For a single-developer tool, even a brief spinner is acceptable, but do not call decode in `build()` directly.
**Warning signs:** Jank when navigating to detail screen.

### Pitfall 5: GetIt Controller Not Registered Before Use
**What goes wrong:** `GetIt.instance<ReportListController>()` throws `StateError: ReportListController is not registered`.
**Why it happens:** New controllers must be registered in `dependencies.dart` before screens try to resolve them.
**How to avoid:** Add registration to `configureDependencies()` as part of the same task that creates each controller.

## Code Examples

### Count Query with `CountOption.exact`
```dart
// Source: supabase-flutter docs — count() returns PostgrestCountResponse
final response = await SupabaseConfig.client
    .from('bug_reports')
    .select('id')
    .eq('source_app', 'freecell')
    .count(CountOption.exact);
final total = response.count; // int
```

### Null Filter for Unprocessed
```dart
// isFilter handles IS NULL in PostgREST
final response = await SupabaseConfig.client
    .from('bug_reports')
    .select('id')
    .eq('source_app', 'freecell')
    .isFilter('github_issue_url', null)
    .count(CountOption.exact);
```

### Column-Projected List Query
```dart
const listColumns = 'id, description, app_version, platform, created_at, github_issue_url, source_app';

final rows = await SupabaseConfig.client
    .from('bug_reports')
    .select(listColumns)
    .eq('source_app', productSlug)
    .order('created_at', ascending: false);
```

### Safe Navigation to Detail
```dart
// In ReportListScreen
Navigator.push(context, MaterialPageRoute(
  builder: (_) => ReportDetailScreen(reportId: summary.id),
));

// ReportDetailScreen fetches full data (including screenshot) on initState
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `select('*')` for all queries | Explicit column projection via select string | supabase-flutter has always supported this; discipline is new in this phase | Prevents 10–20 MB list payloads |
| Rendering base64 images via HTML widget | `dart:convert` + `Image.memory` | Flutter has always had this | No extra packages; no platform HTML bridge |

## Database Schema: Key Facts for Planning

**`bug_reports` table (60 rows, RLS confirmed):**
- Columns relevant to list: `id`, `description`, `app_version`, `platform`, `created_at`, `github_issue_url`, `source_app`
- Columns for detail only: `logs`, `device_info`, `screenshot_base64`, `user_id`
- `screenshot_base64`: present on ALL 60 rows; sizes 166–350 KB each
- `source_app` values in live data: `"freecell"` (46 reports), `"puzzle_nook"` (14 reports)
- `github_issue_url`: 52/60 rows have it; 8 rows are null (these are "unprocessed" in Phase 2)
- RLS policy: admin UUID `65ad7649-f551-4dc2-b6a4-f7a105b73d06` has full access; confirmed working after Phase 1

**`products` table (3 rows, public SELECT RLS):**
- Names: `freecell`, `issueinator`, `puzzle_nook`
- `issueinator` has no bug_reports (source_app never used by the tool itself)
- Dashboard should show 0 for issueinator gracefully

**`bug_report_triage` side table:** Does NOT exist yet. Phase 3 will create it. Phase 2 must not depend on it.

## Open Questions

1. **Dashboard: should `issueinator` product appear in the dashboard?**
   - What we know: It's in the `products` table with 0 bug reports.
   - What's unclear: Whether the developer wants to see it (with 0/0) or filter it out.
   - Recommendation: Show all products from the products table; 0/0 is honest. Easy to filter later.

2. **How to handle `source_app IS NULL` reports (legacy)?**
   - What we know: Current data has no null source_app rows, but schema allows it.
   - What's unclear: Whether legacy null-source_app reports should appear in any product list or a special "Unknown" category.
   - Recommendation: For Phase 2, filter to `source_app IS NOT NULL` in list queries. Dashboard shows only known products. Add a comment noting the decision.

3. **Screenshot decode performance: `compute()` or acceptable sync?**
   - What we know: Screenshots are 166–350 KB base64 strings. `base64Decode` is synchronous.
   - What's unclear: Whether a brief freeze is tolerable for a single-developer tool.
   - Recommendation: Start with synchronous decode in a `FutureBuilder`. If testing reveals jank, wrap in `compute()`. Flag as low-priority optimization.

## Sources

### Primary (HIGH confidence)
- Live Supabase schema (queried directly via MCP) — bug_reports columns, row counts, screenshot sizes, RLS policies
- Supabase live data query — source_app distribution, github_issue_url population, screenshot presence
- Existing codebase (read directly) — pubspec.yaml dependencies, AuthController pattern, dependencies.dart DI pattern, HomeScreen Supabase query pattern

### Secondary (MEDIUM confidence)
- supabase-flutter API patterns — `.count(CountOption.exact)`, `.isFilter()`, `.select()` column projection — based on existing usage in codebase and well-established supabase-flutter 2.x API
- Flutter SDK InteractiveViewer + Image.memory pattern — standard Flutter approach, training knowledge corroborated by existing dart:convert in pubspec

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages already in pubspec, patterns derived from existing Phase 1 code
- Architecture: HIGH — schema fully verified against live database, column sizes measured
- Pitfalls: HIGH — screenshot size risk verified with real data (all 60 rows have screenshots, 166–350 KB each)

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (schema is stable; supabase-flutter 2.x API is stable)
