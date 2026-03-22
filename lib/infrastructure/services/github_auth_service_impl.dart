import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:issueinator/core/dev_log.dart';
import 'package:issueinator/domain/models/github_token_data.dart';
import 'package:issueinator/domain/services/github_auth_service.dart';

class GitHubAuthServiceImpl implements GitHubAuthService {
  // Client ID from GitHub OAuth App (TinkerPlex IssueInator) — NOT a secret; safe to commit.
  // Device flow uses only client_id, no client_secret required.
  static const String _clientId = 'Ov23li5YPIfifmTKFx3A';
  static const String _tokenKey = 'github_access_token';

  final FlutterSecureStorage _secureStorage;
  bool _isAuthenticated = false;

  GitHubAuthServiceImpl()
      : _secureStorage = const FlutterSecureStorage(
          aOptions: AndroidOptions(), // v10.0.0: uses AES_GCM_NoPadding cipher by default
        );

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  Future<bool> validateStoredToken() async {
    final token = await _secureStorage.read(key: _tokenKey);
    if (token == null) {
      devLog('[GitHubAuth] No stored token found');
      _isAuthenticated = false;
      return false;
    }
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {'Authorization': 'Bearer $token'},
      );
      _isAuthenticated = response.statusCode == 200;
      devLog('[GitHubAuth] Token validation: ${response.statusCode} → $_isAuthenticated');
      return _isAuthenticated;
    } catch (e) {
      devLog('[GitHubAuth] Token validation failed: $e');
      _isAuthenticated = false;
      return false;
    }
  }

  @override
  Future<DeviceFlowChallenge> requestDeviceCode() async {
    devLog('[GitHubAuth] Requesting device code...');
    final response = await http.post(
      Uri.parse('https://github.com/login/device/code'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'client_id': _clientId,
        'scope': 'repo read:user',
      }),
    );
    if (response.statusCode != 200) {
      devLog('[GitHubAuth] Device code error: ${response.statusCode} ${response.body}');
      throw Exception('Device code request failed: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    devLog('[GitHubAuth] Device code received, interval=${json['interval']}s');
    return DeviceFlowChallenge.fromJson(json);
  }

  @override
  Stream<DeviceFlowResult> pollForToken({
    required String deviceCode,
    required int intervalSeconds,
  }) async* {
    // CRITICAL: use a mutable local variable — slow_down must permanently increase it
    var currentInterval = intervalSeconds;
    devLog('[GitHubAuth] Starting token poll, initial interval=${currentInterval}s');

    while (true) {
      await Future.delayed(Duration(seconds: currentInterval));

      // Network may be unavailable while Custom Tab is in foreground.
      // Retry silently on transient errors instead of crashing.
      http.Response response;
      try {
        response = await http.post(
          Uri.parse('https://github.com/login/oauth/access_token'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'client_id': _clientId,
            'device_code': deviceCode,
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          }),
        );
      } catch (e) {
        devLog('[GitHubAuth] Poll network error (will retry): $e');
        yield const DeviceFlowPending();
        continue;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body.containsKey('access_token')) {
        final token = body['access_token'] as String;
        await persistToken(token);
        _isAuthenticated = true;
        devLog('[GitHubAuth] Token received and persisted');
        yield DeviceFlowSuccess(token);
        return;
      }

      switch (body['error'] as String?) {
        case 'authorization_pending':
          devLog('[GitHubAuth] Pending authorization...');
          yield const DeviceFlowPending();
          // interval unchanged — continue loop
        case 'slow_down':
          // CRITICAL: add 5s PERMANENTLY — this is not a one-time retry penalty
          currentInterval += 5;
          devLog('[GitHubAuth] slow_down received — interval now ${currentInterval}s (permanent)');
          yield const DeviceFlowPending();
        case 'expired_token':
          devLog('[GitHubAuth] Device code expired');
          yield const DeviceFlowExpired();
          return;
        case 'access_denied':
          devLog('[GitHubAuth] Access denied by user');
          yield const DeviceFlowDenied();
          return;
        default:
          final errorMsg = body['error'] as String? ?? 'unknown error';
          devLog('[GitHubAuth] Unexpected error: $errorMsg');
          yield DeviceFlowError(errorMsg);
          return;
      }
    }
  }

  @override
  Future<void> persistToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
    _isAuthenticated = true;
    devLog('[GitHubAuth] Token persisted to Android Keystore');
  }

  @override
  Future<void> revokeToken() async {
    await _secureStorage.delete(key: _tokenKey);
    _isAuthenticated = false;
    devLog('[GitHubAuth] Token revoked');
  }

  @override
  Future<String?> getStoredToken() async {
    return _secureStorage.read(key: _tokenKey);
  }
}
