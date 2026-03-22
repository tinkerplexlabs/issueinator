---
phase: 01-auth-foundation
plan: 02
subsystem: auth
tags: [google-sign-in, supabase, oauth, flutter, android, signing]

# Dependency graph
requires:
  - phase: 01-01
    provides: google-services.json placed + Google Services Gradle plugin wired, assembleDebug BUILD SUCCESSFUL
provides:
  - google_sign_in ^6.2.1 added to pubspec.yaml
  - AuthController.signInWithGoogle() using GoogleSignIn + signInWithIdToken(OAuthProvider.google)
  - AuthController.signOut() clears both Supabase session and Google Sign-In cache
  - AuthScreen "Sign in with Google" button with loading state
  - Upload keystore signing config wired to both debug and release build types via key.properties
  - End-to-end Google SSO verified on physical Android device as admin UUID — RLS permits bug_reports reads
  - Session persistence across cold restart confirmed (AUTH-02)
affects:
  - 02-data (authenticated Supabase client ready for bug_reports queries)
  - All subsequent plans (auth session available app-wide via Supabase.instance.client)

# Tech tracking
tech-stack:
  added: [google_sign_in ^6.2.1]
  patterns:
    - GoogleSignIn.signIn() → googleUser.authentication → signInWithIdToken(OAuthProvider.google) (matches puzzlenook pattern)
    - Upload keystore signing for debug builds — SHA-1 must match Firebase Console registered fingerprint
    - ListenableBuilder wrapping FilledButton.icon for loading-aware auth button

key-files:
  created:
    - android/key.properties
  modified:
    - pubspec.yaml
    - pubspec.lock
    - lib/application/controllers/auth_controller.dart
    - lib/presentation/screens/auth_screen.dart
    - android/app/build.gradle.kts

key-decisions:
  - "Use upload keystore for debug builds — Google Sign-In silently fails when APK SHA-1 doesn't match Firebase-registered fingerprint; default debug keystore SHA-1 was not registered"
  - "key.properties placed at android/key.properties following FreeCell pattern — load via FileInputStream with graceful fallback if file missing"
  - "Debug and release build types both use release signingConfig when key.properties present — ensures SHA-1 consistency across all build variants"

patterns-established:
  - "Signing pattern: key.properties at android/ loaded in build.gradle.kts, both debug+release use upload keystore signingConfig when available"
  - "Auth button pattern: ListenableBuilder + FilledButton.icon with null onPressed during isLoading"
  - "Google Sign-In pattern: GoogleSignIn field on controller, scopes=['email','profile'], signInWithIdToken chains to Supabase"

requirements-completed: [AUTH-01, AUTH-02]

# Metrics
duration: ~45min (including signing config debugging and device verification)
completed: 2026-03-22
---

# Phase 1 Plan 02: Google Sign-In Dart Layer and Device Verification Summary

**google_sign_in ^6.2.1 wired to AuthController via signInWithIdToken(OAuthProvider.google), upload keystore signing added to unblock SHA-1 match, verified on device as admin UUID with RLS-permitted bug_reports reads and session persisting across cold restart**

## Performance

- **Duration:** ~45 min (including signing config debugging and device verification)
- **Started:** 2026-03-22 (continuation from 01-01)
- **Completed:** 2026-03-22
- **Tasks:** 3 (2 auto + 1 human-verify checkpoint)
- **Files modified:** 5

## Accomplishments

- AuthController.signInWithGoogle() replaces signInAnonymously() — uses GoogleSignIn to obtain idToken, then calls Supabase signInWithIdToken(OAuthProvider.google)
- AuthScreen now shows a "Sign in with Google" FilledButton.icon with loading-aware disabled state
- Upload keystore signing config wired to both debug and release build types via android/key.properties — this was the root cause fix that unblocked Google Sign-In on device
- Physical device verification passed: native Google account picker appeared, app navigated to main UI, admin UUID 65ad7649-f551-4dc2-b6a4-f7a105b73d06 confirmed in logs, 3 products visible (RLS working), session survived cold restart

## Task Commits

Each task was committed atomically:

1. **Task 1: Add google_sign_in package and rewrite AuthController auth methods** - `f93e90f` (feat)
2. **Task 2: Replace auth button in AuthScreen** - `579cf33` (feat)
3. **Task 3: Verify end-to-end Google Sign-In on device** - human-verify checkpoint (no code commit — device verification only)

**Plan metadata:** (docs commit — this SUMMARY + STATE/ROADMAP update)

## Files Created/Modified

- `pubspec.yaml` - Added google_sign_in: ^6.2.1 dependency
- `pubspec.lock` - Resolved dependency graph (includes play-services-auth transitive deps)
- `lib/application/controllers/auth_controller.dart` - signInWithGoogle() + updated signOut(); GitHub auth methods preserved untouched
- `lib/presentation/screens/auth_screen.dart` - ListenableBuilder + FilledButton.icon calling signInWithGoogle()
- `android/app/build.gradle.kts` - Signing config rewritten: key.properties loader + both debug/release use upload keystore signingConfig
- `android/key.properties` - Upload keystore path and credentials (not committed — in .gitignore)

## Decisions Made

- The upload keystore (upload-keystore-tinkerplex.p12) must be used for debug builds, not just release. Google Sign-In silently returns null user when the APK SHA-1 doesn't match the fingerprint registered in Firebase Console. The default Flutter debug keystore SHA-1 was not registered — only the upload certificate fingerprint was. Wiring key.properties to both debug and release signingConfigs resolved this.
- Followed FreeCell's key.properties pattern: graceful file-existence check in build.gradle.kts with fallback to default debug keystore, so builds still work on machines without the keystore file.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Rewrote build.gradle.kts signing config to use upload keystore for debug builds**
- **Found during:** Task 3 (device verification)
- **Issue:** Google Sign-In was silently failing — `_googleSignIn.signIn()` returned null without showing the account picker. Root cause: the APK was signed with Flutter's default debug keystore, whose SHA-1 was not registered in Firebase Console. Only the upload certificate (upload-keystore-tinkerplex.p12) SHA-1 was registered. With a SHA-1 mismatch, Google Play Services silently rejects the auth request.
- **Fix:** Rewrote android/app/build.gradle.kts to load key.properties (storeFile, keyAlias, storePassword, keyPassword) and apply the upload keystore signingConfig to both the debug and release build types when key.properties is present. Created android/key.properties with the upload keystore path. Matched FreeCell's established pattern.
- **Files modified:** android/app/build.gradle.kts, android/key.properties (created, not committed)
- **Verification:** Rebuilt with `flutter run`, Google account picker appeared, sign-in completed, admin UUID confirmed in logs
- **Committed in:** (manual fix during device verification; signing config present in current build.gradle.kts)

---

**Total deviations:** 1 auto-fixed (1 blocking — SHA-1 mismatch between APK signing cert and Firebase-registered fingerprint)
**Impact on plan:** Fix was required for Google Sign-In to function at all on device. No scope creep — signing config is standard Android infrastructure. Matches existing FreeCell pattern.

## Issues Encountered

- Google Sign-In returned null silently without showing the account picker — no error thrown. Diagnosis: SHA-1 fingerprint mismatch between debug APK signing cert and Firebase Console registered fingerprint. Fix: wire upload keystore to debug build type via key.properties.

## User Setup Required

None at this stage. The key.properties file is machine-local (not committed) and the upload keystore was already present on the developer's machine at `/home/daniel/upload-keystore-tinkerplex.p12`.

## Next Phase Readiness

- AUTH-01 and AUTH-02 are complete and verified on a physical device
- Supabase client is fully authenticated as admin UUID — RLS permits reads from bug_reports
- Phase 2 (data layer) can proceed: bug_reports list query, column projection (no screenshot_base64), pagination
- No blockers

---
*Phase: 01-auth-foundation*
*Completed: 2026-03-22*
