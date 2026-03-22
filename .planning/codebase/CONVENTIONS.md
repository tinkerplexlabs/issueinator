# Codebase Conventions

**Mapped:** 2026-03-21

## Code Style

- **Linting:** `package:flutter_lints/flutter.yaml` (standard Flutter lint rules)
- **Formatting:** Standard `dart format` (default line length)
- **Analysis:** `analysis_options.yaml` with default rules, no custom overrides

## Naming Conventions

- **Files:** `snake_case.dart` (standard Dart convention)
- **Classes:** `PascalCase` — `AuthController`, `GitHubAuthServiceImpl`, `LocalStorage`
- **Variables/methods:** `camelCase` — `_loadProducts`, `isGitHubAuthenticated`
- **Private members:** Underscore prefix — `_products`, `_loading`, `_error`
- **Constants:** `camelCase` (Dart convention) — `kDebugMode`

## Architecture Patterns

### Clean Architecture Layers

```
lib/
├── core/           → Utilities (dev_log.dart)
├── config/         → DI registration (dependencies.dart)
├── domain/         → Models + service interfaces (pure Dart)
├── application/    → Controllers (ChangeNotifier)
├── infrastructure/ → Service implementations, persistence
└── presentation/   → Screens + widgets
```

### Dependency Injection

- **GetIt** for service location — manual registration in `config/dependencies.dart`
- All registrations are `registerSingleton` (no lazy or factory patterns yet)
- Services registered by interface: `getIt.registerSingleton<GitHubAuthService>(GitHubAuthServiceImpl())`

### State Management

- **ChangeNotifier** for reactive state (`AuthController extends ChangeNotifier`)
- **ListenableBuilder** in widgets to react to controller changes
- Controllers accessed via `GetIt.instance<AuthController>()` directly in widgets

### Error Handling

- Try/catch in async methods with state update on error (`_error = e.toString()`)
- `devLog()` for debug-only logging (no-ops in release)
- No centralized error reporting or crash analytics yet

## Import Style

- Absolute imports: `package:issueinator/...`
- No relative imports observed
- Grouped by: Flutter SDK → packages → project imports

## Widget Patterns

- `StatefulWidget` with private `_State` class
- `const` constructors where possible
- Scaffold + AppBar pattern for screens
- `ListenableBuilder` for reactive UI sections

## File Organization

- One primary class per file
- `.gitkeep` files in empty directories (domain/models, domain/repositories, etc.)
- Models in `domain/models/`, service interfaces in `domain/services/`
- Implementations in `infrastructure/services/`
