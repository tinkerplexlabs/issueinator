import 'package:flutter/foundation.dart';

import 'package:issueinator/domain/models/bug_report_detail.dart';
import 'package:issueinator/domain/models/sync_result.dart';
import 'package:issueinator/domain/services/github_sync_service.dart';

/// ChangeNotifier that manages UI state for GitHub sync operations.
///
/// Guards against double-tap via [isSyncing] flag.
class SyncController extends ChangeNotifier {
  final GitHubSyncService _syncService;

  SyncController(this._syncService);

  bool _isSyncing = false;
  SyncResult? _lastResult;

  bool get isSyncing => _isSyncing;
  SyncResult? get lastResult => _lastResult;

  /// Syncs [detail] to GitHub. Returns a [SyncResult] describing the outcome.
  ///
  /// Returns [SyncError('Already syncing')] if a sync is already in progress.
  Future<SyncResult> sync(String reportId, BugReportDetail detail) async {
    if (_isSyncing) return const SyncError('Already syncing');

    _isSyncing = true;
    _lastResult = null;
    notifyListeners();

    try {
      final result = await _syncService.syncReport(reportId, detail);
      _lastResult = result;
      return result;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Clears the last sync result (e.g. after the user dismisses a snackbar).
  void clearResult() {
    _lastResult = null;
    notifyListeners();
  }
}
