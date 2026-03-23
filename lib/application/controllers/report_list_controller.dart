import 'package:flutter/foundation.dart';
import 'package:issueinator/domain/models/bug_report_summary.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';

class ReportListController extends ChangeNotifier {
  final BugReportRepository _repository;

  List<BugReportSummary> _reports = [];
  bool _isLoading = false;
  String? _error;
  String? _currentProduct;

  // Multi-select state
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  ReportListController(this._repository);

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
      // Sort: unprocessed first (no tag and no github URL), then by date desc.
      reports.sort((a, b) {
        final aUnprocessed = a.triageTag == null && a.githubIssueUrl == null;
        final bUnprocessed = b.triageTag == null && b.githubIssueUrl == null;
        if (aUnprocessed != bUnprocessed) return aUnprocessed ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      _reports = reports;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
