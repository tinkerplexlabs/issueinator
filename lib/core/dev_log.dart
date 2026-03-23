import 'package:flutter/foundation.dart';
import 'package:issueinator/infrastructure/debug/bug_report_log_buffer.dart';

/// Debug-mode-only logging. No-ops console output in release builds,
/// but always captures to the bug report log buffer.
void devLog(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[IssueInator] $message');
  }

  // Always capture to bug report buffer for potential bug reports
  BugReportLogBuffer().append(message);
}
