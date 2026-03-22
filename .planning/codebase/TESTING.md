# Testing

**Mapped:** 2026-03-21

## Current State

**Minimal** — single placeholder test file.

### Test File

- `test/widget_test.dart` — placeholder with `expect(true, isTrue)`
- Comment indicates real tests planned for subsequent phases

### Test Dependencies

From `pubspec.yaml`:
- `flutter_test` (SDK)
- `mockito: ^5.4.0` — mock generation (not yet used)
- `test: ^1.24.0` — base test framework

## Test Infrastructure

- **No test utilities** — no helpers, fixtures, or shared test setup
- **No mocks generated** — mockito declared but no `@GenerateMocks` annotations
- **No integration tests** — no `integration_test/` directory
- **No CI test pipeline** — no GitHub Actions or other CI config

## Coverage

- **Estimated coverage:** ~0% (only placeholder test)
- **Critical untested areas:**
  - Supabase authentication flow
  - GitHub Device Flow OAuth (device code polling, token exchange)
  - AuthController state management
  - Secure token storage/retrieval
  - Product loading from Supabase

## Recommendations

1. Add unit tests for `AuthController` state transitions
2. Add unit tests for `GitHubAuthServiceImpl` (mock HTTP responses)
3. Add widget tests for `AuthGate` routing logic
4. Add widget tests for `GitHubDeviceFlowSheet` UI states
5. Consider integration tests for Supabase connectivity
