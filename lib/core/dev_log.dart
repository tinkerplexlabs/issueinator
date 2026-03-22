import 'package:flutter/foundation.dart';

/// Debug-mode-only logging. No-ops in release builds.
void devLog(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[IssueInator] $message');
  }
}
