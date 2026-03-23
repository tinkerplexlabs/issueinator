---
phase: 01-auth-foundation
plan: 01
subsystem: auth
tags: [google-services, firebase, gradle, android, google-sign-in]

# Dependency graph
requires: []
provides:
  - google-services.json for com.tinkerplexlabs.issueinator placed at android/app/
  - Google Services Gradle plugin wired to Android build (classpath + apply)
  - com.google.android.gms package visibility declared in AndroidManifest.xml
  - Gradle assembleDebug builds successfully with Google Services plugin active
affects:
  - 01-02 (Google Sign-In native dependency and Supabase auth integration)
  - All subsequent Android plans (build baseline established here)

# Tech tracking
tech-stack:
  added: [com.google.gms:google-services:4.4.0]
  patterns: [buildscript-classpath-then-apply pattern for Gradle plugins matching puzzlenook reference]

key-files:
  created:
    - android/app/google-services.json
  modified:
    - android/build.gradle.kts
    - android/app/build.gradle.kts
    - android/app/src/main/AndroidManifest.xml

key-decisions:
  - "Defer google_play_services_version meta-data to plan 02 when play-services-auth library is added — adding it without the library causes AAPT resource linking failure"
  - "Follow puzzlenook pattern exactly: buildscript block in root build.gradle.kts, plugin applied in app/build.gradle.kts"

patterns-established:
  - "Google Services plugin pattern: classpath in root buildscript{}, id() apply in app plugins{}"

requirements-completed: [AUTH-01]

# Metrics
duration: ~25min (including Gradle build + fix cycle)
completed: 2026-03-22
---

# Phase 1 Plan 01: Google Services Gradle Plugin Wiring Summary

**google-services.json placed for com.tinkerplexlabs.issueinator and Google Services Gradle plugin wired into Android build so assembleDebug completes with BUILD SUCCESSFUL**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-22 (continuation from checkpoint:human-action)
- **Completed:** 2026-03-22
- **Tasks:** 2 (Task 1 was human-action checkpoint; Task 2 was auto)
- **Files modified:** 4

## Accomplishments

- google-services.json for com.tinkerplexlabs.issueinator placed at android/app/ with SHA-1 fingerprint registered in Firebase and Supabase Google provider confirmed enabled
- Root android/build.gradle.kts gains buildscript block with com.google.gms:google-services:4.4.0 classpath (identical to puzzlenook reference)
- android/app/build.gradle.kts plugins block now includes id("com.google.gms.google-services")
- AndroidManifest.xml queries block includes com.google.android.gms package visibility entry
- ./gradlew assembleDebug exits 0 with BUILD SUCCESSFUL

## Task Commits

Each task was committed atomically:

1. **Task 1: Obtain google-services.json** - human-action checkpoint (no commit — file placed by human)
2. **Task 2: Wire Google Services Gradle plugin** - `340301a` (chore)

**Plan metadata:** (docs commit — see final commit)

## Files Created/Modified

- `android/app/google-services.json` - OAuth client config for com.tinkerplexlabs.issueinator (Firebase-generated)
- `android/build.gradle.kts` - Added buildscript block with Google Services classpath
- `android/app/build.gradle.kts` - Added id("com.google.gms.google-services") to plugins block
- `android/app/src/main/AndroidManifest.xml` - Added com.google.android.gms package visibility query

## Decisions Made

- The `google_play_services_version` meta-data entry was deferred to plan 02. Adding `@integer/google_play_services_version` before the `play-services-auth` library is on the classpath causes an AAPT resource link failure — the integer is only defined once the library resolves. The queries entry (package visibility) is safe to add now and was kept.
- Followed puzzlenook reference implementation pattern exactly for Gradle wiring.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed premature google_play_services_version meta-data from AndroidManifest**
- **Found during:** Task 2 (Wire Google Services Gradle plugin)
- **Issue:** Plan spec included `<meta-data android:name="com.google.android.gms.version" android:value="@integer/google_play_services_version" />` in the application block. Without the `play-services-auth` library dependency, AAPT cannot resolve `integer/google_play_services_version` and the build fails: `AAPT: error: resource integer/google_play_services_version not found`
- **Fix:** Removed the meta-data entry from AndroidManifest.xml. It will be added automatically by the Google Play Services library (plan 02) when the dependency is declared.
- **Files modified:** android/app/src/main/AndroidManifest.xml
- **Verification:** ./gradlew assembleDebug exits 0 with BUILD SUCCESSFUL after removal
- **Committed in:** 340301a (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug — plan spec included a resource reference that requires a library not yet on the classpath)
**Impact on plan:** Fix was necessary for the build to pass. No scope creep. The missing entry will be provided by the library in plan 02.

## Issues Encountered

- First Gradle run failed with AAPT resource linking error on `@integer/google_play_services_version` — root cause identified as premature meta-data before the Play Services library dependency exists. Fixed by removing the entry and re-running; build succeeded in 10s on the second attempt.

## User Setup Required

None — google-services.json was placed by the human during the checkpoint:human-action in Task 1. SHA-1 fingerprint registration and Supabase provider enablement were confirmed by the user before resumption.

## Next Phase Readiness

- Android build baseline is established with Google Services plugin active and google-services.json in place
- Plan 02 can now add `play-services-auth` dependency, declare `google_play_services_version` meta-data (now it will resolve), and implement the native Google Sign-In flow
- No blockers

---
*Phase: 01-auth-foundation*
*Completed: 2026-03-22*
