# Requirements: IssueInator

**Defined:** 2026-03-22
**Core Value:** Every bug report gets triaged — tagged, commented, and either synced to the right GitHub repo or dismissed with reason

## v1 Requirements

### Authentication

- [ ] **AUTH-01**: Developer can sign in with Google SSO (replacing anonymous auth), authenticating as admin UUID
- [ ] **AUTH-02**: Session persists across app restarts without re-authentication

### Dashboard

- [ ] **DASH-01**: Developer sees per-product report counts on the home screen
- [ ] **DASH-02**: Developer can tap a product to drill into its report list
- [ ] **DASH-03**: Dashboard shows unprocessed vs total counts per product

### Report List

- [ ] **LIST-01**: Developer sees scrollable list of bug reports filtered by product
- [ ] **LIST-02**: Each list item shows description preview, platform, date, and triage status
- [ ] **LIST-03**: List excludes screenshot_base64 from query (column projection for performance)
- [ ] **LIST-04**: Developer can pull-to-refresh the report list

### Report Detail

- [ ] **DETL-01**: Developer can tap a report to see full detail: description, device_info, app_version, platform, logs
- [ ] **DETL-02**: Developer can view screenshot rendered from base64 (decoded only in detail view)
- [ ] **DETL-03**: Report detail shows current triage tag and GitHub issue link if synced

### Triage

- [ ] **TRIA-01**: Developer can tag a report with one of: issue / feedback / duplicate / not-a-bug / needs-info
- [ ] **TRIA-02**: Developer can add text comments to a report
- [ ] **TRIA-03**: Developer can select multiple reports and batch-tag them
- [ ] **TRIA-04**: Reports tagged "duplicate" are excluded from GitHub sync

### GitHub Sync

- [ ] **SYNC-01**: Developer can sync "issue"-tagged reports to the correct GitHub repo based on source_app
- [ ] **SYNC-02**: Sync uses content hash dedup (hash embedded in issue body as HTML comment) to prevent duplicate GitHub issues
- [ ] **SYNC-03**: After creating a GitHub issue, github_issue_url is written back to Supabase
- [ ] **SYNC-04**: Sync uploads screenshot to Supabase Storage and embeds public URL in GitHub issue body
- [ ] **SYNC-05**: Sync routes to correct repo per product (e.g., freecell → tinkerplexlabs/freecell)

## v2 Requirements

### Triage

- **TRIA-05**: Developer can link duplicate reports to a canonical report ID
- **TRIA-06**: Developer can dismiss reports with a required reason

### Notifications

- **NOTF-01**: Developer receives notification when new bug reports arrive

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-user developer access | Single admin user for now — RLS hardcoded to one UUID |
| In-game bug report submission | Already built in game apps |
| Two-way GitHub sync (status back) | Adds webhook/server complexity for zero daily benefit |
| Push notifications | Check manually for now |
| Real-time subscriptions | Pull-to-refresh sufficient, avoids shared table perf concerns |
| Analytics dashboards | Simple counts on dashboard are enough |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTH-01 | Phase 1 | Pending |
| AUTH-02 | Phase 1 | Pending |
| DASH-01 | Phase 2 | Pending |
| DASH-02 | Phase 2 | Pending |
| DASH-03 | Phase 2 | Pending |
| LIST-01 | Phase 2 | Pending |
| LIST-02 | Phase 2 | Pending |
| LIST-03 | Phase 2 | Pending |
| LIST-04 | Phase 2 | Pending |
| DETL-01 | Phase 2 | Pending |
| DETL-02 | Phase 2 | Pending |
| DETL-03 | Phase 2 | Pending |
| TRIA-01 | Phase 3 | Pending |
| TRIA-02 | Phase 3 | Pending |
| TRIA-03 | Phase 3 | Pending |
| TRIA-04 | Phase 3 | Pending |
| SYNC-01 | Phase 4 | Pending |
| SYNC-02 | Phase 4 | Pending |
| SYNC-03 | Phase 4 | Pending |
| SYNC-04 | Phase 4 | Pending |
| SYNC-05 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-22*
*Last updated: 2026-03-22 after initial definition*
