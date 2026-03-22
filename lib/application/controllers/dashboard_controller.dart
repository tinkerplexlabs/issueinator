import 'package:flutter/foundation.dart';
import 'package:issueinator/domain/models/product_report_count.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';

class DashboardController extends ChangeNotifier {
  final BugReportRepository _repository;

  List<ProductReportCount> _counts = [];
  bool _isLoading = false;
  String? _error;

  DashboardController(this._repository);

  List<ProductReportCount> get counts => _counts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadCounts(List<String> productNames) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _counts = await _repository.getProductCounts(productNames);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
