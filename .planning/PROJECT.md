# IssueInator

## What This Is

A developer-facing Flutter app for triaging bug reports submitted by users of TinkerPlex games (Puzzle Nook, FreeCell, Blocks, Paint, Reader). Every user-submitted bug falls through the triage net and is either synced to GitHub as a tracked issue or explicitly dismissed — nothing falls through the cracks.

## Core Value

Every bug report gets triaged — tagged, commented, and either synced to the right GitHub repo or dismissed with reason. Zero reports left unprocessed.

## Requirements

### Validated

- ✓ Supabase backend connection (shared TinkerPlex instance) — existing
- ✓ GitHub Device Flow OAuth (RFC 8628) with secure token storage — existing
- ✓ Clean architecture skeleton (domain/application/infrastructure/presentation) — existing
- ✓ GetIt DI + Provider state management — existing
- ✓ Material 3 dark theme (neon cyan/magenta/green) — existing
- ✓ Products listing from Supabase — existing

### Active

- [ ] Google Sign-In (copy from FreeCell) replacing anonymous auth — admin must sign in as UUID 65ad7649-... for RLS to grant bug_reports access
- [ ] Dashboard view: summary counts per product, drill-down to report list
- [ ] Bug report list: scrollable, filterable by product (source_app), shows description, platform, date
- [ ] Bug report detail: full report with description, device_info, app_version, platform, logs, screenshot
- [ ] Triage taxonomy: tag each report as issue / feedback / duplicate / not-a-bug / needs-info
- [ ] Comments: add developer comments to reports
- [ ] Duplicate linking: link duplicate reports to a canonical issue
- [ ] Batch operations: multi-select reports and batch-tag them
- [ ] GitHub sync: reports tagged "issue" sync to the correct game's GitHub repo (one repo per game)
- [ ] GitHub deduplication: detect if a similar issue already exists before creating a new one

### Out of Scope

- Multi-user developer access — single admin user for now
- In-game bug report submission UI — already built in the game apps
- Push notifications for new reports — check manually
- Analytics/reporting dashboards beyond simple counts

## Context

- Bug reports already exist in Supabase (`bug_reports` table, 53 rows) submitted from TinkerPlex games
- RLS policy restricts SELECT to the admin UUID (`65ad7649-f551-4dc2-b6a4-f7a105b73d06`) or service_role
- Current app uses anonymous auth, which is why reports don't appear — need Google SSO to authenticate as admin
- The `bug_reports` table has: id, user_id, description, app_version, device_info, platform, logs, screenshot_base64, created_at, github_issue_url, source_app
- Triage tags and comments will likely need new columns or a related table in Supabase
- FreeCell app has working Google Sign-In pattern to copy
- GitHub Device Flow is already implemented for repo access tokens

## Constraints

- **Supabase schema**: Shared across all TinkerPlex apps — any schema changes must be backward-compatible
- **Tech stack**: Flutter/Dart, Supabase, Provider + GetIt (matches TinkerPlex monorepo conventions)
- **Single admin**: Only one developer user needs access — RLS already hardcoded to admin UUID
- **GitHub repos**: One repo per game — sync must route issues to correct repo based on source_app

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Google SSO over anonymous auth | RLS requires admin UUID for bug_reports SELECT | — Pending |
| Dashboard-first layout | Quick overview of report counts before drilling in | — Pending |
| One GitHub repo per game | Matches existing repo structure, keeps issues organized | — Pending |
| Tag + comment + sync triage flow | Full workflow: read, categorize, annotate, then sync to GitHub | — Pending |

---
*Last updated: 2026-03-21 after initialization*
