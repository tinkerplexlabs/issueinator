import 'package:issueinator/domain/models/github_token_data.dart';

abstract class GitHubAuthService {
  bool get isAuthenticated;
  Future<bool> validateStoredToken();
  Future<DeviceFlowChallenge> requestDeviceCode();
  Stream<DeviceFlowResult> pollForToken({
    required String deviceCode,
    required int intervalSeconds,
  });
  Future<void> persistToken(String token);
  Future<void> revokeToken();
  Future<String?> getStoredToken();
}
