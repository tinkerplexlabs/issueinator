# Pitfalls Research

**Domain:** Mobile bug triage tool — Flutter + Supabase + GitHub API integration
**Researched:** 2026-03-21
**Confidence:** MEDIUM (domain-specific pitfalls verified via official docs and multiple sources; some UX claims from community sources only)

---

## Critical Pitfalls

### Pitfall 1: Fetching screenshot_base64 in List Queries

**What goes wrong:**
The `bug_reports` table stores screenshots as base64-encoded strings directly in the column. When the list view fetches all columns (`select(*)`), every row in the list carries the full base64 payload — potentially hundreds of KB per row. Flutter's list will stall, memory spikes, and the Supabase dashboard itself becomes slow to scroll the table.

**Why it happens:**
The natural instinct is to fetch all columns so the detail view is pre-loaded. It works with small datasets and short strings, so no one notices until there are 50+ reports with screenshots.

**How to avoid:**
Always project specific columns in list queries — never `select(*)` on `bug_reports`. The list view needs only `id, source_app, description, platform, app_version, created_at, github_issue_url` and any triage columns. Fetch `screenshot_base64` only on the detail screen for the single selected report.

```dart
// BAD — pulls entire base64 payload for every row
supabase.from('bug_reports').select();

// GOOD — list view projection
supabase.from('bug_reports').select(
  'id, source_app, description, platform, app_version, created_at, github_issue_url'
);
```

**Warning signs:**
- List scroll performance degrades as report count grows
- Network payload for list fetch is unexpectedly large (check DevTools)
- Supabase dashboard table view loads slowly

**Phase to address:**
Bug report list view implementation — establish the projection pattern before the first working list screen. Do not fix this as a performance pass later.

---

### Pitfall 2: GitHub Issue Created Twice on Network Retry

**What goes wrong:**
The GitHub Issues API `POST /repos/{owner}/{repo}/issues` is not idempotent. If the user taps "Sync to GitHub" and the network drops after the request reaches GitHub but before the 201 response returns to the app, the app shows an error and the user retries. GitHub creates a second duplicate issue. The app now has no `github_issue_url` stored and the user has no way to know a duplicate was created.

**Why it happens:**
GitHub's REST API has no built-in idempotency key mechanism for issue creation. Mobile networks (especially when a developer is using the app on a phone) are unreliable. Optimistic retry without duplicate detection causes this.

**How to avoid:**
Before creating a GitHub issue, query GitHub's search API (`GET /search/issues?q=repo:{owner}/{repo}+{fingerprint}`) using a deterministic fingerprint embedded in the issue title or body (e.g., `[issueinator:{report_id}]`). If a matching issue already exists, link to it rather than creating a new one. Store `github_issue_url` in Supabase atomically with the API call — if the Supabase write fails after GitHub creation, the fingerprint search rescues the next attempt.

**Warning signs:**
- Error handling shows "sync failed" but GitHub repo has the issue
- Reports have `null` github_issue_url but corresponding GitHub issues exist
- User sees "create" succeed after retry but two identical issues appear in GitHub

**Phase to address:**
GitHub sync implementation phase. This must be designed before writing any sync code — retrofitting idempotency is painful.

---

### Pitfall 3: RLS Blocks All Data Until Google Sign-In Completes

**What goes wrong:**
The app currently uses anonymous auth. The `bug_reports` table RLS restricts SELECT to the admin UUID (`65ad7649-...`). Any query made before Google Sign-In resolves — including queries made during app startup, splash screen, or after hot-restart in development — returns zero rows with no error (RLS returns empty, not 403). This looks like "no data" rather than "auth not ready," causing confusing debugging sessions.

**Why it happens:**
Supabase RLS silently filters rows rather than throwing auth errors. An anonymous session IS a valid session, so the Supabase client doesn't error — it just returns nothing. The distinction between "no reports exist" and "you can't see reports yet" is invisible.

**How to avoid:**
Gate all `bug_reports` queries behind an `isAuthenticated` check that verifies the session user ID matches the admin UUID. Show a "Sign in required" state rather than an empty list. Implement auth state listener before initializing any Supabase data fetches. Pattern: copy FreeCell's Google Sign-In implementation first, verify identity, then initialize data layer.

**Warning signs:**
- List shows empty during development even when reports exist in Supabase
- No error thrown when querying before auth
- Hot-restart clears session and list appears empty until manually re-authenticated

**Phase to address:**
Google Sign-In migration phase (the first active requirement). This must be completed before any feature that reads `bug_reports`.

---

### Pitfall 4: Adding Triage Columns Without a Migration Plan Breaks Other TinkerPlex Apps

**What goes wrong:**
The `bug_reports` table is shared across all TinkerPlex game apps (the games submit reports to it). Adding new columns for triage state (`triage_tag`, `triage_comment`, `linked_duplicate_id`) can break game app clients that use `select(*)` if those clients error on unexpected columns, or can violate constraints if DEFAULT values aren't specified. Even if the game clients aren't broken today, the shared schema is a coordination surface that requires deliberate change management.

**Why it happens:**
IssueInator is developer-facing and feels "separate" from the game apps, so schema changes seem safe to make freely. In reality, all apps share the same Postgres instance.

**How to avoid:**
Use additive-only schema changes with explicit DEFAULT values and nullable columns so existing game app clients see no change. Prefer a separate `bug_report_triage` table with a foreign key to `bug_reports.id` over adding columns to the main table — this keeps game-app-facing schema untouched entirely. Document any schema change in the monorepo's ADR or shared schema notes before applying it.

**Warning signs:**
- You're adding a NOT NULL column without a DEFAULT
- You're renaming or removing existing columns
- Game app tests start failing after a schema change

**Phase to address:**
Database schema design phase (before writing any triage storage code). Decide: extend `bug_reports` with nullable columns, or create a `bug_report_triage` side table.

---

### Pitfall 5: GitHub Device Flow Token Expiry Silently Breaks Sync

**What goes wrong:**
GitHub Device Flow tokens can expire or be revoked (user revokes app access in GitHub settings, token scope changes, or the token hits its expiry). When `POST /repos/.../issues` returns 401, the app has no recovery path if it treats the GitHub token as permanent. The sync button appears to do nothing or shows a cryptic error.

**Why it happens:**
Device Flow is implemented at app startup and works. Developers assume "once authed, always authed" because they don't revoke their own tokens during development. The failure mode only appears in production use or after long gaps between triage sessions.

**How to avoid:**
Check HTTP 401 responses from GitHub API and trigger a re-authentication flow (re-run Device Flow) rather than showing a generic error. Store token expiry metadata alongside the token in `flutter_secure_storage` if the Device Flow response includes `expires_in`. Implement a token validation check (e.g., `GET /user`) before any sync operation if the last successful API call was more than N hours ago.

**Warning signs:**
- GitHub sync returns 401 after working previously
- Token stored in secure storage but API calls fail
- No re-auth prompt shown on failure

**Phase to address:**
GitHub sync implementation phase. Verify the existing Device Flow implementation handles 401 refresh before adding sync features.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `select(*)` on bug_reports in list view | Simpler query code, detail data pre-loaded | Memory exhaustion as screenshot_base64 rows accumulate; list lag | Never — always project columns |
| Hardcoding admin UUID in client code | Simple auth check | UUID leaks into source control; brittle if admin account changes | Never — read from config or derive from session |
| Storing triage state in local app memory only (no Supabase persistence) | Fast prototyping | Triage work lost on app restart | MVP scaffold only — must persist before calling feature complete |
| Single ChangeNotifier for all bug reports + all triage state | Fewer classes | Unrelated UI rebuilds on every notifyListeners() call; subtle performance issues with 50+ reports | Only during initial scaffolding — split by feature scope |
| No pagination — fetch all bug_reports at once | Simpler list code | Supabase default 1,000-row limit will silently truncate; all 53+ rows fetched on every screen open | Only if report count is verifiably small and bounded |

---

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| GitHub Issues API | Creating issues without storing `html_url` back to Supabase atomically | Write `github_issue_url` to Supabase immediately after 201 response; treat failure to write as a recoverable error needing retry |
| GitHub Issues API | Not checking secondary rate limits (80 content-creating requests/minute) | For batch sync operations, add delay between issue creates; check `X-RateLimit-Remaining` header |
| GitHub Search API | Using full description text in search query | Use a deterministic fingerprint (`[issueinator:{id}]`) in issue body; search by that token, not free text |
| Supabase RLS | Testing queries in the Supabase Dashboard SQL editor | SQL editor runs as service_role and bypasses RLS — always test data access through the Flutter Supabase client |
| Supabase Realtime | Subscribing to `bug_reports` changes in a ChangeNotifier without unsubscribing | Call `removeChannel()` or `unsubscribe()` in the ChangeNotifier's `dispose()` method — otherwise WebSocket connections accumulate |
| flutter_secure_storage | Reading token synchronously at startup | Read is async I/O; await it properly or app reads stale null and starts in unauthed state |

---

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Fetching all columns including screenshot_base64 in list | List scroll stutters; memory spike | Project only needed columns in list queries | ~10 reports with screenshots |
| Re-fetching full report list after every triage action | UI flickers; feels slow; unnecessary network calls | Optimistic local state update + background sync pattern | ~20+ reports in list |
| Calling `notifyListeners()` from the root ChangeNotifier on every triage tag change | Entire screen tree rebuilds including unchanged list items | Separate notifiers per concern (list state vs. selected report state vs. triage form state) | ~30+ reports visible |
| No pagination on bug_reports query | Supabase silently caps at 1,000 rows; old reports invisible | Use `.range(from, to)` with pagination controls | 1,001st report submitted |

---

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing GitHub OAuth token in SharedPreferences | Token readable by other apps on rooted device; token visible in Android backup | Always use flutter_secure_storage (Keychain on iOS, EncryptedSharedPreferences on Android) |
| Hardcoding admin UUID (`65ad7649-...`) as a string constant in Dart source | UUID committed to source control and visible in compiled binary; RLS bypass if UUID leaks | Store in build config or derive from authenticated session — never compare raw hardcoded UUID strings |
| Using Supabase service_role key in the Flutter app | Bypasses all RLS — any user with network access and the key can read/write all tables | Never embed service_role key in client; use anon key + RLS. Admin access comes from Google Sign-In as the admin UUID |
| Embedding GitHub token in plain error messages shown to user | Token leaks in screenshots or crash reports | Redact tokens from error display strings; log only token prefix (first 4 chars) for debugging |

---

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No "sync in progress" indicator during GitHub issue creation | User taps sync again thinking it didn't work, creating duplicate issues | Disable sync button + show progress indicator during API call; block re-tap until resolved |
| Empty list with no distinction between "no reports" and "auth failed" | Developer thinks app is working when it's not authenticated | Show explicit auth state: "Sign in required" vs. "No reports yet" vs. loading spinner |
| "Dismiss" without requiring a reason | Six months later, no record of why reports were dismissed | Require selection from reason list (spam / works-as-designed / duplicate / test report) before dismissal completes |
| Batch tag UI that requires per-report confirmation | Batch operations feel slower than doing one at a time | Batch operations should apply tag immediately with a single "Confirm batch tag X reports?" step |
| GitHub sync status not reflected in report list | Developer can't tell at a glance which reports are synced vs. pending | Show `github_issue_url` presence as a visual indicator (icon, badge) in the list row |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Google Sign-In:** Often missing session persistence — verify the session survives app cold start, not just hot restart
- [ ] **Bug report list:** Often missing column projection — verify `screenshot_base64` is NOT included in list query payload
- [ ] **GitHub sync:** Often missing the Supabase write-back — verify `github_issue_url` is stored after issue creation, not just that the GitHub issue appears
- [ ] **Triage tags:** Often missing persistence — verify tag state survives app restart (it's in Supabase, not just in-memory ChangeNotifier)
- [ ] **Duplicate detection:** Often only checks local in-memory list — verify it queries GitHub Search API for issues already synced from other sessions
- [ ] **Device Flow re-auth:** Often missing 401 recovery — verify a revoked GitHub token triggers re-authentication, not a silent no-op
- [ ] **Pagination:** Often assumed complete when list shows data — verify behavior with the `.range()` query when more than 50 reports exist
- [ ] **Supabase subscription cleanup:** Often missing — verify ChangeNotifiers that subscribe to Realtime call `removeChannel()` in dispose

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Duplicate GitHub issues created by retry | LOW | Search GitHub for `[issueinator:{report_id}]`, close duplicate manually, update `github_issue_url` in Supabase via SQL editor |
| screenshot_base64 in list queries causing memory issues | LOW | Add column projection to query; no data migration needed |
| Triage state stored only in memory (lost on restart) | HIGH | Must add Supabase triage table and migration; re-triage all previously processed reports |
| Service_role key embedded in app | HIGH | Rotate key in Supabase immediately; rebuild and redeploy all TinkerPlex game apps referencing old anon key (if accidentally swapped) |
| Schema change breaks game app clients | MEDIUM | Revert migration via Supabase dashboard; create a new additive-only migration; re-deploy |
| Supabase realtime subscription leak | LOW | Identify leaked channels via Supabase dashboard; fix dispose in code; hot restart clears leaks in dev |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| RLS blocks data until Google Sign-In | Google Sign-In migration (Phase 1) | Verify: cold-start app, query returns data only after successful Google auth |
| screenshot_base64 in list queries | Bug report list view (Phase 2) | Verify: network payload for list fetch contains no base64 strings; check via Flutter DevTools network tab |
| Additive-only schema changes | Schema design before triage feature (Phase 2/3 boundary) | Verify: existing game app integration tests still pass after migration |
| Duplicate GitHub issues on retry | GitHub sync design (Phase 4) | Verify: simulate network failure mid-sync; re-running sync links to existing issue rather than creating new one |
| Device Flow token expiry | GitHub sync implementation (Phase 4) | Verify: manually revoke token in GitHub settings; confirm app shows re-auth prompt, not silent failure |
| Supabase realtime subscription leak | Any phase using Realtime (Phase 3+) | Verify: navigate away from report list and back 10 times; check Supabase dashboard for duplicate channel registrations |
| No pagination | Bug report list view (Phase 2) | Verify: query uses `.range()` not unlimited fetch; check behavior when count > 50 |

---

## Sources

- [GitHub REST API rate limits — official docs](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) — HIGH confidence
- [GitHub rate limits for OAuth apps](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/rate-limits-for-oauth-apps) — HIGH confidence
- [Supabase Row Level Security — official docs](https://supabase.com/docs/guides/database/postgres/row-level-security) — HIGH confidence
- [Supabase RLS misconfigurations pitfalls](https://prosperasoft.com/blog/database/supabase/supabase-rls-issues/) — MEDIUM confidence (community source, consistent with official docs)
- [Supabase base64 column performance issue (GitHub #20998)](https://github.com/supabase/supabase/issues/20998) — MEDIUM confidence (official issue tracker)
- [flutter_secure_storage — pub.dev](https://pub.dev/packages/flutter_secure_storage) — HIGH confidence
- [Supabase Realtime memory leak diagnosis](https://drdroid.io/stack-diagnosis/supabase-realtime-client-side-memory-leak) — MEDIUM confidence (community, consistent with Supabase docs pattern)
- [GitHub idempotency and POST requests](https://www.databasesandlife.com/idempotency/) — MEDIUM confidence (community source)
- [Supabase offline and pagination limits](https://github.com/supabase/supabase-flutter/issues/1039) — MEDIUM confidence (official issue tracker)
- [GetIt common mistakes — LogRocket](https://blog.logrocket.com/dependency-injection-flutter-using-getit-injectable/) — LOW confidence (community blog, single source)

---
*Pitfalls research for: IssueInator — mobile bug triage tool (Flutter + Supabase + GitHub)*
*Researched: 2026-03-21*
