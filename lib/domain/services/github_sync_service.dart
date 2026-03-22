import 'package:issueinator/domain/models/bug_report_detail.dart';
import 'package:issueinator/domain/models/sync_result.dart';

/// Thrown when a GitHub API call returns 401 — token is invalid or expired.
class GitHubAuthException implements Exception {
  const GitHubAuthException();

  @override
  String toString() => 'GitHubAuthException: GitHub token is invalid or expired';
}

/// Service that syncs a bug report to the appropriate GitHub repo.
abstract class GitHubSyncService {
  /// Orchestrates the full sync flow for [reportId]:
  /// content hash → dedup search → screenshot upload → issue create → DB write-back.
  Future<SyncResult> syncReport(String reportId, BugReportDetail detail);

  /// Returns the GitHub repo (e.g. 'tinkerplexlabs/freecell') for the given
  /// [sourceApp] identifier, or null if no mapping exists.
  String? repoForApp(String sourceApp);
}
