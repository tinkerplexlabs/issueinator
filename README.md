# IssueInator

A developer-facing Flutter app for triaging bug reports submitted by users of TinkerPlex games (Puzzle Nook, FreeCell, Blocks, Paint, Reader). Every user-submitted bug falls through the triage net and is either synced to GitHub as a tracked issue or explicitly dismissed — nothing falls through the cracks.

## What It Does

- View bug reports from the shared Supabase backend, filtered by product
- Tag reports with mandatory taxonomy (issue, feedback, duplicate, not-a-bug, needs-info)
- Add comments and link duplicates to canonical issues
- Batch-select and tag multiple reports
- Sync reports tagged "issue" to the correct GitHub repository with deduplication

## Tech Stack

- **Flutter/Dart** (SDK ^3.6.0) — workspace member of the TinkerPlex monorepo
- **Supabase** — shared backend for auth, bug reports, products
- **GitHub Device Flow** (RFC 8628) — OAuth for syncing issues to repos
- **Provider + GetIt** — state management and dependency injection
- **Clean Architecture** — domain / application / infrastructure / presentation layers
- **Material 3 Dark Mode** — neon cyan/magenta/green UI theme

## Running

```bash
# From the demos/ workspace root
flutter pub get

# Run on connected device
cd tools/issueinator
flutter run
```

## Architecture

```
lib/
├── core/              # Logging utilities
├── config/            # GetIt dependency injection
├── domain/            # Models (AppUser, DeviceFlowChallenge), service interfaces
├── application/       # AuthController (ChangeNotifier)
├── infrastructure/    # Supabase config, GitHub auth implementation, local storage
└── presentation/      # Screens (auth, home), widgets (auth gate, device flow dialog)
```

## Auth Flow

1. **Supabase** — PKCE-based anonymous sign-in (dev mode), with Google SSO planned
2. **GitHub** — Device flow OAuth: app displays a user code, user authorizes at github.com/login/device, token stored in Android Keystore via flutter_secure_storage

## Development Status

Phase 1 (Foundation & Auth) is complete. Phase 2 (Report List & Detail) is next.
