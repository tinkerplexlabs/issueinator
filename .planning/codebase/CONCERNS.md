# Codebase Concerns

**Analysis Date:** 2026-03-21

## Tech Debt

**Unsafe Type Casts in Data Parsing:**
- Issue: Multiple locations use unchecked `as` casts on JSON-decoded data that could fail at runtime if API responses vary.
- Files:
  - `lib/infrastructure/services/github_auth_service_impl.dart` (lines 66, 105, 108, 116, 135)
  - `lib/domain/models/github_token_data.dart` (lines 34-40)
  - `lib/presentation/screens/home_screen.dart` (lines 42-43)
  - `lib/domain/models/app_user.dart` (lines 14-16)
- Impact: Malformed API responses or schema changes cause uncaught exceptions and app crashes.
- Fix approach: Replace unsafe casts with safe `.cast<T>()` methods, null-coalescing, and explicit type validation. Build a JSON validation layer or use a package like `freezed` for type-safe deserialization.

**GitHub API Error Handling Under-specified:**
- Issue: GitHub device flow polling treats non-success responses as `DeviceFlowError` but does not validate response structure before casting `body['error']`. Invalid response bodies could throw during cast.
- Files: `lib/infrastructure/services/github_auth_service_impl.dart` (lines 105-139)
- Impact: App crashes if GitHub API returns unexpected response shape (e.g., HTML error page instead of JSON).
- Fix approach: Add explicit content-type validation and graceful degradation for malformed responses. Consider wrapping in try-catch at the cast site.

**Missing Test Coverage:**
- Issue: Widget test file is a placeholder with no real tests. Auth flow, device code polling, and error recovery paths are untested.
- Files: `test/widget_test.dart`
- Impact: Regressions in critical auth paths go undetected. Device flow state transitions and cancellation edge cases are not validated.
- Priority: High
- Fix approach: Add unit tests for `AuthController` state transitions, `GitHubAuthServiceImpl` polling logic (mock HTTP), and widget tests for `GitHubDeviceFlowSheet` state changes. Target >70% coverage for critical paths.

**No Validation of Stored Token on Startup:**
- Issue: `AuthController` constructor restores Supabase session but does not validate or refresh the token. Expired sessions silently persist.
- Files: `lib/application/controllers/auth_controller.dart` (lines 24-31)
- Impact: User sees authenticated UI but API calls fail silently or with cryptic errors. No user-facing indicator of stale session.
- Fix approach: Call `SupabaseConfig.refreshSession()` in `AuthController.init()` and update `_currentUser` if refresh fails. Show snackbar warning if session is invalid.

## Known Bugs

**Device Flow Stream Not Cancelled on Widget Unmount:**
- Issue: `GitHubDeviceFlowSheet` listens to `pollForToken()` stream in `initState()` but the stream subscription is managed by `AuthController.dispose()`, not the widget. If sheet is dismissed before auth succeeds, the polling stream continues in background.
- Symptoms: HTTP poll requests continue after user cancels device flow, wasting battery and network. Multiple concurrent poll streams if user opens/closes sheet repeatedly.
- Files:
  - `lib/presentation/widgets/github_device_flow_dialog.dart` (lines 34-40, 78)
  - `lib/application/controllers/auth_controller.dart` (lines 74-97, 114-118)
- Trigger: Open device flow sheet → cancel (navigate back) → open again → observe network traffic
- Workaround: Manually call `auth.cancelGitHubDeviceFlow()` before popping, but this is not enforced.
- Fix approach: Make `_GitHubDeviceFlowSheetState` responsible for subscription lifecycle. Move `_pollSubscription` to widget state and cancel in `dispose()`. Have `AuthController` manage challenge state only, not the subscription itself.

**Race Condition: GitHub Token Validation During HomeScreen Build:**
- Issue: `HomeScreen.initState()` calls `validateGitHubToken()` unconditionally every time the screen loads. If user is already authenticated and navigates back to home, validation request fires again, potentially overwriting valid cached state with stale network result.
- Symptoms: GitHub auth status flickers or momentarily shows "not connected" on navigation.
- Files: `lib/presentation/screens/home_screen.dart` (lines 27-30)
- Trigger: Authenticate GitHub → navigate away → return to home screen → observe UI flicker
- Workaround: Validation is idempotent (reads cached token, validates it), but unnecessary.
- Fix approach: Move validation to `AuthController` initialization only. Cache validation result with timestamp and skip re-validation if fresh (< 1 hour old).

**No Error Recovery UI for Device Code Expiry:**
- Issue: If device code expires (10 minutes default) while sheet is open, `pollForToken()` yields `DeviceFlowExpired`, but sheet does not offer a clear "Try Again" button. User sees only error text.
- Symptoms: User authorizes slowly, device code expires, no obvious recovery path.
- Files: `lib/presentation/widgets/github_device_flow_dialog.dart` (lines 112-127)
- Trigger: Request device code → wait 10+ minutes without authorizing → code expires → observe minimal error UI
- Workaround: User can tap "Cancel" and restart flow manually.
- Fix approach: Add explicit "Try Again" button for `DeviceFlowExpired` case, similar to error state (lines 118-126).

## Security Considerations

**Client ID Committed to Codebase:**
- Risk: GitHub OAuth Client ID (`Ov23li5YPIfifmTKFx3A`) is hardcoded in source. GitHub Device Flow uses only client_id (no secret), so this is intentional and safe per RFC 8628, but broadens attack surface.
- Files: `lib/infrastructure/services/github_auth_service_impl.dart` (line 11)
- Current mitigation: Device flow does not require client_secret. No credentials are exposed. Client ID scopes are limited to `repo read:user`.
- Recommendations: Document that client_id is public by design. Monitor GitHub API audit logs for abnormal token generation patterns. Consider rotating client_id if abuse detected.

**Supabase Anon Key Committed to Codebase:**
- Risk: Supabase anonymous public key is hardcoded and committed. This is by design per Supabase documentation (PKCE flow), but enables anyone with the codebase to access the backend.
- Files: `lib/infrastructure/services/supabase_config.dart` (lines 5-7)
- Current mitigation: RLS (Row-Level Security) on Supabase tables enforces authorization. PKCE auth flow ensures only authenticated sessions create usable tokens. Anonymous sessions are restricted by RLS policies.
- Recommendations: Ensure all Supabase tables have tight RLS policies that block anonymous access. Audit RLS rules regularly. If RLS fails, attacker can read/modify all data.

**GitHub Token Stored in Android Keystore:**
- Risk: Token is persisted in Flutter Secure Storage, which delegates to Android Keystore on Android. Keystore is encrypted per device. On rooted devices, privileged apps can extract keys.
- Files: `lib/infrastructure/services/github_auth_service_impl.dart` (line 18)
- Current mitigation: Flutter Secure Storage uses AES_GCM_NoPadding by default (v10.0.0+), which is industry standard. Device-level encryption is enabled.
- Recommendations: Advise users not to root devices. Consider adding certificate pinning for GitHub API calls. Log token revocation events.

**No Token Revocation on Logout:**
- Risk: `signOut()` clears Supabase session but does not revoke the GitHub token at GitHub API. Token remains valid until expiry (likely weeks).
- Files: `lib/application/controllers/auth_controller.dart` (lines 57-59)
- Current mitigation: Token only grants `repo` and `read:user` scopes. Revocation is explicit action (requires HTTP call to GitHub API).
- Recommendations: Add explicit token revocation call to `GitHubAuthService.revokeToken()` before clearing secure storage. Call this from `AuthController.signOut()`.

## Performance Bottlenecks

**Synchronous SharedPreferences Access in LocalStorage:**
- Problem: `LocalStorage` methods call `SharedPreferences.getInstance()` on every invocation, triggering synchronous disk read from prefs file.
- Files: `lib/infrastructure/persistence/local_storage.dart` (lines 11, 18, 23)
- Cause: No caching of SharedPreferences instance. Each getter/setter hits disk.
- Improvement path: Cache `SharedPreferences.getInstance()` result in a static field. Load once at app startup in `main()`. Pass to `LocalStorage` constructor as dependency.

**Network Validation on Every HomeScreen Load:**
- Problem: `validateGitHubToken()` makes HTTP GET request to `https://api.github.com/user` every time HomeScreen is built (navigation, orientation change, setState).
- Files: `lib/presentation/screens/home_screen.dart` (lines 27-30)
- Cause: No request deduplication or caching. Validation happens in `initState()` but is called for every screen instance.
- Improvement path: Move validation to `AuthController` initialization. Cache result with timestamp. Skip re-validation if < 30 minutes old. Update UI optimistically from cache.

**ListView Without Item Count Optimization:**
- Problem: HomeScreen renders products list without caching item count or using `ListView.separated` for dividers. Large product lists cause frame drops during scroll.
- Files: `lib/presentation/screens/home_screen.dart` (lines 145-157)
- Cause: No pagination or virtual scrolling. All products loaded into memory.
- Improvement path: Implement pagination (fetch 50 items at a time). Add `ListView.builder` with `itemCount` constraint. Consider `InfiniteListView` package for scroll-to-load.

## Fragile Areas

**AuthController State Machine Complexity:**
- Files: `lib/application/controllers/auth_controller.dart`
- Why fragile: Manages two independent auth flows (Supabase + GitHub) with overlapping state variables (`_isLoading`, `_currentChallenge`, `_isGitHubAuthenticated`). State transitions not formalized; easy to reach invalid states (e.g., `_isLoading = true` but no active request).
- Safe modification: Extract GitHub auth state into separate `GitHubAuthController` class. Use sealed types for state (e.g., `AuthState.loading`, `AuthState.authenticated`). Add assertions to enforce invariants.
- Test coverage: No unit tests for state transitions. Missing: test cancellation mid-flow, rapid start/cancel cycles, network errors during each phase.

**Device Flow Polling Loop:**
- Files: `lib/infrastructure/services/github_auth_service_impl.dart` (lines 72-141)
- Why fragile: Infinite `while (true)` loop with mutable `currentInterval` variable. Slow_down errors permanently increase interval; logic is correct but unintuitive. If interval grows unbounded, polling stops responding.
- Safe modification: Add maximum interval cap (GitHub spec recommends not exceeding 120s). Add iteration counter to break after max attempts. Wrap loop in explicit Future/Stream guards. Add comments explaining why `currentInterval` is mutable.
- Test coverage: No tests for slow_down behavior, expiry timeout, network errors during poll. Missing edge cases: rapid fire slow_down messages, interval overflow.

**JSON Deserialization Without Validation:**
- Files:
  - `lib/infrastructure/services/github_auth_service_impl.dart` (lines 66, 105)
  - `lib/domain/models/github_token_data.dart` (lines 32-42)
  - `lib/domain/models/app_user.dart` (lines 14-16)
- Why fragile: `jsonDecode()` followed by unsafe `as` casts. If API adds/removes fields or changes types, app crashes at runtime.
- Safe modification: Use `freezed` + `json_serializable` or hand-write validation logic. Build a `ResponseValidator` that checks required fields before deserializing.
- Test coverage: No tests for malformed responses. Missing: test missing fields, wrong types, extra fields, null values where non-null expected.

## Scaling Limits

**Single Device Code at a Time:**
- Current capacity: Only one active device flow instance per `AuthController` (singleton). If user opens device flow sheet twice, second request overwrites first.
- Limit: Cannot support concurrent auth requests or multi-device scenarios.
- Scaling path: Use a queue or allow multiple active challenges. Store challenge map by sheet instance ID. Track subscriptions per challenge.

**No Pagination for Products List:**
- Current capacity: All products loaded and rendered. Unoptimized for > 100 items.
- Limit: Scrolling becomes laggy at 500+ products. Memory usage grows linearly.
- Scaling path: Implement server-side pagination (fetch 50 items per page). Add infinite scroll detection. Cache results in local database (e.g., `drift` or SQLite).

## Dependencies at Risk

**No Upper Bound on supabase_flutter:**
- Risk: `supabase_flutter: ^2.0.0` accepts 2.x.y. Supabase has history of breaking changes between minor versions (auth flow changes, API endpoint shifts).
- Impact: `flutter pub upgrade` could pull in a version with incompatible auth behavior. Silent failures.
- Migration plan: Pin to specific minor: `supabase_flutter: ^2.0.0` → `supabase_flutter: ^2.4.0` (latest 2.x). Test against latest before upgrading.

**http Package Without Timeout:**
- Risk: All HTTP calls in `GitHubAuthServiceImpl` use `http.get()` and `http.post()` without timeout. Network hangs block device flow indefinitely.
- Impact: User sees spinner forever if GitHub API is slow or unreachable.
- Migration plan: Wrap all HTTP calls with `.timeout(Duration(seconds: 10))`. Add retry logic with exponential backoff.

## Missing Critical Features

**No Session Refresh on App Startup:**
- Problem: App restores Supabase session on launch but does not verify it's still valid. Expired session persists, causing silent API failures.
- Blocks: Users cannot detect stale sessions. No "Session Expired" error shown.
- Recommendation: Implement app startup hook that calls `SupabaseConfig.refreshSession()` and handles expiry (sign out, show login screen).

**No Offline Queue for Token Persistence:**
- Problem: GitHub token validation makes network request every HomeScreen load. No offline support.
- Blocks: Cannot determine GitHub auth status without network. Token status flickers on slow networks.
- Recommendation: Cache validation result with timestamp. Skip re-validation if < 30 minutes old and offline.

**No User Feedback for Network Errors:**
- Problem: Network errors (device code request failure, token validation timeout, product load failure) are logged but not shown to user.
- Blocks: User has no idea why auth is stuck or products aren't loading.
- Recommendation: Add error snackbars or toasts for network failures. Provide retry buttons in UI.

## Test Coverage Gaps

**GitHub Device Flow Integration:**
- What's not tested: Device code request, polling loop, slow_down handling, expiry timeout, access_denied flow, error responses.
- Files: `lib/infrastructure/services/github_auth_service_impl.dart`
- Risk: Regressions in critical auth path go undetected until user-facing QA.
- Priority: High
- Add: Unit tests with mocked HTTP client. Mock GitHub API responses for success, expiry, slow_down, error cases.

**AuthController State Transitions:**
- What's not tested: signInAnonymously, startGitHubDeviceFlow, cancelGitHubDeviceFlow, dispose (subscription cleanup).
- Files: `lib/application/controllers/auth_controller.dart`
- Risk: State leaks (subscriptions not cancelled), listener not notified on state change, exceptions swallowed.
- Priority: High
- Add: Unit tests for each public method. Use `ChangeNotifier` mocking. Assert listener notifications and state values.

**HomeScreen Data Loading:**
- What's not tested: Product list loading, error display, column discovery, casting failures.
- Files: `lib/presentation/screens/home_screen.dart`
- Risk: Malformed product data causes uncaught exception and app crash.
- Priority: Medium
- Add: Widget tests with mocked Supabase client. Test success, error, and empty states. Test casting of List and Map responses.

**GitHubDeviceFlowSheet State Rendering:**
- What's not tested: Loading state, ready state (show code and button), success state, error state, expiry state.
- Files: `lib/presentation/widgets/github_device_flow_dialog.dart`
- Risk: UI state mismatches (button hidden when it should show, error not dismissible).
- Priority: Medium
- Add: Widget tests for each state. Mock `AuthController` and verify button visibility, text content, tap handlers.

**Error Recovery Paths:**
- What's not tested: Retry buttons, cancel buttons, back navigation during auth flow, network reconnection.
- Files: Across auth flow
- Risk: User stuck in loading state or unable to retry after failure.
- Priority: Medium
- Add: Widget tests for tap handlers. Verify navigation and state reset on retry/cancel.

---

*Concerns audit: 2026-03-21*
