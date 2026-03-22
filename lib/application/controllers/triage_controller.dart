import 'package:flutter/foundation.dart';
import 'package:issueinator/domain/models/bug_report_triage.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';

class TriageController extends ChangeNotifier {
  final BugReportRepository _repository;

  TriageController(this._repository);

  bool _isSaving = false;
  String? _error;

  bool get isSaving => _isSaving;
  String? get error => _error;

  /// Applies [tag] to [reportId]. Returns true on success.
  Future<bool> applyTag(String reportId, TriageTag tag) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      await _repository.saveTriage(reportId, tag: tag.value);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Saves a [comment] for [reportId]. Returns true on success.
  Future<bool> saveComment(String reportId, String comment) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      await _repository.saveTriage(reportId, comment: comment);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Returns the triage record for [reportId], or null if none exists.
  Future<BugReportTriage?> getTriage(String reportId) async {
    return _repository.getTriageForReport(reportId);
  }
}
