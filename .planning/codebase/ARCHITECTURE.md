# Architecture

**Analysis Date:** 2026-03-21

## Pattern Overview

**Overall:** Clean Architecture with layered separation of concerns

**Key Characteristics:**
- Strict layer isolation (domain → application → infrastructure → presentation)
- Domain layer contains no Flutter dependencies — pure Dart business logic
- Application layer uses ChangeNotifier for reactive state management
- GetIt singleton for dependency injection with manual registration
- Supabase as single backend for authentication and data access
- GitHub OAuth via device flow (RFC 8628) for external integrations

## Layers

**Domain:**
- Purpose: Pure Dart business logic, service interfaces, and data models
- Location: `lib/domain/`
- Contains: `models/` (AppUser, DeviceFlowChallenge, sealed DeviceFlowResult types), `services/` (GitHubAuthService interface), `repositories/` (scaffold only)
- Depends on: Nothing (no external imports)
- Used by: Application and infrastructure layers

**Application:**
- Purpose: Use cases and state management via ChangeNotifier controllers
- Location: `lib/application/controllers/`
- Contains: `AuthController` — manages Supabase auth state, GitHub device flow polling, session restoration
- Depends on: Domain services, infrastructure config (SupabaseConfig)
- Used by: Presentation screens and widgets

**Infrastructure:**
- Purpose: External service implementations and persistence
- Location: `lib/infrastructure/`
- Contains:
  - `services/supabase_config.dart` — PKCE initialization, session refresh, global client access
  - `services/github_auth_service_impl.dart` — GitHub device flow implementation (request code, poll token, secure storage)
  - `persistence/local_storage.dart` — SharedPreferences abstraction
- Depends on: Domain service interfaces, external packages (supabase_flutter, http, flutter_secure_storage)
- Used by: Application controllers

**Presentation:**
- Purpose: UI screens, widgets, and user interactions
- Location: `lib/presentation/`
- Contains:
  - `screens/auth_screen.dart` — Anonymous sign-in prompt (dev mode, Google SSO planned)
  - `screens/home_screen.dart` — Bug report list, GitHub connection status, product data
  - `widgets/auth_gate.dart` — Conditional router (unauthenticated → AuthScreen, authenticated → HomeScreen)
  - `widgets/github_device_flow_dialog.dart` — Bottom sheet for device flow UX (code display, browser launch, status)
- Depends on: Application controllers, domain models, infrastructure config
- Used by: Flutter MaterialApp entry point

**Core:**
- Purpose: Shared utilities and cross-cutting concerns
- Location: `lib/core/`
- Contains: `dev_log.dart` — debug-only logging utility
- Depends on: Flutter foundation only
- Used by: All layers for consistent logging

**Config:**
- Purpose: Dependency injection setup
- Location: `lib/config/`
- Contains: `dependencies.dart` — GetIt singleton registration (LocalStorage, GitHubAuthService, AuthController)
- Depends on: All layer implementations
- Used by: `main.dart` at startup

## Data Flow

**Authentication Initialization Flow:**

1. `main()` → `SupabaseConfig.initialize()` (PKCE setup, silent session restore)
2. `main()` → `configureDependencies()` (register GetIt singletons)
3. `runApp()` → `IssueInatorApp` (MaterialApp initialization)
4. `IssueInatorApp` → `AuthGate` (root widget, listens to Supabase auth stream)
5. `AuthGate.build()` checks `SupabaseConfig.client.auth.onAuthStateChange` stream:
   - Session exists → render `HomeScreen`
   - No session → render `AuthScreen`

**GitHub Device Flow Authorization:**

1. User taps "Connect GitHub" in `HomeScreen`
2. → `GitHubDeviceFlowSheet.show()` launches bottom sheet
3. Sheet calls `AuthController.startGitHubDeviceFlow(githubService)`
4. `AuthController` calls `GitHubAuthServiceImpl.requestDeviceCode()`:
   - POST to `https://github.com/login/device/code` with client_id and scope
   - Returns `DeviceFlowChallenge` (device_code, user_code, verification_uri, interval)
5. Sheet displays user_code (tappable for copy), launches `verification_uri_complete` in browser
6. `AuthController` subscribes to `githubService.pollForToken()` stream:
   - Polls at interval (adjusts on slow_down), handles pending/expired/denied/success states
   - On success: token persisted to Android Keystore via `flutter_secure_storage`
   - Updates `_isGitHubAuthenticated` flag, notifies listeners
7. Sheet listens to `AuthController` changes, auto-dismisses on success with 800ms delay

**Home Screen Data Load:**

1. `HomeScreen.initState()` calls `_loadProducts()`
2. Queries `SupabaseConfig.client.from('products').select('*').order('name')`
3. On success: discovers columns from first row keys, displays product list
4. Simultaneously validates stored GitHub token via `AuthController.validateGitHubToken()`

**State Management:**

- **Supabase session:** Automatic PKCE persistence by supabase_flutter package, restored in `AuthController` constructor, streamed via `onAuthStateChange`
- **GitHub auth state:** Stored in `AuthController` fields (`_isGitHubAuthenticated`, `_currentChallenge`), notifyListeners() broadcasts changes
- **UI reactivity:** `ListenableBuilder` and `StreamBuilder` in presentation layer listen to controller and Supabase streams
- **Local storage:** SharedPreferences via `LocalStorage` abstraction (currently unused in Phase 1, reserved for future use)

## Key Abstractions

**GitHubAuthService (Interface):**
- Purpose: Abstract GitHub OAuth device flow from presentation logic
- Examples: `lib/domain/services/github_auth_service.dart`, `lib/infrastructure/services/github_auth_service_impl.dart`
- Pattern: Dependency inversion — controller depends on interface, not implementation

**DeviceFlowResult (Sealed Class):**
- Purpose: Type-safe polling state machine with sum types (DeviceFlowPending, DeviceFlowSuccess, DeviceFlowExpired, DeviceFlowDenied, DeviceFlowError)
- Examples: `lib/domain/models/github_token_data.dart`
- Pattern: Sealed classes enforce exhaustive pattern matching on all possible outcomes

**SupabaseConfig (Singleton):**
- Purpose: Global Supabase client and session management without exposing raw client
- Examples: `lib/infrastructure/services/supabase_config.dart`
- Pattern: Static factory methods for initialization and session refresh; `client` getter for read access

**AuthController (ChangeNotifier Singleton):**
- Purpose: Unify Supabase auth and GitHub auth state into single reactive source
- Examples: `lib/application/controllers/auth_controller.dart`
- Pattern: Constructor restores Supabase session; methods trigger state changes and notify listeners; explicit dispose of poll subscription

## Entry Points

**main.dart:**
- Location: `lib/main.dart`
- Triggers: App launch (flutter run)
- Responsibilities: Initialize Supabase, register dependencies, build MaterialApp with AuthGate root

**AuthGate (Root Navigation):**
- Location: `lib/presentation/widgets/auth_gate.dart`
- Triggers: On every Supabase auth state change
- Responsibilities: Conditionally route to AuthScreen (unauthenticated) or HomeScreen (authenticated)

**HomeScreen (Feature Entry):**
- Location: `lib/presentation/screens/home_screen.dart`
- Triggers: User authenticated (via AuthGate)
- Responsibilities: Load and display products, show GitHub auth status, launch device flow sheet

## Error Handling

**Strategy:** Non-crashing resilience with graceful degradation

**Patterns:**
- **Network errors in device flow:** `GitHubAuthServiceImpl.pollForToken()` catches transient HTTP errors, yields `DeviceFlowPending`, retries silently (line 99-102)
- **Session refresh failures:** `SupabaseConfig.refreshSession()` never throws, returns boolean success state, logs all failures (line 24-41)
- **Auth state changes:** `AuthController.updateFromAuthState()` handles null user gracefully, clears state (line 33-41)
- **Product load failures:** `HomeScreen._loadProducts()` catches and displays error message in UI instead of crashing (line 52-58)
- **Debug logging:** `devLog()` is no-op in release builds, safe to leave calls throughout (lib/core/dev_log.dart)

## Cross-Cutting Concerns

**Logging:** `devLog()` utility in `lib/core/dev_log.dart` — debug-only, prefixed with layer/component identifier (e.g., `[AuthController]`, `[GitHubAuth]`). Used throughout for auth flow tracking and error diagnosis.

**Validation:**
- GitHub token validation: `GitHubAuthServiceImpl.validateStoredToken()` makes GET request to `/user` endpoint to verify token is still valid
- Device code response parsing: `DeviceFlowChallenge.fromJson()` and streaming result parsing in `pollForToken()` handle JSON structure mapping

**Authentication:**
- Supabase PKCE flow is automatic via supabase_flutter (line 13-15 in supabase_config.dart)
- GitHub device flow is manual: client_id only (no secret required per RFC 8628), user code shown in UI, user authorizes externally, token polled and stored in Android Keystore via flutter_secure_storage

**Session Persistence:**
- Supabase session: Automatic PKCE token storage by native platform libraries, restored on app launch
- GitHub token: Manual write to flutter_secure_storage in `persistToken()` (line 144-148 in github_auth_service_impl.dart), read in `validateStoredToken()` (line 27)
- Polling state: In-memory in AuthController, not persisted; user must restart device flow if app crashes during polling

---

*Architecture analysis: 2026-03-21*
