import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:issueinator/domain/models/bug_report_detail.dart';
import 'package:issueinator/domain/models/sync_result.dart';
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:issueinator/domain/services/github_sync_service.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';

class GitHubSyncServiceImpl implements GitHubSyncService {
  final GitHubAuthService _githubAuthService;
  final BugReportRepository _repository;

  GitHubSyncServiceImpl(this._githubAuthService, this._repository);

  /// Cached repo map loaded from the products table.
  Map<String, String>? _repoMap;

  /// Loads the source_app → github_repo mapping from the products table.
  Future<Map<String, String>> _getRepoMap() async {
    if (_repoMap != null) return _repoMap!;
    final rows = await SupabaseConfig.client
        .from('products')
        .select('name, github_repo')
        .not('github_repo', 'is', null);
    _repoMap = {
      for (final row in rows as List)
        row['name'] as String: row['github_repo'] as String,
    };
    return _repoMap!;
  }

  @override
  String? repoForApp(String sourceApp) => _repoMap?[sourceApp];

  @override
  Future<SyncResult> syncReport(String reportId, BugReportDetail detail) async {
    // 1. Get stored GitHub OAuth token.
    final token = await _githubAuthService.getStoredToken();
    if (token == null) {
      return const SyncError('Not authenticated', requiresReAuth: true);
    }

    // 2. Route to the correct GitHub repo based on source_app.
    final repoMap = await _getRepoMap();
    final repo = repoMap[detail.sourceApp];
    if (repo == null) {
      return SyncError('No GitHub repo mapped for "${detail.sourceApp}"');
    }

    // 3. Compute content hash — must match CLI tool algorithm exactly.
    final hash = _contentHash(
      detail.description,
      detail.deviceInfo ?? '',
      detail.platform ?? '',
      detail.appVersion ?? '',
    );

    // 4. Check for an existing issue via GraphQL dedup search.
    try {
      final existingUrl = await _findExistingIssue(hash, repo, token);
      if (existingUrl != null) {
        await _repository.updateGithubIssueUrl(reportId, existingUrl);
        return SyncDuplicate(existingUrl);
      }
    } on GitHubAuthException {
      await _githubAuthService.revokeToken();
      return const SyncError('GitHub token expired', requiresReAuth: true);
    }

    // 5. Fetch and upload screenshot (non-fatal — proceed without if it fails).
    final screenshotB64 = await _repository.getReportScreenshot(reportId);
    String? screenshotUrl;
    if (screenshotB64 != null && screenshotB64.isNotEmpty) {
      screenshotUrl = await _uploadScreenshot(reportId, screenshotB64);
    }

    // 6. Build issue title (first 80 chars of description, prefixed with "[Bug] ").
    final title = _issueTitle(detail.description);

    // 7. Build issue body in CLI tool format.
    final body = _issueBody(
      platform: detail.platform ?? 'Unknown',
      deviceInfo: detail.deviceInfo ?? 'Unknown',
      appVersion: detail.appVersion ?? 'Unknown',
      reportId: reportId,
      contentHash: hash,
      description: detail.description,
      screenshotUrl: screenshotUrl,
      logs: detail.logs ?? '',
    );

    // 8. Create the GitHub issue and write the URL back to the DB.
    try {
      final issueUrl = await _createGitHubIssue(repo, title, body, token);
      await _repository.updateGithubIssueUrl(reportId, issueUrl);
      return SyncSuccess(issueUrl);
    } on GitHubAuthException {
      await _githubAuthService.revokeToken();
      return const SyncError('GitHub token expired', requiresReAuth: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Computes SHA-256 of `description\ndeviceInfo\nplatform\nappVersion`
  /// and returns the first 12 hex characters.
  ///
  /// This MUST match the algorithm in freecell/tool/sync_bug_reports_to_github.dart.
  String _contentHash(
    String description,
    String deviceInfo,
    String platform,
    String appVersion,
  ) {
    final input = '$description\n$deviceInfo\n$platform\n$appVersion';
    final digest = sha256.convert(utf8.encode(input));
    return digest.toString().substring(0, 12);
  }

  /// Searches for an existing GitHub issue containing [hash] in its body.
  ///
  /// Uses GraphQL (NOT REST /search/issues) because the REST search API
  /// returns 422 for private repos, even with repo scope.
  ///
  /// GraphQL `url` field on Issue nodes returns the web URL (not API URL).
  Future<String?> _findExistingIssue(
    String hash,
    String repo,
    String token,
  ) async {
    final response = await http.post(
      Uri.parse('https://api.github.com/graphql'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'query': '''
          {
            search(query: "hash:$hash in:body repo:$repo", type: ISSUE, first: 1) {
              nodes {
                ... on Issue {
                  url
                }
              }
            }
          }
        ''',
      }),
    );

    if (response.statusCode == 401) throw const GitHubAuthException();

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final nodes = (data['data']?['search']?['nodes'] as List?) ?? [];
    if (nodes.isEmpty) return null;
    return nodes[0]['url'] as String?;
  }

  /// Decodes [base64Data] in a background isolate and uploads to Supabase Storage.
  ///
  /// Returns the public URL on success, or null on any failure (non-fatal).
  Future<String?> _uploadScreenshot(
    String reportId,
    String base64Data,
  ) async {
    try {
      // Decode on a background isolate to avoid jank on large images.
      final Uint8List bytes = await compute(base64Decode, base64Data);
      final path = '$reportId.png';

      await SupabaseConfig.client.storage
          .from('bug-screenshots')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );

      return SupabaseConfig.client.storage
          .from('bug-screenshots')
          .getPublicUrl(path);
    } catch (_) {
      // Non-fatal: sync proceeds without a screenshot URL.
      return null;
    }
  }

  /// POSTs a new issue to GitHub REST API.
  ///
  /// Returns [html_url] (the GitHub web URL, NOT the API `url` field).
  /// Throws [GitHubAuthException] on 401. Throws generic [Exception] on other failures.
  Future<String> _createGitHubIssue(
    String repo,
    String title,
    String body,
    String token,
  ) async {
    final response = await http.post(
      Uri.parse('https://api.github.com/repos/$repo/issues'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'title': title,
        'body': body,
        'labels': ['bug', 'bug-report'],
      }),
    );

    if (response.statusCode == 401) throw const GitHubAuthException();
    if (response.statusCode != 201) {
      throw Exception('GitHub API error: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    // Use html_url (web URL) — NOT url (API URL that starts with api.github.com).
    return json['html_url'] as String;
  }

  /// Builds the issue title: "[Bug] " + first 80 chars of description.
  String _issueTitle(String description) {
    final truncated = description.length > 80
        ? description.substring(0, 80)
        : description;
    return '[Bug] $truncated';
  }

  /// Builds the issue body in the format matching the existing CLI tools.
  ///
  /// Format:
  /// - Metadata table
  /// - HTML comment with content hash (for dedup)
  /// - Description section
  /// - Screenshot section (if URL available)
  /// - Logs section in collapsible <details> (last 512 KB)
  String _issueBody({
    required String platform,
    required String deviceInfo,
    required String appVersion,
    required String reportId,
    required String contentHash,
    required String description,
    required String? screenshotUrl,
    required String logs,
  }) {
    final buffer = StringBuffer();

    // Metadata table
    buffer.writeln('| Field | Value |');
    buffer.writeln('|-------|-------|');
    buffer.writeln('| Platform | $platform |');
    buffer.writeln('| Device | $deviceInfo |');
    buffer.writeln('| App Version | $appVersion |');
    buffer.writeln('| Report ID | $reportId |');
    buffer.writeln();

    // HTML comment with content hash — used for dedup search
    buffer.writeln('<!-- hash:$contentHash -->');
    buffer.writeln();

    // Description
    buffer.writeln('## Description');
    buffer.writeln();
    buffer.writeln(description);
    buffer.writeln();

    // Screenshot (if available)
    buffer.writeln('## Screenshot');
    buffer.writeln();
    if (screenshotUrl != null) {
      buffer.writeln('![screenshot]($screenshotUrl)');
    } else {
      buffer.writeln('_No screenshot available._');
    }
    buffer.writeln();

    // Logs in collapsible section, truncated to last 512 KB
    buffer.writeln('<details>');
    buffer.writeln('<summary>Logs</summary>');
    buffer.writeln();
    buffer.writeln('```');
    if (logs.isNotEmpty) {
      const maxBytes = 512 * 1024; // 512 KB
      final logBytes = utf8.encode(logs);
      if (logBytes.length > maxBytes) {
        final truncatedBytes = logBytes.sublist(logBytes.length - maxBytes);
        buffer.writeln(utf8.decode(truncatedBytes, allowMalformed: true));
      } else {
        buffer.writeln(logs);
      }
    }
    buffer.writeln('```');
    buffer.writeln();
    buffer.writeln('</details>');

    return buffer.toString();
  }
}
