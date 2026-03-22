# Project Research Summary

**Project:** IssueInator
**Domain:** Internal developer bug triage tool — Flutter + Supabase + GitHub Issues integration
**Researched:** 2026-03-21
**Confidence:** HIGH (existing codebase examined directly; official API docs verified)

## Executive Summary

IssueInator is a single-admin mobile tool that converts raw bug reports from five TinkerPlex game apps into triaged GitHub issues. The product already has a working scaffold (Device Flow GitHub auth, anonymous Supabase auth, Flutter Material 3 dark theme) but is missing its entire core feature set: the ability to read bug reports, tag them, comment on them, and push them to GitHub. The new milestone is a targeted build-out, not a greenfield project — every technology decision extends what already exists rather than introducing something new.

The recommended approach follows the existing TinkerPlex clean architecture: domain models and abstract interfaces first, then infrastructure implementations (Supabase repository, GitHub service), then controllers (ChangeNotifier via Provider), then screens. The single most important prerequisite is replacing the current anonymous Supabase auth with Google Sign-In — Row Level Security on the `bug_reports` table silently blocks all data reads until the admin UUID is authenticated. Nothing else can be built or tested until this gate is open. After auth is working, the build proceeds in a natural dependency chain: read reports, then tag them, then sync to GitHub.

The primary risks are narrow but sharp. First, a non-idempotent GitHub Issues API means a network retry during sync can create duplicate issues — this must be designed with a fingerprint-based dedup check before writing any sync code. Second, the `bug_reports` table is shared with all five game apps, so any schema change must be additive-only with nullable columns and DEFAULT values. Third, fetching `screenshot_base64` in list queries will degrade performance quickly — column projection must be established at the first list screen and never relaxed.

## Key Findings

### Recommended Stack

The stack is substantially already in place. Three packages need to be added (`google_sign_in ^7.2.0`, `flutter_markdown_plus ^1.0.7`, `photo_view ^0.15.0`) and two need version bumps (`supabase_flutter ^2.0.0` → `^2.12.0`, `http ^1.2.0` → `^1.6.0`). The `google_sign_in` v7 API is a breaking change from v6 — use only v7 patterns from Supabase docs; the FreeCell app provides a working reference implementation. GitHub API calls should use the existing raw `http` + Bearer token pattern already working for Device Flow; no GitHub client library is needed or recommended.

The original `flutter_markdown` package was discontinued by Google in 2025. Use `flutter_markdown_plus` (maintained by Foresight Mobile) as the direct successor. Supabase Realtime should NOT be enabled for `bug_reports` — the shared schema constraint makes per-table real-time enablement risky, and pull-to-refresh is sufficient for a batch triage workflow.

**Core technologies:**
- `supabase_flutter ^2.12.0`: Supabase client, PKCE auth, data queries — already in use; bump resolves OAuthProvider naming conflict from early v2
- `google_sign_in ^7.2.0`: Native Google OAuth for admin sign-in — required so RLS grants access as admin UUID; copy pattern from FreeCell
- `http ^1.6.0`: GitHub REST API calls — extends existing Device Flow pattern; raw Bearer token, no client library
- `flutter_secure_storage ^10.0.0`: GitHub OAuth token storage — already in use; no change
- `flutter_markdown_plus ^1.0.7`: Render markdown in bug report detail — successor to discontinued flutter_markdown
- `photo_view ^0.15.0`: Pan/zoom screenshots from `screenshot_base64` — used only on detail screen

### Expected Features

The feature dependency chain is strict: Google Sign-In unlocks everything else. Without it, zero rows are visible. Bug report list unlocks detail, which unlocks triage tagging, which unlocks GitHub sync. This ordering is non-negotiable and must be reflected in the roadmap.

**Must have (table stakes — v1):**
- Google Sign-In — without it, the entire app shows nothing (RLS)
- Dashboard summary counts per product — orientation before diving into reports
- Bug report list with product filter and unprocessed-first ordering — the primary work surface
- Bug report detail — full context including screenshot inline and logs with copy button
- Triage status tag (issue / feedback / duplicate / not-a-bug / needs-info) — the core action
- Developer comment on a report — record reasoning alongside the tag
- GitHub issue creation with structured body template — the primary output
- Dismiss/decline with reason — close non-actionable reports cleanly

**Should have (competitive — v1.x, add after validation):**
- Per-report processing state badge in list — visual sync/triage status at a glance
- Duplicate linking — mark report as duplicate of another, link to canonical
- Batch tagging — multi-select for bulk triage of identical crash floods
- GitHub deduplication check — search API pre-flight before issue creation

**Defer (v2+):**
- Snooze a report — queue volume does not justify this yet
- Filter by triage status in list — unprocessed-first ordering covers the workflow
- Export triage data — no analytics requirement in scope

**Anti-features (do not build):**
- Multi-user access, push notifications, AI auto-triage, two-way GitHub sync, real-time live updates — all expand scope past the tool's purpose for zero current benefit

### Architecture Approach

The existing clean architecture skeleton is the right foundation and should not be restructured. New code slots into existing layers: domain models and interfaces are defined first, infrastructure implementations (Supabase repository, GitHub service) implement those interfaces, two new controllers (`TriageController`, `GitHubSyncController`) drive UI state, and screens are built last. Two controllers rather than one is deliberate — mixing triage state and sync state into a single controller creates unnecessary rebuilds and a >400-line class. All Supabase calls go through the `BugReportRepository` abstract interface; controllers never touch the Supabase SDK directly.

**Major components:**
1. `AuthController` (exists) — Supabase session + GitHub token state; must be extended for Google Sign-In
2. `TriageController` (new) — bug report list, filter state, tag and comment mutations via `BugReportRepository`
3. `GitHubSyncController` (new) — sync state per report, deduplication check, issue creation via `GitHubIssueService`
4. `SupabaseBugReportRepositoryImpl` (new) — implements `BugReportRepository`; all Supabase calls with column projection
5. `GitHubIssueServiceImpl` (new) — implements `GitHubIssueService`; Bearer token injected at call time from `GitHubAuthService`
6. `TinkerplexProduct` enum (new) — maps `source_app` values to `owner/repo` pairs; owns all routing logic in the domain layer

### Critical Pitfalls

1. **RLS silently returns empty until Google Sign-In completes** — an anonymous session is a valid Supabase session, so no error is thrown; the list just appears empty. Gate all `bug_reports` queries behind a session check that verifies the admin UUID is the authenticated user. Build Google Sign-In before any data feature.

2. **Fetching `screenshot_base64` in list queries** — `select(*)` pulls the full base64 payload for every row; with 50+ reports this causes memory spikes and scroll stutters. Always project specific columns in list queries; fetch `screenshot_base64` only in the detail screen for a single report. Establish this pattern at the first list screen — do not plan to fix it later.

3. **Non-idempotent GitHub issue creation on network retry** — `POST /repos/.../issues` has no idempotency key. A retry after a dropped network creates a duplicate issue. Embed a deterministic fingerprint (`[issueinator:{report_id}]`) in the issue body and search for it before creating. Design this before writing any sync code.

4. **Schema changes breaking shared TinkerPlex game apps** — `bug_reports` is shared with all five game apps. Adding columns must use `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ... DEFAULT NULL`. Prefer a separate `bug_report_triage` side table to keep the game-app-facing schema untouched entirely.

5. **GitHub Device Flow token expiry with no recovery path** — tokens can be revoked. A 401 from the GitHub API must trigger a re-authentication flow, not a silent no-op or generic error. Verify the existing Device Flow implementation handles 401 refresh before building sync features.

## Implications for Roadmap

Based on the dependency chain discovered in research, a four-phase structure is strongly recommended:

### Phase 1: Auth Foundation
**Rationale:** RLS blocks all `bug_reports` reads until the admin is authenticated as the correct UUID. Nothing else can be built or tested. This is the only hard prerequisite with no workaround.
**Delivers:** Working Google Sign-In replacing anonymous auth; session persistence across cold starts; auth gate routing to main UI
**Addresses:** FEATURES.md — Google Sign-In (P1 prerequisite)
**Avoids:** PITFALLS.md — Pitfall 3 (RLS silent empty); ensures the "looks done but isn't" auth checklist items are verified (cold-start session survival, not just hot-restart)
**Research flag:** None needed — FreeCell app provides a working reference implementation; copy the pattern directly

### Phase 2: Bug Report Read Path
**Rationale:** Reading reports is the prerequisite for all triage and sync features. Schema extension for triage columns must be designed here before any writes are attempted — once the schema decision is made (columns on `bug_reports` vs. side table), all downstream code is unblocked.
**Delivers:** Dashboard summary counts per product; filterable bug report list; full detail view with screenshot and logs; Supabase schema extended for triage state
**Addresses:** FEATURES.md — dashboard counts, report list, report detail, screenshot inline, logs with copy (all P1)
**Uses:** `supabase_flutter` column projection, `photo_view`, `flutter_markdown_plus`
**Implements:** `BugReportRepository` interface + `SupabaseBugReportRepositoryImpl`, `TriageController`, `DashboardScreen`, `ReportListScreen`, `ReportDetailScreen`
**Avoids:** PITFALLS.md — Pitfall 1 (`screenshot_base64` column projection established here); Pitfall 4 (additive-only schema migration)
**Research flag:** Schema design decision (columns vs. side table) may benefit from a brief research-phase to confirm which approach preserves the shared schema constraint most safely

### Phase 3: Triage Actions
**Rationale:** With the read path working and schema in place, write operations can be added safely. Tags and comments are straightforward Supabase mutations. Duplicate linking requires a UI search pattern but no new infrastructure. This phase completes the v1 triage loop.
**Delivers:** Tag application (issue / feedback / duplicate / not-a-bug / needs-info); developer comment; duplicate linking; dismiss with required reason; triage state persists across app restart
**Addresses:** FEATURES.md — triage status tag, developer comment, duplicate linking, dismiss/decline (all P1/P2)
**Implements:** `TriageController` mutation methods, `triage_tag_chip` widget, optimistic UI update + immediate Supabase persist pattern
**Avoids:** PITFALLS.md — Pitfall 4 (write migrations must be additive); technical debt pattern of storing triage state only in memory
**Research flag:** None needed — standard Supabase update pattern; well-documented

### Phase 4: GitHub Sync
**Rationale:** Sync is last because it requires a valid triage tag before a report should be pushed to GitHub (enforce the "only tagged 'issue' reports get synced" guard), and it introduces the most failure-mode complexity. The idempotency design must be locked before writing any sync code.
**Delivers:** GitHub issue creation with structured body template; `github_issue_url` write-back to Supabase; deduplication fingerprint check; Device Flow 401 recovery; GitHub sync status indicator in report list
**Addresses:** FEATURES.md — GitHub issue creation (P1), structured issue body template (P1), per-report processing state badge (P2), GitHub deduplication check (P2)
**Implements:** `GitHubIssueService` interface + `GitHubIssueServiceImpl`, `GitHubSyncController`, `github_sync_button` widget
**Avoids:** PITFALLS.md — Pitfall 2 (idempotency fingerprint); Pitfall 5 (Device Flow 401 recovery); integration gotcha of missing Supabase write-back after issue creation
**Research flag:** Idempotency fingerprint approach and GitHub Search API query construction would benefit from a brief research-phase during planning

### Phase Ordering Rationale

- **Auth before data** is forced by RLS — there is no workaround or stub that avoids this. Testing any data feature without real auth produces silent empty results, not useful errors.
- **Read before write** is forced by schema — the triage column/table design must be validated before write code is attempted. Retrofitting the schema after write code is written is a high-cost rework.
- **Triage before sync** is a product rule, not just a code dependency — syncing an untagged or unreviewed report would pollute GitHub repos. The tag requirement should be a guard in `GitHubSyncController`, not a UI convention.
- **Batch tagging and additional P2 features** should be added within Phase 3 or as a Phase 3.5 after core triage is validated in daily use, based on whether friction appears.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2 (schema design):** The choice between adding triage columns to `bug_reports` vs. a separate `bug_report_triage` side table has correctness implications for the shared schema constraint. STACK.md recommends additive columns with `IF NOT EXISTS`; PITFALLS.md recommends a side table. These recommendations conflict slightly and should be reconciled before schema migration is written.
- **Phase 4 (GitHub sync idempotency):** The fingerprint-based dedup approach (`[issueinator:{report_id}]` in issue body) needs validation that GitHub Search API indexes issue body text quickly enough to prevent race conditions in rapid retry scenarios. Also confirm `X-RateLimit-Remaining` header response format before implementing rate limit handling.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Google Sign-In):** FreeCell provides a working reference; copy the pattern
- **Phase 3 (triage mutations):** Standard Supabase update pattern; no novel integration

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Existing codebase examined directly; official pub.dev and Supabase docs verified; FreeCell reference implementation confirmed working |
| Features | MEDIUM | Table stakes validated by Linear/Sentry/GitHub triage comparisons; differentiators based on community workflow patterns; internal tool so no user research available |
| Architecture | HIGH | Clean architecture pattern is the established TinkerPlex convention; component breakdown derived from existing code structure; data flows verified against GitHub and Supabase official docs |
| Pitfalls | MEDIUM | Critical pitfalls (RLS silence, base64 in list, non-idempotent GitHub API, shared schema) have HIGH-confidence sources; UX pitfalls and performance traps are MEDIUM (community sources, consistent with official docs) |

**Overall confidence:** HIGH

### Gaps to Address

- **Schema decision (columns vs. side table):** STACK.md and PITFALLS.md give slightly different guidance. Resolve during Phase 2 planning before writing any migration SQL. Recommendation: prefer the `bug_report_triage` side table to keep game-app-facing schema unchanged, but validate this against the current RLS policies to confirm a JOIN-based query works within admin-only RLS.
- **`google_sign_in` v7 Android configuration:** The FreeCell reference exists but the specific `google-services.json` and OAuth client ID setup for IssueInator's app ID (`com.tinkerplexlabs.issueinator`) needs verification. This is config work, not architecture research — address at the start of Phase 1.
- **Supabase 1,000-row default limit:** The current report count is ~53, well under the limit. Pagination should be designed into `BugReportRepository` from Phase 2 even if not immediately needed, to avoid a retrofit when volume grows.

## Sources

### Primary (HIGH confidence)
- Existing issueinator codebase `lib/` — confirms current state, existing patterns, working Device Flow implementation
- [pub.dev/packages/supabase_flutter](https://pub.dev/packages/supabase_flutter) — version 2.12.0, official supabase.io publisher
- [pub.dev/packages/google_sign_in](https://pub.dev/packages/google_sign_in) — version 7.2.0, official Flutter publisher
- [pub.dev/packages/http](https://pub.dev/packages/http) — version 1.6.0, dart.dev publisher
- [supabase.com/docs/reference/dart/auth-signinwithidtoken](https://supabase.com/docs/reference/dart/auth-signinwithidtoken) — signInWithIdToken with OAuthProvider.google
- [docs.github.com/en/rest/issues/issues](https://docs.github.com/en/rest/issues/issues) — GitHub REST API for issue creation
- [docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) — rate limits (30 req/min search, 5000 req/hr core)
- [supabase.com/docs/guides/database/postgres/row-level-security](https://supabase.com/docs/guides/database/postgres/row-level-security) — RLS behavior and silent filtering
- TinkerPlex CLAUDE.md — clean architecture conventions, GetIt + Provider pattern, monorepo constraints

### Secondary (MEDIUM confidence)
- [pub.dev/packages/flutter_markdown_plus](https://pub.dev/packages/flutter_markdown_plus) — successor to discontinued flutter_markdown; confirmed via foresightmobile.com blog
- [pub.dev/packages/photo_view](https://pub.dev/packages/photo_view) — version 0.15.0; last published 23 months ago but still maintained
- [github.com/supabase/supabase/issues/20998](https://github.com/supabase/supabase/issues/20998) — base64 column performance issue confirmed in official tracker
- [supabase.com/docs/guides/realtime/authorization](https://supabase.com/docs/guides/realtime/authorization) — Realtime + RLS interaction
- [Linear triage docs](https://linear.app/docs/triage) — triage taxonomy patterns
- [Sentry issue grouping docs](https://docs.sentry.io/concepts/data-management/event-grouping/merging-issues/) — duplicate detection patterns
- [vscode Issues Triaging wiki](https://github.com/microsoft/vscode/wiki/Issues-Triaging) — real-world large-scale triage process

### Tertiary (LOW confidence)
- [Bird Eats Bug: Bug Triage Process](https://birdeatsbug.com/blog/bug-triage-process) — workflow breakdown; useful but vendor blog
- [Marker.io: Bug Triage Organization](https://marker.io/blog/bug-triage) — feature patterns; vendor blog
- [LogRocket: GetIt common mistakes](https://blog.logrocket.com/dependency-injection-flutter-using-getit-injectable/) — single community source

---
*Research completed: 2026-03-21*
*Ready for roadmap: yes*
