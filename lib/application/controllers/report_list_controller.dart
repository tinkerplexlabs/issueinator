import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:issueinator/core/dev_log.dart';
import 'package:issueinator/domain/models/bug_report_summary.dart';
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';

class ReportListController extends ChangeNotifier {
  final BugReportRepository _repository;
  final GitHubAuthService _githubAuthService;

  List<BugReportSummary> _reports = [];
  bool _isLoading = false;
  String? _error;
  String? _currentProduct;

  // Multi-select state
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  ReportListController(this._repository, this._githubAuthService);

  List<BugReportSummary> get reports => _reports;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get currentProduct => _currentProduct;

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  bool get isSelectionMode => _isSelectionMode;
  int get selectedCount => _selectedIds.length;

  Future<void> loadReports(String productName) async {
    _currentProduct = productName;
    _isLoading = true;
    _error = null;
    // CRITICAL (Pitfall 4): Clear selection when loading a different product
    // to prevent cross-product selection leaks.
    clearSelection();
    notifyListeners();

    try {
      final reports = await _repository.getReportsByProduct(productName);

      // Check GitHub issue states for synced reports without cached state.
      await _refreshGitHubStates(reports);

      // Filter out closed GitHub issues, then sort.
      final visible = reports.where((r) => !r.isClosedOnGitHub).toList();
      visible.sort((a, b) {
        final aUnprocessed = a.triageTag == null && a.githubIssueUrl == null;
        final bUnprocessed = b.triageTag == null && b.githubIssueUrl == null;
        if (aUnprocessed != bUnprocessed) return aUnprocessed ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      _reports = visible;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Checks GitHub for issue states on synced reports that don't have a
  /// cached state yet. Updates the DB and the in-memory list.
  Future<void> _refreshGitHubStates(List<BugReportSummary> reports) async {
    final token = await _githubAuthService.getStoredToken();
    if (token == null) return;

    final needsCheck = reports.where(
      (r) => r.githubIssueUrl != null && r.githubIssueState == null,
    ).toList();

    if (needsCheck.isEmpty) return;

    devLog('[ReportList] Checking GitHub state for ${needsCheck.length} issues');

    for (final report in needsCheck) {
      try {
        final state = await _fetchIssueState(report.githubIssueUrl!, token);
        if (state != null) {
          await _repository.updateGithubIssueState(report.id, state);
          // Update in-memory model
          final idx = reports.indexWhere((r) => r.id == report.id);
          if (idx >= 0) {
            reports[idx] = reports[idx].copyWith(githubIssueState: state);
          }
        }
      } catch (e) {
        devLog('[ReportList] Failed to check state for ${report.id}: $e');
      }
    }
  }

  /// Fetches the issue state (open/closed) from the GitHub API.
  /// Converts html_url to API url: github.com/owner/repo/issues/N → api.github.com/repos/owner/repo/issues/N
  Future<String?> _fetchIssueState(String htmlUrl, String token) async {
    // Parse: https://github.com/owner/repo/issues/123
    final uri = Uri.parse(htmlUrl);
    final segments = uri.pathSegments; // [owner, repo, issues, 123]
    if (segments.length < 4) return null;

    final apiUrl = 'https://api.github.com/repos/${segments[0]}/${segments[1]}/issues/${segments[3]}';
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

  /// Reload the current product's reports (for pull-to-refresh).
  Future<void> refresh() async {
    if (_currentProduct == null) return;
    await loadReports(_currentProduct!);
  }

  // ---------------------------------------------------------------------------
  // Multi-select methods
  // ---------------------------------------------------------------------------

  void enterSelectionMode(String firstId) {
    _isSelectionMode = true;
    _selectedIds.add(firstId);
    notifyListeners();
  }

  void toggleSelection(String reportId) {
    if (_selectedIds.contains(reportId)) {
      _selectedIds.remove(reportId);
      if (_selectedIds.isEmpty) _isSelectionMode = false;
    } else {
      _selectedIds.add(reportId);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  Future<void> batchTag(String tag, BugReportRepository repo) async {
    await repo.batchSaveTriage(_selectedIds.toList(), tag);
    clearSelection();
    await refresh();
  }
}
