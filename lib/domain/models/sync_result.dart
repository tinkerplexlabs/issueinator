/// Result of a GitHub sync attempt.
sealed class SyncResult {
  const SyncResult();
}

/// Issue was successfully created on GitHub.
class SyncSuccess extends SyncResult {
  final String issueUrl;
  const SyncSuccess(this.issueUrl);
}

/// An existing issue with the same content hash was found — no duplicate created.
class SyncDuplicate extends SyncResult {
  final String existingUrl;
  const SyncDuplicate(this.existingUrl);
}

/// Sync failed. If [requiresReAuth] is true, the GitHub token is invalid and
/// the user must re-authenticate via Device Flow.
class SyncError extends SyncResult {
  final String message;
  final bool requiresReAuth;
  const SyncError(this.message, {this.requiresReAuth = false});
}
