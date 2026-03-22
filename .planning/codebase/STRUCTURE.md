# Codebase Structure

**Analysis Date:** 2026-03-21

## Directory Layout

```
issueinator/
├── lib/
│   ├── main.dart                      # App entry point, MaterialApp setup
│   ├── core/                          # Shared utilities
│   │   └── dev_log.dart               # Debug-only logging
│   ├── config/                        # Dependency injection setup
│   │   └── dependencies.dart          # GetIt singleton registration
│   ├── domain/                        # Pure Dart business logic (no Flutter deps)
│   │   ├── models/
│   │   │   ├── app_user.dart         # User identity data from Supabase
│   │   │   └── github_token_data.dart # Device flow types (sealed classes)
│   │   ├── services/
│   │   │   └── github_auth_service.dart # GitHub OAuth interface
│   │   └── repositories/              # (Empty scaffold)
│   ├── application/                   # Use cases and state management
│   │   └── controllers/
│   │       └── auth_controller.dart   # ChangeNotifier: Supabase + GitHub auth
│   ├── infrastructure/                # External integrations and persistence
│   │   ├── services/
│   │   │   ├── supabase_config.dart   # Supabase PKCE client, session management
│   │   │   └── github_auth_service_impl.dart # Device flow implementation
│   │   └── persistence/
│   │       └── local_storage.dart     # SharedPreferences wrapper (unused Phase 1)
│   └── presentation/                  # UI screens and widgets
│       ├── screens/
│       │   ├── auth_screen.dart       # Anonymous sign-in prompt (dev)
│       │   └── home_screen.dart       # Product list, GitHub status, data display
│       └── widgets/
│           ├── auth_gate.dart         # Root navigation based on auth state
│           └── github_device_flow_dialog.dart # Device flow UX (code, browser, polling)
├── test/
│   └── widget_test.dart               # Placeholder widget test
├── assets/
│   └── images/
│       └── app_icon.png               # 1x dark theme icon
├── pubspec.yaml                       # Dependencies, build config
├── pubspec.lock                       # Resolved versions
├── analysis_options.yaml               # Lint rules (flutter_lints)
├── README.md                          # Project overview
├── CLAUDE.md                          # AI assistant guidance (if present)
└── .planning/
    └── codebase/                      # Architecture documentation (you are here)
        ├── ARCHITECTURE.md
        └── STRUCTURE.md
```

## Directory Purposes

**lib/:**
- Purpose: All Dart/Flutter source code for the application
- Contains: Organized by clean architecture layers
- Key files: `main.dart` (app bootstrap)

**lib/core/:**
- Purpose: Shared utilities and cross-cutting concerns
- Contains: Logging, constants, helpers
- Key files: `dev_log.dart` (debug-only print wrapper)

**lib/config/:**
- Purpose: Application-level configuration and setup
- Contains: Dependency injection configuration
- Key files: `dependencies.dart` (GetIt singleton registration)

**lib/domain/:**
- Purpose: Pure Dart business logic, isolated from Flutter
- Contains:
  - `models/` — Data transfer objects and value types (AppUser, DeviceFlowChallenge, DeviceFlowResult sealed class hierarchy)
  - `services/` — Service interfaces (GitHubAuthService abstract class)
  - `repositories/` — (Scaffold placeholder, unused Phase 1)
- Key files: `models/github_token_data.dart` (sealed DeviceFlowResult types), `services/github_auth_service.dart` (interface)

**lib/application/:**
- Purpose: Use cases and application-layer state management
- Contains: Controllers using ChangeNotifier pattern
- Key files: `controllers/auth_controller.dart` (Supabase + GitHub auth state machine)

**lib/infrastructure/:**
- Purpose: External service implementations and platform-specific code
- Contains:
  - `services/` — Concrete implementations (Supabase initialization, GitHub OAuth)
  - `persistence/` — Local storage abstraction (SharedPreferences wrapper)
- Key files:
  - `services/supabase_config.dart` (Supabase client, PKCE setup, session refresh)
  - `services/github_auth_service_impl.dart` (GitHub device flow: code request, token polling, secure storage)
  - `persistence/local_storage.dart` (SharedPreferences wrapper, unused Phase 1)

**lib/presentation/:**
- Purpose: UI screens, widgets, and user interactions
- Contains:
  - `screens/` — Full-page layouts (AuthScreen, HomeScreen)
  - `widgets/` — Reusable UI components and dialogs
- Key files:
  - `screens/auth_screen.dart` (Anonymous sign-in button, dev-mode note)
  - `screens/home_screen.dart` (Product list, GitHub status row, device flow trigger)
  - `widgets/auth_gate.dart` (Root navigation, Supabase auth stream)
  - `widgets/github_device_flow_dialog.dart` (Device flow UX: code display, browser button, polling UI)

**test/:**
- Purpose: Automated tests (unit, widget, integration)
- Contains: Test files matching lib/ structure
- Key files: `widget_test.dart` (placeholder)

**assets/:**
- Purpose: Non-code resources (images, fonts, data files)
- Contains: `images/app_icon.png` (launcher and splash icon)
- Key files: App icon

## Key File Locations

**Entry Points:**
- `lib/main.dart`: App launch — initializes Supabase, registers dependencies, builds MaterialApp
- `lib/presentation/widgets/auth_gate.dart`: Root widget — routes to AuthScreen or HomeScreen based on auth state

**Authentication:**
- `lib/infrastructure/services/supabase_config.dart`: Supabase initialization and session management
- `lib/application/controllers/auth_controller.dart`: Unified Supabase + GitHub auth state
- `lib/infrastructure/services/github_auth_service_impl.dart`: GitHub OAuth device flow implementation
- `lib/domain/services/github_auth_service.dart`: GitHub auth service interface

**Screens:**
- `lib/presentation/screens/auth_screen.dart`: Unauthenticated landing (sign-in button)
- `lib/presentation/screens/home_screen.dart`: Authenticated landing (products, GitHub status, device flow trigger)

**Models:**
- `lib/domain/models/app_user.dart`: User identity from Supabase
- `lib/domain/models/github_token_data.dart`: Device flow challenge and sealed result types

**Configuration:**
- `lib/config/dependencies.dart`: GetIt singleton registration
- `pubspec.yaml`: Package manifest and build settings

**Testing:**
- `test/widget_test.dart`: Placeholder for widget tests

## Naming Conventions

**Files:**
- `snake_case.dart` — All Dart files
- Controllers: `{feature}_controller.dart` (e.g., `auth_controller.dart`)
- Screens: `{page}_screen.dart` (e.g., `auth_screen.dart`, `home_screen.dart`)
- Widgets: `{component}_widget.dart` or `{component}_dialog.dart` or `{component}_sheet.dart` (e.g., `auth_gate.dart`, `github_device_flow_dialog.dart`)
- Services: `{service_name}_service.dart` for interfaces; `{service_name}_service_impl.dart` for implementations
- Models: `{model_name}.dart` (e.g., `app_user.dart`, `github_token_data.dart`)

**Directories:**
- Plural nouns for grouping similar files (e.g., `models/`, `services/`, `screens/`, `widgets/`, `controllers/`)
- Layer-based grouping (domain, application, infrastructure, presentation)
- Functional grouping within layers (models, services, repositories, controllers, screens, widgets)

**Classes:**
- PascalCase — `AuthController`, `GitHubAuthService`, `HomeScreen`, `AppUser`
- Sealed classes: `DeviceFlowResult` with subtypes `DeviceFlowPending`, `DeviceFlowSuccess`, `DeviceFlowExpired`, `DeviceFlowDenied`, `DeviceFlowError`

**Functions/Methods:**
- camelCase — `requestDeviceCode()`, `pollForToken()`, `startGitHubDeviceFlow()`
- Prefixed with underscore for private methods — `_loadProducts()`, `_onAuthChanged()`

**Constants:**
- Static const fields in classes — `_clientId`, `_tokenKey` in `GitHubAuthServiceImpl`
- PascalCase for types, camelCase for values

## Where to Add New Code

**New Feature (e.g., bug report list):**
- **Models:** `lib/domain/models/{feature_name}.dart` — data structures
- **Service Interface:** `lib/domain/services/{feature_name}_service.dart` — if external integration needed
- **Controller:** `lib/application/controllers/{feature_name}_controller.dart` — state management via ChangeNotifier
- **Screens:** `lib/presentation/screens/{feature_name}_screen.dart` — page-level widget
- **Widgets:** `lib/presentation/widgets/{feature_name}_{component}.dart` — reusable sub-components
- **Infrastructure:** `lib/infrastructure/services/{feature_name}_service_impl.dart` — implement service interface if needed

**New Utility or Cross-Cutting Concern:**
- Small, reusable utilities → `lib/core/{concern_name}.dart` (e.g., `dev_log.dart`)
- Layer-specific utilities → within that layer (e.g., helpers in `lib/infrastructure/`)

**New Service Implementation (e.g., Supabase integration):**
- Define interface in `lib/domain/services/{service_name}.dart`
- Implement in `lib/infrastructure/services/{service_name}_impl.dart`
- Register in `lib/config/dependencies.dart` with GetIt

**Unit Tests:**
- Mirror lib/ structure under test/
- Test files: `test/unit/{layer}/{file}_test.dart`
- Example: `test/unit/application/auth_controller_test.dart`

**Widget Tests:**
- `test/widget/{file}_test.dart`
- Example: `test/widget/home_screen_test.dart`

## Special Directories

**lib/domain/repositories/:**
- Purpose: Repository interfaces for data access abstraction
- Generated: No
- Committed: Yes (scaffolding only, .gitkeep present)
- Status: Empty in Phase 1; will be populated in Phase 2 when report queries are introduced

**test/:**
- Purpose: Automated tests
- Generated: No
- Committed: Yes
- Status: Contains placeholder widget_test.dart; tests for auth flow and device flow to be added Phase 1-02

**assets/images/:**
- Purpose: Icon and splash image assets
- Generated: No
- Committed: Yes
- Status: Contains `app_icon.png` for launcher and splash; referenced in pubspec.yaml flutter_launcher_icons config

**.dart_tool/:**
- Purpose: Dart build cache (ignored by git)
- Generated: Yes
- Committed: No (.gitignore)

**build/:**
- Purpose: Flutter build output (ignored by git)
- Generated: Yes
- Committed: No (.gitignore)

## Layer-to-Layer Import Rules

**Allowed imports:**
- Presentation → Application, Infrastructure, Domain
- Application → Infrastructure, Domain
- Infrastructure → Domain only
- Domain → None (no external dependencies)

**Forbidden imports:**
- Domain → Any other layer
- Infrastructure → Application or Presentation
- Application → Presentation (controllers pass logic, not UI)
- Circular imports between layers

**Example correct import chain:**
```dart
// HomeScreen (presentation)
import 'package:issueinator/application/controllers/auth_controller.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';
import 'package:issueinator/domain/models/app_user.dart';

// AuthController (application)
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';
import 'package:issueinator/domain/models/github_token_data.dart';

// GitHubAuthServiceImpl (infrastructure)
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:issueinator/domain/models/github_token_data.dart';
```

---

*Structure analysis: 2026-03-21*
