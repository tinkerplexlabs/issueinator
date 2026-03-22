import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:issueinator/domain/models/app_user.dart';
import 'package:issueinator/domain/models/github_token_data.dart';
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';
import 'package:issueinator/core/dev_log.dart';

class AuthController extends ChangeNotifier {
  AppUser? _currentUser;
  bool _isLoading = false;

  // GitHub auth state (added in Plan 01-03)
  bool _isGitHubAuthenticated = false;
  DeviceFlowChallenge? _currentChallenge;
  StreamSubscription<DeviceFlowResult>? _pollSubscription;

  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;
  bool get isGitHubAuthenticated => _isGitHubAuthenticated;
  DeviceFlowChallenge? get currentChallenge => _currentChallenge;

  AuthController() {
    // Restore session from supabase_flutter's automatic PKCE persistence
    final supabaseUser = SupabaseConfig.client.auth.currentUser;
    if (supabaseUser != null) {
      _currentUser = AppUser.fromSupabaseUser(supabaseUser);
      devLog('[AuthController] Restored session for ${_currentUser?.id}');
    }
  }

  void updateFromAuthState(dynamic session) {
    if (session?.user != null) {
      _currentUser = AppUser.fromSupabaseUser(session.user);
      devLog('[AuthController] Auth state updated: ${_currentUser?.id}');
    } else {
      _currentUser = null;
      devLog('[AuthController] Signed out');
    }
    notifyListeners();
  }

  Future<void> signInAnonymously() async {
    _isLoading = true;
    notifyListeners();
    try {
      await SupabaseConfig.client.auth.signInAnonymously();
    } catch (e) {
      devLog('[AuthController] signInAnonymously error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await SupabaseConfig.client.auth.signOut();
  }

  // GitHub auth methods (Plan 01-03)

  Future<void> validateGitHubToken(GitHubAuthService githubService) async {
    _isGitHubAuthenticated = await githubService.validateStoredToken();
    notifyListeners();
  }

  Future<void> startGitHubDeviceFlow(GitHubAuthService githubService) async {
    _isLoading = true;
    notifyListeners();
    try {
      _currentChallenge = await githubService.requestDeviceCode();
      notifyListeners();
      _pollSubscription = githubService
          .pollForToken(
            deviceCode: _currentChallenge!.deviceCode,
            intervalSeconds: _currentChallenge!.intervalSeconds,
          )
          .listen(
            (result) {
              if (result is DeviceFlowSuccess) {
                _isGitHubAuthenticated = true;
                _currentChallenge = null;
                notifyListeners();
              } else if (result is DeviceFlowExpired ||
                  result is DeviceFlowDenied ||
                  result is DeviceFlowError) {
                _currentChallenge = null;
                notifyListeners();
              }
              // DeviceFlowPending: no state change needed
            },
            onDone: () {
              _isLoading = false;
              notifyListeners();
            },
          );
    } catch (e) {
      devLog('[AuthController] startGitHubDeviceFlow error: $e');
      _currentChallenge = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  void cancelGitHubDeviceFlow() {
    _pollSubscription?.cancel();
    _pollSubscription = null;
    _currentChallenge = null;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollSubscription?.cancel();
    super.dispose();
  }
}
