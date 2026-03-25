import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:issueinator/core/dev_log.dart';
import 'package:issueinator/domain/models/product_report_count.dart';
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';

class DashboardController extends ChangeNotifier {
  final BugReportRepository _repository;
  final GitHubAuthService _githubAuthService;

  List<ProductReportCount> _counts = [];
  bool _isLoading = false;
  String? _error;

  DashboardController(this._repository, this._githubAuthService);

  List<ProductReportCount> get counts => _counts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadCounts(List<String> productNames) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Sync uncached GitHub issue states before counting.
      await _refreshUncachedGithubStates();
      _counts = await _repository.getProductCounts(productNames);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches GitHub issue state for all synced reports that don't have a
  /// cached state. Runs in parallel batches for speed.
  Future<void> _refreshUncachedGithubStates() async {
    final token = await _githubAuthService.getStoredToken();
    if (token == null) return;

    final uncached = await _repository.getUncachedGithubIssues();
    if (uncached.isEmpty) return;

    devLog('[Dashboard] Checking GitHub state for ${uncached.length} issues');

    // Process in parallel batches of 10 to avoid hammering the API.
    const batchSize = 10;
    for (var i = 0; i < uncached.length; i += batchSize) {
      final batch = uncached.skip(i).take(batchSize);
      await Future.wait(batch.map((entry) async {
        try {
          final state = await _fetchIssueState(entry['url']!, token);
          if (state != null) {
            await _repository.updateGithubIssueState(entry['id']!, state);
          }
        } catch (e) {
          devLog('[Dashboard] Failed to check ${entry['id']}: $e');
        }
      }));
    }

    devLog('[Dashboard] GitHub state sync complete');
  }

  Future<String?> _fetchIssueState(String htmlUrl, String token) async {
    final uri = Uri.parse(htmlUrl);
    final segments = uri.pathSegments;
    if (segments.length < 4) return null;

    final apiUrl =
        'https://api.github.com/repos/${segments[0]}/${segments[1]}/issues/${segments[3]}';
    final response = await http.get(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
      },
    );

    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['state'] as String?;
  }
}
