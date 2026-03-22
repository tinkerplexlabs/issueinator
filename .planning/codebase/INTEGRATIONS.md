# External Integrations

**Analysis Date:** 2026-03-21

## APIs & External Services

**GitHub OAuth Device Flow:**
- GitHub OAuth API - User authentication via device flow (no native SDK, browser required)
  - Endpoints: `https://github.com/login/device/code`, `https://github.com/login/oauth/access_token`, `https://api.github.com/user`
  - Client: http 1.2.0
  - Client ID: `Ov23li5YPIfifmTKFx3A` (embedded, safe - no secret required for device flow)
  - Scopes: `repo read:user`
  - Implementation: `lib/infrastructure/services/github_auth_service_impl.dart`
  - Token validation endpoint: `https://api.github.com/user` (Bearer token validation)

## Data Storage

**Databases:**
- Supabase PostgreSQL (remote)
  - Managed by Supabase
  - URL: `https://vgvgcfgayqbifsqixerh.supabase.co`
  - Client: supabase_flutter 2.0.0
  - PKCE authentication enabled
  - Session persistence automatic (handled by supabase_flutter)
  - Connection: Initialized in `lib/infrastructure/services/supabase_config.dart`

**Local Storage:**
- Android SharedPreferences - User preferences and non-sensitive local data
  - Implementation: `lib/infrastructure/persistence/local_storage.dart` (SharedPreferencesLocalStorage)
  - Accessed via abstract LocalStorage interface

- Android Keystore (Encrypted) - Sensitive GitHub access tokens
  - Library: flutter_secure_storage 10.0.0
  - Cipher: AES_GCM_NoPadding (default for v10.0.0)
  - Key stored: `github_access_token`
  - Implementation: `lib/infrastructure/services/github_auth_service_impl.dart`

## Authentication & Identity

**Auth Providers:**

1. **Supabase Auth (Primary):**
   - Implementation: `lib/infrastructure/services/supabase_config.dart`
   - Auth flow: PKCE (Proof Key for Code Exchange)
   - Session storage: Automatic (supabase_flutter persists session)
   - Session refresh: `SupabaseConfig.refreshSession()` (safe to call at startup and reconnection, never throws)
   - Supported modes: Anonymous sign-in + linked identity upgrade
   - Session monitoring: AuthGate widget listens to `Supabase.instance.client.auth.authStateChanges` stream

2. **GitHub OAuth Device Flow (Secondary):**
   - Implementation: `lib/infrastructure/services/github_auth_service_impl.dart`
   - Flow type: OAuth 2.0 Device Authorization Grant (no browser redirect)
   - User proves identity on GitHub.com, app polls for token
   - Token storage: Android Keystore (flutter_secure_storage)
   - Token validation: HTTP request to `https://api.github.com/user`
   - Polling: Respects `interval` from device code response; increases by 5s on `slow_down` error
   - Sealed result types: `DeviceFlowChallenge`, `DeviceFlowPending`, `DeviceFlowSuccess`, `DeviceFlowExpired`, `DeviceFlowDenied`, `DeviceFlowError`

## Monitoring & Observability

**Error Tracking:** None detected

**Logs:**
- Approach: Console/debug logging via `lib/core/dev_log.dart`
- Logged prefixes: `[SupabaseConfig]`, `[GitHubAuth]`, `[AuthController]`
- No external logging service integration

## CI/CD & Deployment

**Hosting:**
- Target: Google Play Store (Android)
- Backend: Supabase (fully managed cloud)
- No self-hosted infrastructure required

**CI Pipeline:** Not detected in codebase analysis (likely managed separately)

## Environment Configuration

**Required env vars:** None - all critical values are hardcoded

**Hardcoded Credentials (Safe):**
- Supabase URL and anon key in `lib/infrastructure/services/supabase_config.dart`
- GitHub OAuth client ID in `lib/infrastructure/services/github_auth_service_impl.dart`

**Secrets location:**
- GitHub access tokens: Android Keystore (encrypted via flutter_secure_storage)
- Supabase session tokens: Managed automatically by supabase_flutter

## Webhooks & Callbacks

**Incoming:** None detected

**Outgoing:**
- OAuth device flow user validation: User provides approval on GitHub.com, polled by app
- Session state stream: Supabase auth state changes streamed to AuthController

## Request/Response Patterns

**GitHub Device Flow Polling:**
- POST to `https://github.com/login/oauth/access_token`
- Request body: `{"client_id": "...", "device_code": "...", "grant_type": "urn:ietf:params:oauth:grant-type:device_code"}`
- Response errors handled: `authorization_pending`, `slow_down`, `expired_token`, `access_denied`
- Slow-down penalty applied permanently to polling interval (not one-time)

**Token Validation:**
- GET to `https://api.github.com/user`
- Header: `Authorization: Bearer {token}`
- HTTP 200 = valid token, any other status = invalid

**Supabase Authentication:**
- Uses PKCE flow with automatic session persistence
- No explicit token refresh calls needed for normal operations
- Manual refresh available via `SupabaseConfig.refreshSession()` for edge cases

---

*Integration audit: 2026-03-21*
