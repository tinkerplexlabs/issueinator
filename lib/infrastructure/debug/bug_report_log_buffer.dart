import 'dart:collection';

/// A log entry with timestamp and optional metadata
class _LogEntry {
  final DateTime timestamp;
  final String message;
  final String? category;
  final int sizeBytes;

  _LogEntry({
    required this.timestamp,
    required this.message,
    this.category,
  }) : sizeBytes = _calculateSize(message, category);

  static int _calculateSize(String message, String? category) {
    // Estimate: timestamp (24) + category (avg 15) + message + separators
    return 40 + (category?.length ?? 0) + message.length;
  }

  String format() {
    final ts = timestamp.toIso8601String();
    if (category != null) {
      return '[$ts] [$category] $message';
    }
    return '[$ts] $message';
  }
}

/// Size-based circular log buffer for bug reports
///
/// Maintains a rolling window of application logs in memory.
/// Default export is capped at 500KB to fit within typical AI context
/// windows alongside screenshots and descriptions. An extended mode
/// exports the full buffer (up to 2MB) for deeper investigation.
class BugReportLogBuffer {
  /// Maximum buffer size in memory: 2MB
  static const int maxSizeBytes = 2 * 1024 * 1024;

  /// Default export limit: 500KB (fits in typical context window)
  static const int defaultExportBytes = 500 * 1024;

  /// Extended export limit: full buffer
  static const int extendedExportBytes = maxSizeBytes;

  // Singleton instance
  static final BugReportLogBuffer _instance = BugReportLogBuffer._internal();

  /// Get the singleton instance
  factory BugReportLogBuffer() => _instance;

  BugReportLogBuffer._internal();

  /// Ring buffer of log entries
  final Queue<_LogEntry> _entries = Queue<_LogEntry>();

  /// Current total size in bytes
  int _currentSizeBytes = 0;

  /// Whether logging is enabled
  bool _enabled = true;

  /// Get current buffer size in bytes
  int get currentSizeBytes => _currentSizeBytes;

  /// Get number of entries
  int get entryCount => _entries.length;

  /// Enable or disable log capture
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Append a log message to the buffer
  void append(String message,
      {String? category, Map<String, dynamic>? data}) {
    if (!_enabled) return;

    String formattedMessage = message;
    if (data != null && data.isNotEmpty) {
      formattedMessage = '$message $data';
    }

    final entry = _LogEntry(
      timestamp: DateTime.now(),
      message: formattedMessage,
      category: category,
    );

    _entries.addLast(entry);
    _currentSizeBytes += entry.sizeBytes;

    // Remove oldest entries until under size limit
    while (_currentSizeBytes > maxSizeBytes && _entries.isNotEmpty) {
      final removed = _entries.removeFirst();
      _currentSizeBytes -= removed.sizeBytes;
    }
  }

  /// Export logs as plain text, capped to a byte limit.
  String export({bool extended = false}) {
    if (_entries.isEmpty) {
      return '[No logs captured]';
    }

    final limit = extended ? extendedExportBytes : defaultExportBytes;
    final selected = _selectEntries(limit);

    final buffer = StringBuffer();
    buffer.writeln('=== Application Logs ===');
    buffer.writeln('Entries: ${selected.length} of ${_entries.length}');
    buffer.writeln(
        'Buffer: ${(_currentSizeBytes / 1024).toStringAsFixed(1)} KB');
    if (!extended && selected.length < _entries.length) {
      buffer.writeln(
          '(truncated to ~${(limit / 1024).toInt()} KB — use extended context for full logs)');
    }
    buffer.writeln('');

    for (final entry in selected) {
      buffer.writeln(entry.format());
    }

    return buffer.toString();
  }

  /// Export logs as markdown-formatted text, capped to a byte limit.
  String exportAsMarkdown({bool extended = false}) {
    if (_entries.isEmpty) {
      return '*No logs captured*';
    }

    final limit = extended ? extendedExportBytes : defaultExportBytes;
    final selected = _selectEntries(limit);

    final buffer = StringBuffer();
    buffer.writeln('```');
    for (final entry in selected) {
      buffer.writeln(entry.format());
    }
    buffer.writeln('```');

    return buffer.toString();
  }

  /// Select the most recent entries that fit within [maxBytes].
  List<_LogEntry> _selectEntries(int maxBytes) {
    if (_currentSizeBytes <= maxBytes) {
      return _entries.toList();
    }

    final selected = <_LogEntry>[];
    int accumulated = 0;
    for (final entry in _entries.toList().reversed) {
      if (accumulated + entry.sizeBytes > maxBytes) break;
      selected.add(entry);
      accumulated += entry.sizeBytes;
    }
    return selected.reversed.toList();
  }

  /// Clear all logs
  void clear() {
    _entries.clear();
    _currentSizeBytes = 0;
  }

  /// Get summary statistics
  Map<String, dynamic> getStats() {
    return {
      'entryCount': _entries.length,
      'sizeBytes': _currentSizeBytes,
      'sizeKB': (_currentSizeBytes / 1024).toStringAsFixed(1),
      'sizeMB': (_currentSizeBytes / (1024 * 1024)).toStringAsFixed(2),
      'maxSizeMB': (maxSizeBytes / (1024 * 1024)).toStringAsFixed(0),
      'percentFull':
          ((_currentSizeBytes / maxSizeBytes) * 100).toStringAsFixed(1),
    };
  }
}
