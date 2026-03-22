# Phase 3: Triage Actions - Research

**Researched:** 2026-03-22
**Domain:** Supabase schema migration (side table) + Flutter write path + multi-select UI
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TRIA-01 | Developer can tag a report with one of: issue / feedback / duplicate / not-a-bug / needs-info; tag persists after app restart | Side table `bug_report_triage` holds the tag; upsert on tag change; confirmed admin UUID has ALL policy on `bug_reports`, same policy must cover the new table |
| TRIA-02 | Developer can add a text comment to a report; comment appears on subsequent visits | `comment` column on `bug_report_triage` (same side table); shown in detail view on re-load |
| TRIA-03 | Developer can select multiple reports and batch-tag them | Multi-select mode in `ReportListScreen` + `ReportListController`; batch upsert via Supabase `.upsert()` with a list of rows |
| TRIA-04 | Reports tagged "duplicate" are visually excluded from GitHub sync (no button shown or disabled) | Detail screen already has a stub triage chip (Phase 2 TODO comment); suppress sync button when `triageTag == 'duplicate'` |
</phase_requirements>

---

## Summary

Phase 3 is a write-path phase sitting directly on top of the read path built in Phase 2. The key architectural decision was made pre-work (logged in STATE.md): **use a `bug_report_triage` side table rather than adding columns to `bug_reports`**. This is the correct call — `bug_reports` is a shared schema table owned by game apps; adding columns could break those apps' RLS or column expectations.

The side table pattern requires one Supabase migration (CREATE TABLE + RLS policy), one upsert method on `BugReportRepository`, and then Flutter UI work across three touch points: the detail screen (tag picker + comment field), the list screen (multi-select mode), and the dashboard unprocessed count (swap Phase 2 proxy for real `triage_tag IS NULL` check).

The admin RLS on `bug_reports` uses the UUID `a672276e-b2bd-403e-912c-040251c1063f` (verified live — this is the actual UUID in the policy, NOT the `65ad7649` value mentioned in some planning docs; STATE.md records the correction made in 02-03). The side table RLS policy must use the same UUID.

Batch tagging (TRIA-03) is the only non-trivial UI feature. Supabase's Dart client supports `.upsert(List<Map>)` natively, so the data layer is straightforward. The UI complexity is in multi-select state management: a `Set<String>` of selected report IDs lives in `ReportListController`, a checkbox appears per list item when in selection mode, and a bottom action bar with a "Tag selected" button appears when selection is non-empty.

**Primary recommendation:** Create the `bug_report_triage` side table first (migration task), then implement the single-report write path (TRIA-01 + TRIA-02), then add multi-select on top of the working write path (TRIA-03), then wire the duplicate exclusion check (TRIA-04). Sequential dependency — each step builds on the previous.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `supabase_flutter` | `^2.0.0` (already in pubspec) | `.upsert()` for tag write, `.select()` for tag read alongside report data | Already present; no new packages needed for this phase |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Flutter `showModalBottomSheet` | framework built-in | Tag picker UI — 5 options displayed as `ListTile`s | Single-report tagging from detail screen |
| Flutter `BottomAppBar` or `SnackBar`-style overlay | framework built-in | Batch action bar in list multi-select mode | Appears when `selectedIds.isNotEmpty` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Side table `bug_report_triage` | Add `triage_tag`, `comment` columns to `bug_reports` | Side table is correct — shared schema safety. Already decided pre-work. Do not revisit. |
| Supabase `.upsert()` | Two-step check-then-insert | `.upsert()` with `onConflict: 'report_id'` is atomic and idempotent. No race condition. |
| Modal bottom sheet for tag picker | `DropdownButton` inline | Bottom sheet is finger-friendly on mobile, works cleanly in detail view without cluttering layout |

**Installation:** No new packages required.

---

## Architecture Patterns

### Files to Create

```
lib/
├── domain/models/bug_report_triage.dart          # NEW: TriageTag enum + BugReportTriage model
├── application/controllers/triage_controller.dart # NEW: tag + comment write operations
```

### Files to Modify

```
lib/
├── infrastructure/repositories/bug_report_repository.dart  # ADD: upsert triage, fetch triage
├── presentation/screens/report_detail_screen.dart          # ADD: tag picker, comment field, show current triage
├── presentation/screens/report_list_screen.dart            # ADD: multi-select mode, triage status chip
├── config/dependencies.dart                                 # ADD: TriageController registration
```

### Database Migration (Wave 0 prerequisite)

```sql
-- bug_report_triage side table
CREATE TABLE public.bug_report_triage (
  report_id   uuid PRIMARY KEY REFERENCES public.bug_reports(id) ON DELETE CASCADE,
  triage_tag  text CHECK (triage_tag IN ('issue','feedback','duplicate','not-a-bug','needs-info')),
  comment     text,
  triaged_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- RLS: only the developer admin can read/write
ALTER TABLE public.bug_report_triage ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Developer admin: full access to bug_report_triage"
  ON public.bug_report_triage
  FOR ALL
  TO authenticated
  USING  (auth.uid() = 'a672276e-b2bd-403e-912c-040251c1063f'::uuid)
  WITH CHECK (auth.uid() = 'a672276e-b2bd-403e-912c-040251c1063f'::uuid);
```

**Critical:** The admin UUID in the policy is `a672276e-b2bd-403e-912c-040251c1063f` — confirmed from live `pg_policies` query on the `bug_reports` table (2026-03-22). Do NOT use the `65ad7649` UUID mentioned in earlier planning docs; that was superseded in 02-03.

### Pattern 1: TriageTag enum + BugReportTriage model

```dart
// lib/domain/models/bug_report_triage.dart
enum TriageTag {
  issue('issue', 'Issue'),
  feedback('feedback', 'Feedback'),
  duplicate('duplicate', 'Duplicate'),
  notABug('not-a-bug', 'Not a Bug'),
  needsInfo('needs-info', 'Needs Info');

  const TriageTag(this.value, this.label);
  final String value;
  final String label;

  static TriageTag? fromValue(String? value) =>
      value == null ? null : TriageTag.values.firstWhere((t) => t.value == value, orElse: () => throw ArgumentError('Unknown tag: $value'));
}

class BugReportTriage {
  final String reportId;
  final TriageTag? tag;
  final String? comment;
  final DateTime? updatedAt;

  const BugReportTriage({required this.reportId, this.tag, this.comment, this.updatedAt});

  factory BugReportTriage.fromJson(Map<String, dynamic> json) {
    return BugReportTriage(
      reportId: json['report_id'] as String,
      tag: TriageTag.fromValue(json['triage_tag'] as String?),
      comment: json['comment'] as String?,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
    );
  }
}
```

### Pattern 2: Upsert single triage record

```dart
// In BugReportRepository
Future<void> saveTriage(String reportId, {String? tag, String? comment}) async {
  await SupabaseConfig.client
      .from('bug_report_triage')
      .upsert({
        'report_id': reportId,
        if (tag != null) 'triage_tag': tag,
        if (comment != null) 'comment': comment,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'report_id');
}

Future<BugReportTriage?> getTriageForReport(String reportId) async {
  final rows = await SupabaseConfig.client
      .from('bug_report_triage')
      .select('report_id, triage_tag, comment, updated_at')
      .eq('report_id', reportId);
  if (rows.isEmpty) return null;
  return BugReportTriage.fromJson(rows.first);
}
```

### Pattern 3: Batch upsert for multi-select

```dart
Future<void> batchSaveTriage(List<String> reportIds, String tag) async {
  final rows = reportIds.map((id) => {
    'report_id': id,
    'triage_tag': tag,
    'updated_at': DateTime.now().toIso8601String(),
  }).toList();

  await SupabaseConfig.client
      .from('bug_report_triage')
      .upsert(rows, onConflict: 'report_id');
}
```

### Pattern 4: Multi-select state in ReportListController

```dart
// Add to ReportListController:
final Set<String> _selectedIds = {};
bool _isSelectionMode = false;

Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
bool get isSelectionMode => _isSelectionMode;

void enterSelectionMode(String firstId) {
  _isSelectionMode = true;
  _selectedIds.add(firstId);
  notifyListeners();
}

void toggleSelection(String reportId) {
  if (_selectedIds.contains(reportId)) {
    _selectedIds.remove(reportId);
    if (_selectedIds.isEmpty) _isSelectionMode = false;
  } else {
    _selectedIds.add(reportId);
  }
  notifyListeners();
}

void clearSelection() {
  _selectedIds.clear();
  _isSelectionMode = false;
  notifyListeners();
}

Future<void> batchTag(String tag, BugReportRepository repo) async {
  await repo.batchSaveTriage(_selectedIds.toList(), tag);
  clearSelection();
  await refresh();
}
```

### Pattern 5: Update unprocessed count proxy in Phase 3

Two places use the Phase 2 proxy (`github_issue_url IS NULL`). Both must be updated to join/filter on `bug_report_triage`:

**`BugReportRepository.getProductCounts()`** — switch unprocessed filter:
```dart
// Phase 3: replace .isFilter('github_issue_url', null) with:
// Reports with no triage row OR triage_tag IS NULL
// Simplest correct approach: count total minus count(triage rows with non-null tag)
// OR: use a subquery / view. Easiest in Supabase client: count reports NOT IN (SELECT report_id FROM bug_report_triage WHERE triage_tag IS NOT NULL)
// Since Supabase Dart client does not support NOT IN with subquery natively,
// fetch triage'd IDs separately and subtract from total, OR use a Postgres view.
```

**Resolution:** Because the Supabase Dart client cannot express `NOT IN (subquery)` natively, the cleanest approach is a two-query strategy: fetch total count + fetch count where report id IS in triage table with a non-null tag, then compute unprocessed = total - tagged. See Pitfall 2.

**`ReportListScreen`** — list item triage status chip: the `BugReportSummary` model must include triage state. Options:
1. Fetch triage rows for the product in a second query and zip them with the summary list (preferred — keeps `bug_reports` column projection intact)
2. Add a Postgres view that joins the two tables

Option 1 is simpler and avoids schema changes. `BugReportSummary` gets an optional `triageTag` field populated from a parallel triage fetch.

### Anti-Patterns to Avoid

- **Don't add `triage_tag` or `comment` to `bug_reports` directly.** Shared schema safety. Decision is locked. The side table is the correct path.
- **Don't use `.update()` for triage writes.** Use `.upsert()` — the first triage of a report has no existing row. `.update()` would silently do nothing if the row doesn't exist yet.
- **Don't load all triage rows for a product in the detail screen.** Fetch triage for a single report by `report_id` only.
- **Don't block batch tag on UI thread.** Wrap in `try/finally`, show a loading indicator in the bottom action bar, and handle errors gracefully.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Idempotent tag write | Check-then-insert/update manually | `.upsert(onConflict: 'report_id')` | Atomic, handles first-time and re-tag in one call |
| Batch upsert | Loop of individual upserts | `.upsert(List<Map>)` | Single network round-trip regardless of batch size |
| Tag picker UI | Custom dropdown widget | `showModalBottomSheet` with `ListTile` per tag | Zero dependencies, finger-friendly, Flutter standard |

**Key insight:** The Supabase Dart client's `.upsert()` accepts a `List<Map>` — batch operations are a single call, not a loop.

---

## Common Pitfalls

### Pitfall 1: Wrong admin UUID in RLS policy

**What goes wrong:** Triage upsert silently fails (RLS blocks write, Supabase returns empty error or 403). Tags appear to save but reload shows "Not yet triaged."

**Why it happens:** RLS policy uses `a672276e-b2bd-403e-912c-040251c1063f`. Earlier planning docs reference `65ad7649-f551-4dc2-b6a4-f7a105b73d06`. If the migration uses the wrong UUID, the admin cannot write to the table.

**How to avoid:** The migration SQL above uses `a672276e-b2bd-403e-912c-040251c1063f` — this was verified live from `pg_policies` on `bug_reports` on 2026-03-22. Use this exact UUID. Cross-check with STATE.md note "[02-03]: Admin UUID updated to tinkertestautomation@gmail.com."

**Warning signs:** No Supabase client error is thrown — RLS USING violations on INSERT/UPDATE return empty results, not exceptions, by default.

### Pitfall 2: Unprocessed count cannot use NOT IN subquery via Dart client

**What goes wrong:** Developer tries to write a single Supabase Dart query for "bug reports where no triage row exists" — the client does not support `NOT IN (SELECT ...)` syntax.

**Why it happens:** The Supabase Dart client's `.filter()` methods map to PostgREST query params which do not support nested subqueries.

**How to avoid:** Use a two-query strategy in `getProductCounts()`:
1. Count total reports for product
2. Count triage rows for that product where `triage_tag IS NOT NULL`
3. `unprocessedCount = totalCount - taggedCount`

Alternatively, create a Postgres view `bug_report_triage_summary` that pre-joins for dashboard counts. The two-query approach requires no schema changes and is simpler for a single-developer app.

**Warning signs:** Compile error or PostgREST 400 when trying to chain `.not('id', 'in', subquery)`.

### Pitfall 3: Triage data not refreshed after write

**What goes wrong:** Developer tags a report, navigates back to detail screen, sees "Not yet triaged" because the detail screen fetched on mount and cached state.

**Why it happens:** `ReportDetailScreen` fetches detail in `initState`. The triage state is a separate fetch. After a write, neither is automatically invalidated.

**How to avoid:** After a successful triage upsert, call `_fetchTriage()` from within `_ReportDetailScreenState` (or re-navigate with a result that triggers re-fetch). The simplest pattern: `Navigator.pop(context, true)` from the tag picker, and the detail screen re-fetches on `true` return.

**Warning signs:** Tag appears saved (no error) but stale chip is displayed on the next visit.

### Pitfall 4: Multi-select state persists across product navigation

**What goes wrong:** Developer selects reports in product A, navigates to product B — the previous selection is still active in `ReportListController`.

**Why it happens:** `ReportListController` is a singleton in GetIt. Its `_selectedIds` set is not cleared when `loadReports()` is called for a new product.

**How to avoid:** Call `clearSelection()` at the start of `loadReports()`. The selection is always product-scoped.

**Warning signs:** Bottom action bar appears immediately when entering a new product list.

### Pitfall 5: upsert without updated_at causes stale timestamp

**What goes wrong:** Triage row `updated_at` never changes on re-tag because the Postgres default (`now()`) only applies on INSERT, not on upsert conflict update.

**Why it happens:** Supabase `.upsert()` performs `ON CONFLICT DO UPDATE SET ...` with only the columns provided. If `updated_at` is not included in the upsert payload, the existing value is kept.

**How to avoid:** Always include `'updated_at': DateTime.now().toIso8601String()` in the upsert map (shown in code examples above).

---

## Code Examples

### Fetch triage alongside report list (parallel query pattern)

```dart
// Source: project pattern — parallel fetch + zip
Future<List<BugReportSummary>> getReportsByProductWithTriage(String productName) async {
  final reportsFuture = SupabaseConfig.client
      .from('bug_reports')
      .select('id, description, app_version, platform, created_at, github_issue_url, source_app')
      .eq('source_app', productName)
      .order('created_at', ascending: false);

  final triageFuture = SupabaseConfig.client
      .from('bug_report_triage')
      .select('report_id, triage_tag')
      // No filter needed — RLS limits to admin; fetch all and zip
      ;

  final results = await Future.wait([reportsFuture, triageFuture]);
  final reports = (results[0] as List).cast<Map<String, dynamic>>();
  final triageList = (results[1] as List).cast<Map<String, dynamic>>();

  final triageByReportId = {
    for (final t in triageList) t['report_id'] as String: t['triage_tag'] as String?
  };

  return reports.map((row) {
    final summary = BugReportSummary.fromJson(row);
    // attach triage tag — BugReportSummary needs triageTag field
    return summary.copyWith(triageTag: triageByReportId[row['id']]);
  }).toList();
}
```

Note: `BugReportSummary` needs a `triageTag` field and `copyWith` added in Phase 3.

### Tag picker bottom sheet (detail screen)

```dart
void _showTagPicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Apply Triage Tag', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...TriageTag.values.map((tag) => ListTile(
            leading: _tagIcon(tag),
            title: Text(tag.label),
            onTap: () {
              Navigator.pop(context);
              _applyTag(tag);
            },
          )),
        ],
      ),
    ),
  );
}
```

### Duplicate exclusion in detail screen (TRIA-04)

```dart
// In _buildStatusBar — only show sync action when tag is NOT duplicate
if (_triage?.tag != TriageTag.duplicate)
  FilledButton.icon(
    onPressed: _syncToGitHub, // Phase 4 stub for now
    icon: const Icon(Icons.sync),
    label: const Text('Sync to GitHub'),
  )
else
  const Chip(label: Text('Duplicate — excluded from GitHub sync')),
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `github_issue_url IS NULL` as unprocessed proxy | `triage_tag IS NULL` (no triage row or null tag) | Phase 3 | Two places update: `getProductCounts()` and `ReportListScreen` list item chip |
| Hardcoded "Not yet triaged" chip in detail screen | Live triage from `bug_report_triage` | Phase 3 | Phase 2 TODO comment in `_buildStatusBar` is the exact hook point |

**Phase 2 TODO hooks (exact locations to wire):**
- `report_list_screen.dart` line 75: `// Phase 2 proxy: replace with triage tag display in Phase 3`
- `report_detail_screen.dart` line 165: `// Phase 3: replace with actual triage tag from bug_report_triage table`
- `bug_report_repository.dart` line 12: `// Phase 2 proxy: replace with triage_tag IS NULL in Phase 3`
- `bug_report_repository.dart` line 24: `// Phase 2 proxy: replace with triage_tag IS NULL in Phase 3`

---

## Open Questions

1. **Triage fetch scope for the product list**
   - What we know: `bug_report_triage` will have rows for all triaged reports across all products. A query with no `source_app` filter will return ALL triage rows.
   - What's unclear: At 61 reports total (growing slowly), fetching all triage rows and filtering in-memory is acceptable. At scale it becomes a problem.
   - Recommendation: Fetch all triage rows in one call (no filter) for Phase 3 — the table is tiny. Add `source_app` column to `bug_report_triage` or use a join if the table grows beyond ~500 rows.

2. **Comment field UX: inline edit vs. dialog**
   - What we know: TRIA-02 requires a text comment; no UX decision has been locked.
   - What's unclear: Whether inline editing (TextField in detail screen) or a separate dialog is preferred.
   - Recommendation: Inline `TextField` with a "Save comment" button in the detail screen — simpler, no modal management needed, aligns with the app's single-developer developer-tool character.

3. **Batch tag from list: does selection need to survive a refresh?**
   - What we know: TRIA-03 requires batch tagging but does not specify whether selection survives a pull-to-refresh.
   - What's unclear: If refresh clears selection, the developer loses their selected set.
   - Recommendation: Clear selection on refresh — safer UX. If the developer refreshes mid-selection, the tags will show updated state. Selection is cheap to re-establish.

---

## Sources

### Primary (HIGH confidence)

- Live Supabase `pg_policies` query on `bug_reports` (2026-03-22) — confirmed admin UUID `a672276e-b2bd-403e-912c-040251c1063f`
- Live Supabase `list_tables` on `public` schema (2026-03-22) — confirmed `bug_report_triage` does NOT yet exist; `bug_reports` column list is authoritative
- `/home/daniel/work/tinkerplexlabs/demos/issueinator/lib/infrastructure/repositories/bug_report_repository.dart` — existing query patterns, Phase 2 proxy comments
- `/home/daniel/work/tinkerplexlabs/demos/issueinator/lib/presentation/screens/report_detail_screen.dart` — Phase 3 TODO hook at line 165
- `/home/daniel/work/tinkerplexlabs/demos/issueinator/lib/presentation/screens/report_list_screen.dart` — Phase 3 TODO hook at line 75
- `/home/daniel/work/tinkerplexlabs/demos/issueinator/lib/application/controllers/report_list_controller.dart` — base for multi-select additions
- `/home/daniel/work/tinkerplexlabs/demos/issueinator/.planning/STATE.md` — admin UUID correction (02-03), side table decision (pre-work)

### Secondary (MEDIUM confidence)

- Supabase Dart client `.upsert()` behavior — confirmed via project usage pattern in existing repository code; `onConflict` parameter is standard PostgREST behavior

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; existing `supabase_flutter` covers all write operations
- Architecture: HIGH — side table decision locked in STATE.md; RLS UUID verified live; Phase 2 TODO hooks are exact line references in existing code
- Pitfalls: HIGH — derived from direct code inspection, live schema query, and documented STATE.md decisions
- Multi-select UI pattern: HIGH — standard Flutter patterns, no third-party dependencies

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable stack; Supabase schema confirmed live)
