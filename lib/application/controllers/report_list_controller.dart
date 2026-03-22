import 'package:flutter/foundation.dart';
import 'package:issueinator/domain/models/bug_report_summary.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';

class ReportListController extends ChangeNotifier {
  final BugReportRepository _repository;

  List<BugReportSummary> _reports = [];
  bool _isLoading = false;
  String? _error;
  String? _currentProduct;

  ReportListController(this._repository);

  List<BugReportSummary> get reports => _reports;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get currentProduct => _currentProduct;

  Future<void> loadReports(String productName) async {
    _currentProduct = productName;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _reports = await _repository.getReportsByProduct(productName);
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
}
