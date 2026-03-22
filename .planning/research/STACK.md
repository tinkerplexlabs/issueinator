# Stack Research

**Domain:** Flutter developer tool — bug triage with Supabase backend and GitHub issue sync
**Researched:** 2026-03-21
**Confidence:** HIGH for existing stack extensions; MEDIUM for new additions

## Context: What Already Exists

This is a subsequent-milestone research task. The existing app already has:

- Flutter + Material 3 (dark theme, neon cyan/magenta/green)
- `supabase_flutter: ^2.0.0` — Supabase client, PKCE auth, anon client
- `http: ^1.2.0` — Used for GitHub Device Flow polling (raw HTTP calls to `api.github.com`)
- `flutter_secure_storage: ^10.0.0` — Stores GitHub OAuth token in Android Keystore
- `provider: ^6.1.0` + `get_it: ^7.6.0` — State management and DI
- `shared_preferences: ^2.2.0` — Non-sensitive local storage
- `url_launcher: ^6.2.0` — Opens browser for Device Flow auth

The new milestone adds: Google Sign-In (replacing anon auth), bug report list/detail views, triage tagging, comments, and GitHub issue sync.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `supabase_flutter` | `^2.12.0` (bump from `^2.0.0`) | Supabase client, auth, realtime streams | Already in use; v2.12.0 is current stable. Bump resolves OAuthProvider naming conflict with provider package that existed in early v2. |
| `google_sign_in` | `^7.2.0` | Google OAuth for admin sign-in | Supabase `signInWithIdToken` requires this for native Google auth. FreeCell app uses this same pattern. v7 is a breaking-change release from v6 — use v7 patterns only. |
| `http` | `^1.6.0` (bump from `^1.2.0`) | GitHub REST API calls (create issue, search issues) | Already in use for Device Flow. Extend the same pattern for issue creation. No need for a GitHub client library — raw HTTP with Bearer token is simpler and already working. |
| `flutter_secure_storage` | `^10.0.0` | Stores GitHub OAuth access token | Already in use. v10 uses AES_GCM_NoPadding by default on Android (Tink-backed). No change needed. |

### Supporting Libraries (New Additions)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `flutter_markdown_plus` | `^1.0.7` | Render GitHub issue body markdown in detail view | Use when displaying bug report descriptions that may contain markdown. `flutter_markdown` (Google's original) was discontinued in 2025; `flutter_markdown_plus` is the maintained successor maintained by Foresight Mobile. |
| `photo_view` | `^0.15.0` | Pan/zoom screenshots attached to bug reports | Use in bug report detail when `screenshot_base64` field is non-null. The `bug_reports` table has `screenshot_base64`. |
| `intl` | `^0.19.0` | Format dates/times in report list and detail | Already in pubspec. Use `DateFormat` and `timeago` patterns for "3 hours ago" style display. |

### Libraries Already in pubspec (No Change)

| Library | Version | Purpose |
|---------|---------|---------|
| `provider` | `^6.1.0` | ChangeNotifier + MultiProvider tree |
| `get_it` | `^7.6.0` | Singleton DI registration |
| `shared_preferences` | `^2.2.0` | Non-sensitive local persistence |
| `url_launcher` | `^6.2.0` | Open GitHub issue URLs in browser |
| `crypto` | `^3.0.7` | PKCE code verifier (already used) |
| `collection` | `^1.18.0` | List utilities |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `flutter_lints` | `^3.0.0` | Static analysis | Already in dev_dependencies |
| `mockito` | `^5.4.0` | Unit test mocking | Already in dev_dependencies |

## Installation

```bash
# Add new dependencies to pubspec.yaml
flutter pub add google_sign_in
flutter pub add flutter_markdown_plus
flutter pub add photo_view

# Bump existing packages
# In pubspec.yaml change:
#   supabase_flutter: ^2.0.0  →  supabase_flutter: ^2.12.0
#   http: ^1.2.0              →  http: ^1.6.0

flutter pub get
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Raw `http` calls for GitHub API | `github` Dart package (v9.25.0) | Never for this project. The `github` package is community-maintained (volunteers, not official), last published 11 months ago. The project already uses raw `http` with Bearer auth for Device Flow — extending that pattern is zero additional complexity and avoids a new unmaintained dependency. |
| `supabase_flutter` streams via `StreamBuilder` | Polling with `Timer.periodic` | Use polling only if real-time is not enabled on the `bug_reports` table. Real-time is disabled by default on Supabase; must be explicitly enabled per-table. Until real-time is confirmed enabled, use one-time `select()` fetches triggered by pull-to-refresh. |
| `flutter_markdown_plus` | `markdown_widget` | Use `markdown_widget` only if you need more complex layout embedding (e.g., markdown inside a `CustomScrollView` sliver). For simple description display, `flutter_markdown_plus` is less setup. |
| `photo_view` | Flutter's built-in `InteractiveViewer` | Use `InteractiveViewer` if screenshot display is low-priority. `photo_view` adds hero animations and better gesture handling but is not strictly required. |
| Google Sign-In + `signInWithIdToken` | Supabase OAuth web redirect | Never for this app. Web OAuth redirect requires a deep link setup on Android and would break the native feel. `google_sign_in` native flow is the established TinkerPlex pattern (FreeCell uses it). |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `flutter_markdown` (original Google package) | Discontinued by Google in 2025. No longer maintained. | `flutter_markdown_plus` — direct successor, maintained by Foresight Mobile |
| `github` Dart package | Community-maintained, not an official GitHub client. Last updated April 2024 (11 months ago). Adds ~200KB to app for functionality achievable with 20 lines of `http` code. | Raw `http.post()` with `Authorization: Bearer $token` header |
| Supabase realtime for `bug_reports` | Real-time requires enabling it per-table in Supabase dashboard. The shared schema constraint means we must not break other apps. Enabling real-time on a shared table has performance implications. | One-time `select()` with pull-to-refresh; triage operations are intentional, not background-reactive. |
| Code generation (`injectable`, `freezed`) | Adds build_runner complexity the monorepo explicitly avoids. PuzzleNook uses injectable but other apps do not. | Manual GetIt registration in `config/dependencies.dart` (existing pattern) |
| `dio` HTTP client | Overkill for this app. Already using `http` package successfully for Device Flow. Adding `dio` for GitHub API calls creates two HTTP clients in one app. | Extend existing `http` usage |

## Stack Patterns by Context

**For bug report list (scrollable, filterable):**
- `supabase.from('bug_reports').select().eq('source_app', filter).order('created_at', ascending: false)`
- Wrap in `ChangeNotifier`, expose `List<BugReport> reports` + `bool isLoading`
- Use `ListView.builder` with `RefreshIndicator` for pull-to-refresh

**For triage tags and comments (new Supabase columns):**
- Add `triage_status TEXT DEFAULT NULL` and `triage_comment TEXT DEFAULT NULL` columns to `bug_reports`
- Use `ALTER TABLE bug_reports ADD COLUMN IF NOT EXISTS ...` for backward-compatible migration
- No new table needed; keeps the schema simple. `IF NOT EXISTS` protects shared apps from breakage.

**For GitHub issue creation:**
```dart
// Pattern already established in GitHubAuthServiceImpl
final token = await getIt<GitHubAuthService>().getStoredToken();
final response = await http.post(
  Uri.parse('https://api.github.com/repos/$owner/$repo/issues'),
  headers: {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  },
  body: jsonEncode({'title': title, 'body': body, 'labels': labels}),
);
```

**For Google Sign-In pattern (copy from FreeCell):**
```dart
// google_sign_in v7.x pattern (breaking change from v6)
final googleSignIn = GoogleSignIn(
  clientId: iosClientId,      // iOS only
  serverClientId: webClientId, // Required for idToken
);
final googleUser = await googleSignIn.signIn();
final googleAuth = await googleUser!.authentication;
await supabase.auth.signInWithIdToken(
  provider: OAuthProvider.google,  // v2: OAuthProvider not Provider
  idToken: googleAuth.idToken!,
  accessToken: googleAuth.accessToken,
);
```

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| `supabase_flutter ^2.12.0` | `provider ^6.1.0` | v2 renamed `Provider` enum to `OAuthProvider` to avoid collision with the `provider` package. This fix was in early v2; v2.12.0 is clean. |
| `google_sign_in ^7.2.0` | `supabase_flutter ^2.x` | v7 has breaking changes from v6: `GoogleSignIn.instance` API is different. Use only v7 patterns from Supabase docs. |
| `flutter_markdown_plus ^1.0.7` | Flutter SDK `^3.6.0` | flutter_markdown_plus is a successor to flutter_markdown, not a fork — no namespace collision. |
| `http ^1.6.0` | Dart SDK `^3.6.0` | Backward compatible with existing Device Flow code at `^1.2.0`. |

## GitHub REST API: Relevant Endpoints

The project needs these GitHub API v3 endpoints (all via raw `http` with Bearer token):

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Create issue | POST | `/repos/{owner}/{repo}/issues` |
| Search existing issues | GET | `/repos/{owner}/{repo}/issues?state=open` or `/search/issues?q=...` |
| Get issue | GET | `/repos/{owner}/{repo}/issues/{number}` |
| Validate token | GET | `/user` (already implemented) |

Required header: `X-GitHub-Api-Version: 2022-11-28` (GitHub stable API version)
Scope: `repo` (already requested in Device Flow — already implemented)

## Supabase Schema Changes Required

The `bug_reports` table needs new columns for triage. Migration must be backward-compatible (shared schema constraint):

```sql
-- Safe: IF NOT EXISTS prevents errors if run twice or from another app context
ALTER TABLE bug_reports ADD COLUMN IF NOT EXISTS triage_status TEXT DEFAULT NULL;
ALTER TABLE bug_reports ADD COLUMN IF NOT EXISTS triage_comment TEXT DEFAULT NULL;
ALTER TABLE bug_reports ADD COLUMN IF NOT EXISTS github_synced_at TIMESTAMPTZ DEFAULT NULL;
ALTER TABLE bug_reports ADD COLUMN IF NOT EXISTS duplicate_of UUID REFERENCES bug_reports(id) DEFAULT NULL;
```

Note: `github_issue_url` column already exists in `bug_reports` (confirmed in PROJECT.md).

## Sources

- [pub.dev/packages/supabase_flutter](https://pub.dev/packages/supabase_flutter) — Current version 2.12.0 (HIGH confidence, official publisher supabase.io)
- [pub.dev/packages/google_sign_in](https://pub.dev/packages/google_sign_in) — Current version 7.2.0 (HIGH confidence, official Flutter publisher)
- [pub.dev/packages/flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) — Current version 10.0.0 (HIGH confidence)
- [pub.dev/packages/http](https://pub.dev/packages/http) — Current version 1.6.0 (HIGH confidence, dart.dev publisher)
- [pub.dev/packages/flutter_markdown_plus](https://pub.dev/packages/flutter_markdown_plus) — Current version 1.0.7 (MEDIUM confidence; successor to discontinued flutter_markdown confirmed via foresightmobile.com blog)
- [pub.dev/packages/photo_view](https://pub.dev/packages/photo_view) — Current version 0.15.0 (MEDIUM confidence; last published 23 months ago but still maintained)
- [pub.dev/packages/github](https://pub.dev/packages/github) — Version 9.25.0, community-maintained; NOT recommended (MEDIUM confidence for rejection rationale)
- [supabase.com/docs/reference/dart/auth-signinwithidtoken](https://supabase.com/docs/reference/dart/auth-signinwithidtoken) — signInWithIdToken pattern with OAuthProvider.google (HIGH confidence, official Supabase docs)
- [supabase.com/docs/reference/dart/stream](https://supabase.com/docs/reference/dart/stream) — Supabase stream API patterns (HIGH confidence)
- [docs.github.com/en/rest/issues/issues](https://docs.github.com/en/rest/issues/issues) — GitHub REST API for issues (HIGH confidence, official GitHub docs)
- Existing codebase: `lib/infrastructure/services/github_auth_service_impl.dart` — Confirms raw `http` + Bearer token pattern already working in production (HIGH confidence)

---
*Stack research for: IssueInator bug triage tool — new milestone additions*
*Researched: 2026-03-21*
