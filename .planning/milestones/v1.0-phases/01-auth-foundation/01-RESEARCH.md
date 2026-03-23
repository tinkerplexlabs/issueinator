# Phase 1: Auth Foundation - Research

**Researched:** 2026-03-22
**Domain:** Flutter Google Sign-In + Supabase Native OAuth + Android configuration
**Confidence:** HIGH — full reference implementation exists in puzzlenook at `/home/daniel/work/tinkerplexlabs/demos/puzzlenook/`

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUTH-01 | Developer can sign in with Google SSO (replacing anonymous auth), authenticating as admin UUID | Full pattern in puzzlenook `SupabaseAuthService.signInWithGoogle()` — add `google_sign_in` package, wire `signInWithIdToken` to Supabase, requires `google-services.json` for `com.tinkerplexlabs.issueinator` |
| AUTH-02 | Session persists across app restarts without re-authentication | `supabase_flutter` PKCE flow persists the session automatically via `flutter_secure_storage`; `AuthController` constructor already restores it from `SupabaseConfig.client.auth.currentUser` |
</phase_requirements>

---

## Summary

Phase 1 is a port job, not an invention job. The complete Google Sign-In + Supabase pattern already runs in production in `puzzlenook`. The issueinator app already has the scaffolding — `AuthGate`, `AuthController`, `SupabaseConfig`, and `AuthScreen` — but the auth method is `signInAnonymously()`. The only required changes are: add `google_sign_in` to pubspec, wire up the `signInWithGoogle()` method in `AuthController`, swap the button in `AuthScreen`, and configure the Android build to point at a `google-services.json` for `com.tinkerplexlabs.issueinator`.

Session persistence is already working correctly. `supabase_flutter` with `AuthFlowType.pkce` persists the session token automatically via `flutter_secure_storage`. The `AuthController` constructor already restores the session (`SupabaseConfig.client.auth.currentUser`). No new work needed there — AUTH-02 is free once AUTH-01 is complete.

The single non-trivial prerequisite is the `google-services.json` file. This file must contain an OAuth client entry for `com.tinkerplexlabs.issueinator` registered in Firebase Console (same Firebase project: `tinkerplexlabs-74d71`, project number `1038604734243`). Without this file, the Google Sign-In native flow cannot obtain an ID token — the build will fail at Gradle sync or crash at runtime. The STATE.md blocker note ("google-services.json and OAuth client ID setup needs verification") is accurate: this is the only config-level action that blocks execution.

**Primary recommendation:** Port `puzzlenook`'s `SupabaseAuthService.signInWithGoogle()` into `AuthController`, wire the Android build (Google Services plugin + `google-services.json`), and replace the anonymous sign-in button. Do not add Firebase SDK — only the Google Services Gradle plugin is needed, same as puzzlenook.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `google_sign_in` | `^6.2.1` | Native Android Google OAuth — returns ID token for Supabase | The only supported native path; web-based OAuth via `supabase_flutter` requires a browser redirect, which is not appropriate for a developer-only tool |
| `supabase_flutter` | `^2.0.0` | Already present. `signInWithIdToken()` consumes Google ID token | PKCE flow + RLS. Auto-persists session. No changes to initialization needed |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `flutter_secure_storage` | `^10.0.0` | Already present. Used internally by `supabase_flutter` for session persistence | No direct usage needed — included transitively |
| `com.google.gms:google-services` Gradle plugin | `4.4.0` | Reads `google-services.json` at build time to inject OAuth client config | Required in `android/build.gradle.kts` classpath |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `google_sign_in` native | `supabase_flutter` OAuth web flow | Web flow opens browser tab, redirects back via deep link — viable but unnecessary for a single-user developer tool where UX friction doesn't matter. Native is simpler end-to-end |
| Firebase Auth SDK | Google Services plugin only | Full Firebase Auth SDK is not needed — only the Google Services Gradle plugin is required to read `google-services.json` and provide the OAuth client ID. Puzzlenook confirms this pattern |

### Installation

```bash
# From issueinator directory:
flutter pub add google_sign_in
```

---

## Architecture Patterns

### Existing Structure to Modify

```
lib/
├── application/controllers/auth_controller.dart   # ADD signInWithGoogle()
├── domain/models/app_user.dart                    # No changes needed
├── infrastructure/services/supabase_config.dart   # No changes needed
├── presentation/screens/auth_screen.dart          # REPLACE signInAnonymously() button
├── presentation/widgets/auth_gate.dart            # No changes needed
└── config/dependencies.dart                       # No changes needed

android/
├── build.gradle.kts                               # ADD google-services classpath
├── app/build.gradle.kts                           # ADD google-services plugin
└── app/google-services.json                       # ADD (new file — from Firebase Console)
```

### Pattern 1: Native Google Sign-In → Supabase signInWithIdToken

This is the exact pattern used in `puzzlenook/lib/infrastructure/services/supabase_auth_service.dart`. For issueinator, the implementation lives directly in `AuthController` (no separate auth service layer needed — the app is single-user and has no anonymous mode to support alongside Google auth).

```dart
// In AuthController — ported from puzzlenook SupabaseAuthService
Future<void> signInWithGoogle() async {
  _isLoading = true;
  notifyListeners();
  try {
    final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      // User cancelled — not an error
      return;
    }
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) throw Exception('No ID token from Google');

    await SupabaseConfig.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
    // AuthGate's StreamBuilder on onAuthStateChange handles navigation
  } catch (e) {
    devLog('[AuthController] signInWithGoogle error: $e');
    // Rethrow or set error state for UI
  } finally {
    _isLoading = false;
    notifyListeners();
  }
}
```

The `AuthGate` already listens to `SupabaseConfig.client.auth.onAuthStateChange` and routes to `HomeScreen` when a session appears — no navigation wiring needed.

### Pattern 2: Session Restoration (already implemented)

`AuthController` constructor already does this correctly:
```dart
AuthController() {
  final supabaseUser = SupabaseConfig.client.auth.currentUser;
  if (supabaseUser != null) {
    _currentUser = AppUser.fromSupabaseUser(supabaseUser);
  }
}
```
`supabase_flutter` with PKCE automatically persists and restores the session from secure storage. No additional work needed for AUTH-02.

### Pattern 3: Android Build Wiring

The Google Services Gradle plugin must be applied at two levels — same as puzzlenook:

**`android/build.gradle.kts` (root)** — add to `buildscript.dependencies`:
```kotlin
classpath("com.google.gms:google-services:4.4.0")
```

**`android/app/build.gradle.kts`** — add to `plugins`:
```kotlin
id("com.google.gms.google-services")
```

**`AndroidManifest.xml`** — add:
```xml
<!-- Required for Google Sign-In: Declare Google Play Services package visibility -->
<queries>
  <package android:name="com.google.android.gms" />
</queries>
<!-- Inside <application>: -->
<meta-data
    android:name="com.google.android.gms.version"
    android:value="@integer/google_play_services_version" />
```

### Anti-Patterns to Avoid

- **Don't keep `signInAnonymously()` as a fallback path.** The current `AuthScreen` calls it. Remove it entirely — there is no offline mode or guest mode needed for a developer triage tool. If Google sign-in fails, show an error.
- **Don't add Firebase Auth SDK.** Only the Google Services Gradle plugin is needed. Adding `firebase_core` / `firebase_auth` is unnecessary and adds ~4MB and complexity.
- **Don't create a separate `GoogleAuthService` infrastructure class.** The app is single-user with one auth method. `AuthController` is the right home for `signInWithGoogle()`.
- **Don't remove `signOut()` from `AuthController`.** It must also call `googleSignIn.signOut()` to clear the Google account picker cache, otherwise the same Google account is silently re-used on next sign-in without prompting.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Google OAuth ID token acquisition | Custom OAuth2 flow / web view | `google_sign_in` package | Handles account chooser UI, token refresh, Play Services version negotiation, Android activity lifecycle |
| Session persistence across restarts | Manual token storage in SharedPreferences | `supabase_flutter` built-in PKCE persistence | Already working — `currentUser` returns the restored session at cold start |
| Auth state routing | Manual navigation after sign-in | Existing `AuthGate` StreamBuilder on `onAuthStateChange` | Already reacts to auth events; navigation is automatic |

**Key insight:** The session persistence story is already correct. `supabase_flutter` stores the PKCE session in `flutter_secure_storage` automatically. AUTH-02 is satisfied by the existing implementation — the planner should not add any session storage tasks.

---

## Common Pitfalls

### Pitfall 1: Missing google-services.json causes silent runtime crash

**What goes wrong:** Build succeeds. App launches. Tapping "Sign In with Google" throws `PlatformException` with code `sign_in_failed` or the OAuth client ID is null, causing the Google account picker to not appear or return null immediately.

**Why it happens:** The `google_sign_in` package reads the OAuth client configuration injected by the Google Services Gradle plugin from `google-services.json`. If the file is absent or has no entry for the app's package name (`com.tinkerplexlabs.issueinator`), the plugin either fails at Gradle sync or produces no `google_play_services_version` integer resource.

**How to avoid:** Create the `google-services.json` in Firebase Console for `tinkerplexlabs-74d71` project, add `com.tinkerplexlabs.issueinator` as a new Android app, download the file, place it at `android/app/google-services.json`. This must happen before any code changes are testable.

**Warning signs:** Gradle sync error mentioning "google-services.json not found", or `PlatformException(sign_in_failed, ...)` at runtime.

### Pitfall 2: SHA-1 certificate fingerprint not registered in Firebase

**What goes wrong:** `google-services.json` is present, Google account picker appears, but authentication completes with `PlatformException: unknown calling package` or silently returns `null` for `googleUser`.

**Why it happens:** Firebase's OAuth client validates the signing certificate. The debug keystore SHA-1 must be registered in Firebase Console under the Android app settings for `com.tinkerplexlabs.issueinator`. The SHA-1 for the debug keystore is different from the release keystore.

**How to avoid:** Get the SHA-1 with:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```
Add this SHA-1 in Firebase Console → Project Settings → Your App (issueinator) → SHA certificate fingerprints. Re-download `google-services.json` after adding it.

**Warning signs:** Sign-in returns `null` user even though Google picker showed; puzzlenook's `supabase_auth_service.dart` has retry logic specifically for the `unknown calling package` error string — this is the same root cause.

### Pitfall 3: Supabase Google provider not enabled

**What goes wrong:** `signInWithIdToken()` throws `AuthException` with "Provider google is not enabled".

**Why it happens:** Supabase dashboard has Google as an OAuth provider disabled by default.

**How to avoid:** Verify in Supabase Dashboard → Authentication → Providers → Google is toggled ON. This is a one-time shared config for `vgvgcfgayqbifsqixerh.supabase.co` — puzzlenook already uses Google Sign-In on this instance, so the provider should already be enabled. Confirm before assuming it is.

**Warning signs:** `AuthException` with status code 400 and message containing "google" and "disabled" or "not enabled".

### Pitfall 4: RLS returns empty result even after correct sign-in

**What goes wrong:** Sign-in succeeds, user is authenticated, but `bug_reports` query returns `[]`.

**Why it happens:** The signed-in Google user's UUID is not `65ad7649-f551-4dc2-b6a4-f7a105b73d06`. Google Sign-In creates or retrieves a Supabase user linked to the Google account. The UUID assigned by Supabase is stable for each Google account, but it must be the same UUID that RLS is checking.

**How to avoid:** After first sign-in, check `SupabaseConfig.client.auth.currentUser?.id` in the debugger or via `devLog`. If it differs from `65ad7649-f551-4dc2-b6a4-f7a105b73d06`, the wrong Google account was used, or the admin UUID in RLS needs updating to match the actual authenticated UUID. Do not modify the RLS policy without checking both ends.

**Warning signs:** Auth state shows a valid non-null user, but all Supabase queries return empty arrays (RLS silently filters). This is different from an unauthenticated request, which would return an error.

### Pitfall 5: signOut() leaves Google account picker stuck on same account

**What goes wrong:** Developer signs out and signs back in — the Google account picker doesn't appear; it silently re-selects the previous account.

**Why it happens:** `googleSignIn.signOut()` was not called, only `SupabaseConfig.client.auth.signOut()`. The Google Sign-In SDK caches the selected account.

**How to avoid:** `signOut()` in `AuthController` must call both:
```dart
await SupabaseConfig.client.auth.signOut();
await googleSignIn.signOut();
```

---

## Code Examples

### Google Sign-In full flow (from puzzlenook reference)

Source: `/home/daniel/work/tinkerplexlabs/demos/puzzlenook/lib/infrastructure/services/supabase_auth_service.dart`

```dart
final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

Future<void> signInWithGoogle() async {
  final googleUser = await _googleSignIn.signIn();
  if (googleUser == null) return; // cancelled

  final googleAuth = await googleUser.authentication;
  final idToken = googleAuth.idToken;
  if (idToken == null) throw Exception('No ID Token from Google Sign-In');

  await SupabaseConfig.client.auth.signInWithIdToken(
    provider: OAuthProvider.google,
    idToken: idToken,
    accessToken: googleAuth.accessToken,
  );
  // onAuthStateChange stream triggers AuthGate navigation automatically
}
```

### Verify admin UUID after sign-in

```dart
final userId = SupabaseConfig.client.auth.currentUser?.id;
const adminUuid = '65ad7649-f551-4dc2-b6a4-f7a105b73d06';
assert(userId == adminUuid, 'Wrong Google account — RLS will block all queries');
devLog('[AuthController] Signed in as: $userId (admin: ${userId == adminUuid})');
```

### android/build.gradle.kts root addition

```kotlin
buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath("com.google.gms:google-services:4.4.0")
    }
}
```

### android/app/build.gradle.kts plugin addition

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")  // ADD THIS
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `signInWithProvider(OAuthProvider.google)` (web redirect) | `signInWithIdToken()` with native `google_sign_in` | supabase_flutter v2 | Native flow: no browser redirect, faster UX, no deep link callback needed |
| Anonymous auth (current issueinator) | Google SSO replacing anonymous entirely | Phase 1 | RLS unlocked; admin UUID becomes the authenticated identity |

**Deprecated/outdated:**
- `signInAnonymously()` in `AuthController`: present but must be removed — anonymous sessions never match the admin UUID and will always be blocked by RLS.
- GitHub device flow code in `AuthController` (`_isGitHubAuthenticated`, `DeviceFlowChallenge`, etc.): this is Phase 4 infrastructure added prematurely. It does not need to be touched in Phase 1, but should not interfere.

---

## Open Questions

1. **google-services.json: does it already exist for issueinator?**
   - What we know: `android/app/google-services.json` is absent from issueinator. Puzzlenook has one for `com.tinkerplexlabs.puzzlenook`.
   - What's unclear: Whether the developer has already registered `com.tinkerplexlabs.issueinator` in the Firebase Console and has the file locally, just not committed.
   - Recommendation: The planner should include a task to verify/create this file as the first action in the phase. It is an unblockable prerequisite — all code tasks depend on it. Flag it explicitly as "manual step required."

2. **SHA-1 certificate fingerprint: registered in Firebase?**
   - What we know: Puzzlenook has two SHA-1 fingerprints registered (debug + release). Issueinator needs its own entry.
   - What's unclear: Whether the same debug.keystore is used across all apps (likely — it's the Android SDK default) and whether it's already in Firebase.
   - Recommendation: Include a task to verify/add the SHA-1 fingerprint. The `keytool` command is known and deterministic.

3. **Supabase Google provider: already enabled on this instance?**
   - What we know: Puzzlenook uses it successfully on `vgvgcfgayqbifsqixerh.supabase.co`. Very likely already enabled.
   - What's unclear: Cannot verify without Supabase dashboard access.
   - Recommendation: Add a brief verification step (sign-in attempt) as the first test after wiring. Do not add a full "configure Supabase" task — assume it's already enabled.

---

## Sources

### Primary (HIGH confidence)

- `/home/daniel/work/tinkerplexlabs/demos/puzzlenook/lib/infrastructure/services/supabase_auth_service.dart` — complete working `signInWithGoogle()` implementation including retry logic
- `/home/daniel/work/tinkerplexlabs/demos/puzzlenook/android/app/build.gradle.kts` — Google Services plugin wiring pattern
- `/home/daniel/work/tinkerplexlabs/demos/puzzlenook/android/app/google-services.json` — structure showing Firebase project, OAuth client entries, SHA-1 fingerprints
- `/home/daniel/work/tinkerplexlabs/demos/puzzlenook/android/app/src/main/AndroidManifest.xml` — required manifest additions for Google Sign-In
- `/home/daniel/work/tinkerplexlabs/demos/issueinator/lib/application/controllers/auth_controller.dart` — current auth controller to be modified
- `/home/daniel/work/tinkerplexlabs/demos/issueinator/lib/presentation/widgets/auth_gate.dart` — existing routing gate (no changes needed)
- `/home/daniel/work/tinkerplexlabs/demos/issueinator/.planning/STATE.md` — confirmed blocker: `google-services.json` setup needed

### Secondary (MEDIUM confidence)

- `puzzlenook/android/build.gradle.kts` root — `classpath("com.google.gms:google-services:4.4.0")` is the current version in use

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — `google_sign_in ^6.2.1` + `supabase_flutter ^2.0.0` confirmed in production (puzzlenook)
- Architecture: HIGH — full working reference implementation read from source
- Pitfalls: HIGH — derived from actual code comments, retry logic, and STATE.md documented blockers
- Config prerequisites: MEDIUM — `google-services.json` absence confirmed; SHA-1 and Supabase provider status require runtime verification

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable libraries; `google_sign_in` and `supabase_flutter` APIs are stable)
