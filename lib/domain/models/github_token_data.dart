/// Represents a validated GitHub OAuth token.
class GitHubTokenData {
  final String accessToken;
  final String tokenType;
  final String scope;

  const GitHubTokenData({
    required this.accessToken,
    required this.tokenType,
    required this.scope,
  });
}

/// The challenge shown to the user during device flow.
class DeviceFlowChallenge {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final int expiresInSeconds;
  final int intervalSeconds; // polling interval — NEVER hardcode, use this

  const DeviceFlowChallenge({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresInSeconds,
    required this.intervalSeconds,
  });

  factory DeviceFlowChallenge.fromJson(Map<String, dynamic> json) {
    return DeviceFlowChallenge(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUri: json['verification_uri'] as String,
      verificationUriComplete: json['verification_uri_complete'] as String? ??
          '${json['verification_uri']}?user_code=${json['user_code']}',
      expiresInSeconds: json['expires_in'] as int,
      intervalSeconds: json['interval'] as int,
    );
  }
}

/// Sealed result type for device flow polling iterations.
sealed class DeviceFlowResult {
  const DeviceFlowResult();
}

class DeviceFlowPending extends DeviceFlowResult {
  const DeviceFlowPending();
}

class DeviceFlowSuccess extends DeviceFlowResult {
  final String accessToken;
  const DeviceFlowSuccess(this.accessToken);
}

class DeviceFlowExpired extends DeviceFlowResult {
  const DeviceFlowExpired();
}

class DeviceFlowDenied extends DeviceFlowResult {
  const DeviceFlowDenied();
}

class DeviceFlowError extends DeviceFlowResult {
  final String message;
  const DeviceFlowError(this.message);
}
