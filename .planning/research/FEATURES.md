# Feature Research

**Domain:** Internal developer bug triage tool (mobile game bug reports -> GitHub issues)
**Researched:** 2026-03-21
**Confidence:** MEDIUM — table stakes validated by multiple sources; differentiators informed by Linear/Sentry/GitHub triage patterns; anti-features based on known scope constraints

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features a developer expects in any triage queue tool. Missing these makes the tool feel broken or unusable as a daily workflow.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Bug report list with scrollable queue | Primary surface; without it there's nothing to triage | LOW | Already scaffolded; needs filtering |
| Filter by product / source_app | 5 different game apps generate reports; must slice per-game | LOW | Supabase query parameter on `source_app` column |
| Bug report detail view | Full context is required to make any triage decision | LOW | Render description, device_info, platform, app_version, logs, screenshot_base64 |
| Triage status tag per report | Categorize each report: issue / feedback / duplicate / not-a-bug / needs-info | MEDIUM | Needs new `triage_status` column or separate table; schema change must be backward-compatible |
| Developer comment on a report | Record reasoning, ask for more info, note what was done | MEDIUM | New `bug_report_comments` table; tied to admin user_id |
| Dashboard summary counts | First screen: how many unprocessed reports per product | LOW | Aggregate query; critical for "zero unprocessed" workflow goal |
| "Unprocessed" default queue | Show untriaged items first so nothing falls through | LOW | Filter on null/unset triage_status |
| Duplicate linking | Mark report as duplicate of another, link to canonical | MEDIUM | Needs `duplicate_of` foreign key column pointing at canonical bug_report id |
| GitHub issue creation | Push an "issue"-tagged report to the correct game repo | HIGH | GitHub REST API `POST /repos/{owner}/{repo}/issues`; requires Device Flow token; route by source_app |
| Dismiss / decline with reason | Close non-actionable reports without GitHub noise | LOW | Tag as not-a-bug or feedback + optional comment; no GitHub call needed |

### Differentiators (Competitive Advantage)

Features that distinguish IssueInator from just using GitHub Issues directly, making triage faster and more complete.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Batch tagging (multi-select) | Triage many similar crash reports at once instead of one-by-one | MEDIUM | UI multi-select + bulk Supabase update; especially valuable when 50+ crash reports pile up from a single release |
| GitHub deduplication check before sync | Prevent cluttering repos with issues already filed | HIGH | Requires searching existing GitHub issues for similar title/body; naive approach: search API `GET /search/issues?q=...+repo:{owner}/{repo}`; flag when match score is high |
| Structured issue body template | Auto-compose a clean GitHub issue from the bug report fields (description, device, version, logs) | LOW | String template — zero complexity, high value; developers opening raw reports waste time reformatting |
| Screenshot inline in detail view | Visual context without needing to decode base64 manually | LOW | `screenshot_base64` field decoded and rendered as Image widget; high-value quality-of-life |
| Per-report processing state badge | Instantly see at a glance what stage each report is in (unprocessed, tagged, synced, dismissed) | LOW | Derived from triage_status + github_issue_url presence; badge in list row |
| Logs display with copy button | Logs are long and hard to read inline; a collapsible section with copy-to-clipboard speeds debugging | LOW | Flutter SelectableText or clipboard widget; small effort, real workflow gain |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem useful but would expand scope past the tool's purpose or create maintenance burden for a single-developer admin tool.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Multi-user access / team assignment | Feels like a real issue tracker should have this | Tool is single-admin by design (RLS hardcoded to one UUID); adding multi-user means Supabase schema changes, auth changes, and a whole permissions layer for zero current benefit | If team grows, migrate to Linear or GitHub Issues directly |
| Push notifications for new reports | "Never miss a new bug" | Manual checking is the stated workflow; building a notification system means a server component, token management, and platform-specific push channels — all for a tool one developer uses | Schedule a daily check; add a refresh button in the dashboard |
| AI-powered severity prediction / auto-triage | Trendy, reduces manual work | With 53 current reports and low daily volume, the manual triage is the value (developer reads and understands each report); AI auto-classification would remove the human judgment that makes triage meaningful | Use structured triage taxonomy (the 5 tags) as the human judgment layer |
| Analytics dashboards / trends over time | "How many bugs per week?" | Out of scope per PROJECT.md; simple counts per product are enough | Dashboard summary counts (table stakes) cover the useful 80% |
| In-app bug report submission UI | "Close the loop — report and triage in one place" | Already built in game apps; duplicating submission UI here creates two sources of truth | Existing game SDKs handle submission; IssueInator only triages |
| Two-way GitHub sync (pull back status changes) | "Keep Supabase in sync with GitHub issue state" | GitHub webhooks require a server endpoint; storing mirror state adds complexity and drift risk; admin can see GitHub directly | Write `github_issue_url` when creating; link out to GitHub for status; don't mirror back |
| Real-time live updates (websocket/Supabase Realtime) | "Reports update as they come in" | Supabase Realtime is simple to add, but the triage queue is a batch workflow — not a live dashboard. Polling on focus/refresh is sufficient | Pull-to-refresh or refresh button; check on app foreground |

---

## Feature Dependencies

```
[Google Sign-In]
    └──required by──> [Bug Report List]
                          └──required by──> [Bug Report Detail]
                                                └──required by──> [Triage Status Tag]
                                                                      ├──required by──> [Developer Comment]
                                                                      ├──required by──> [Duplicate Linking]
                                                                      └──required by──> [GitHub Issue Creation]

[Bug Report List]
    └──required by──> [Batch Tagging]
    └──required by──> [Dashboard Summary Counts]

[GitHub Issue Creation]
    └──enhances──> [GitHub Deduplication Check] (check before create)

[Triage Status Tag]
    └──enhances──> [Per-report Processing State Badge]

[Bug Report Detail]
    └──enhances──> [Screenshot Inline View]
    └──enhances──> [Logs Display with Copy]
    └──enhances──> [Structured Issue Body Template] (template uses detail fields)
```

### Dependency Notes

- **Google Sign-In required by Bug Report List:** RLS blocks SELECT on `bug_reports` unless authenticated as admin UUID; everything downstream depends on this working first.
- **Triage Status Tag required by GitHub Issue Creation:** A report should only be pushed to GitHub after it is explicitly tagged "issue" — preventing accidental pushes of unreviewed reports.
- **Duplicate Linking required before GitHub Issue Creation can be clean:** Without marking duplicates first, you risk creating GitHub issues for reports that are already filed. Logical ordering: tag -> link duplicates -> sync.
- **GitHub Deduplication Check enhances GitHub Issue Creation:** Deduplication check is a pre-flight step, not a blocker. GitHub issue creation works without it; dedup check just surfaces likely matches as a warning.

---

## MVP Definition

### Launch With (v1)

Minimum viable product that achieves the core value: "every bug report gets triaged."

- [ ] Google Sign-In (without this, the whole tool is broken — nothing is visible)
- [ ] Dashboard summary counts per product (orientation before diving in)
- [ ] Bug report list filtered by product, with unprocessed-first default ordering
- [ ] Bug report detail (description, device_info, platform, app_version, screenshot inline, logs with copy)
- [ ] Triage status tag (issue / feedback / duplicate / not-a-bug / needs-info)
- [ ] Developer comment (record reasoning for the tag)
- [ ] GitHub issue creation with structured template body (the primary output action)
- [ ] Dismiss/decline with reason (close non-actionable reports cleanly)

### Add After Validation (v1.x)

Features to add once the core triage loop is working and daily use reveals friction.

- [ ] Duplicate linking — trigger: "I keep tagging things duplicate but can't find the original fast"
- [ ] Batch tagging — trigger: "A new release dumped 20 identical crash reports and I had to tag them one by one"
- [ ] GitHub deduplication check — trigger: "I accidentally created duplicate GitHub issues for the same bug"
- [ ] Per-report processing state badge in list — trigger: "I can't tell which reports I already processed without opening them"

### Future Consideration (v2+)

Features to defer until the tool has proven its value in daily use.

- [ ] Snooze a report (hide until revisited) — defer: low reported volume makes it unnecessary; revisit if queue grows to hundreds of items regularly
- [ ] Filter by triage status in the list — defer: unprocessed-first queue covers the workflow; add filtering when processed reports create noise
- [ ] Export triage data to CSV — defer: no analytics requirement in scope

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Google Sign-In | HIGH | LOW (copy from FreeCell) | P1 |
| Dashboard summary counts | HIGH | LOW | P1 |
| Bug report list with filters | HIGH | LOW | P1 |
| Bug report detail view | HIGH | LOW | P1 |
| Triage status tag | HIGH | MEDIUM | P1 |
| Developer comment | HIGH | MEDIUM | P1 |
| GitHub issue creation | HIGH | HIGH | P1 |
| Screenshot inline view | MEDIUM | LOW | P1 |
| Logs display with copy | MEDIUM | LOW | P1 |
| Structured issue body template | HIGH | LOW | P1 |
| Per-report processing state badge | MEDIUM | LOW | P2 |
| Duplicate linking | MEDIUM | MEDIUM | P2 |
| Batch tagging | MEDIUM | MEDIUM | P2 |
| GitHub deduplication check | MEDIUM | HIGH | P2 |
| Snooze a report | LOW | MEDIUM | P3 |
| Filter by triage status | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

---

## Competitor Feature Analysis

This is an internal tool in the developer triage tool category. Comparable tools: Linear (triage mode), Sentry (issue grouping/review), GitHub Issues natively.

| Feature | Linear Triage | Sentry Issue Queue | GitHub Issues native | Our Approach |
|---------|--------------|-------------------|---------------------|--------------|
| Triage queue / inbox | Yes — dedicated triage view with accept/decline/snooze actions | Yes — unresolved issues queue by default | No — flat issue list, no triage concept | Unprocessed-first filtered list; simpler than Linear's keyboard-driven queue |
| Tag / label on report | Yes — labels + priority | Yes — severity, tags | Yes — labels | 5-option taxonomy (issue/feedback/duplicate/not-a-bug/needs-info) |
| Comment on report | Yes | Yes | Yes | Developer comment field; single admin so no threading needed |
| Duplicate detection | AI-assisted (Business tier) | Fingerprint + merge UI | Manual + "similar issues" link | Manual link on report + GitHub search before sync; no ML needed at this volume |
| Batch operations | Yes (multi-select + bulk actions) | Yes | Limited (labels only via UI) | Multi-select + bulk tag; covers the most common batch need |
| GitHub sync | Native (two-way) | Via integration | n/a (GitHub is native) | One-way push only; write github_issue_url back to Supabase as confirmation |
| Deduplication before creation | No | n/a | No | GitHub search API pre-flight check; flag matches, let admin decide |

---

## Sources

- [Linear Triage Docs](https://linear.app/docs/triage) — MEDIUM confidence (official docs, current)
- [Linear Triage Intelligence Docs](https://linear.app/docs/triage-intelligence) — MEDIUM confidence (official docs, current)
- [Sentry Issue Grouping / Merging Docs](https://docs.sentry.io/concepts/data-management/event-grouping/merging-issues/) — MEDIUM confidence (official docs, current)
- [Bird Eats Bug: Bug Triage Process](https://birdeatsbug.com/blog/bug-triage-process) — LOW confidence (community blog, useful workflow breakdown)
- [Atlassian: Bug Triage Best Practices](https://www.atlassian.com/agile/software-development/bug-triage) — LOW confidence (page content not fully fetched; known authoritative source)
- [GitHub REST API: Rate Limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) — HIGH confidence (official GitHub docs)
- [GitHub REST API: Issue Comments](https://docs.github.com/en/rest/issues/comments) — HIGH confidence (official GitHub docs)
- [Marker.io: Bug Triage Organization](https://marker.io/blog/bug-triage) — LOW confidence (vendor blog)
- [vscode Issues Triaging wiki](https://github.com/microsoft/vscode/wiki/Issues-Triaging) — MEDIUM confidence (real-world large-scale triage process documented by Microsoft)
- [Kubernetes Issue Triage Guidelines](https://www.kubernetes.dev/docs/guide/issue-triage/) — MEDIUM confidence (real-world large-scale triage process)

---
*Feature research for: internal developer bug triage tool (mobile game bug reports)*
*Researched: 2026-03-21*
