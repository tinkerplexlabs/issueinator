enum TriageTag {
  issue('issue', 'Issue'),
  feedback('feedback', 'Feedback'),
  duplicate('duplicate', 'Duplicate'),
  notABug('not-a-bug', 'Not a Bug'),
  needsInfo('needs-info', 'Needs Info');

  const TriageTag(this.value, this.label);
  final String value;
  final String label;

  static TriageTag? fromValue(String? value) {
    if (value == null) return null;
    return TriageTag.values.firstWhere(
      (t) => t.value == value,
      orElse: () => throw ArgumentError('Unknown triage tag: $value'),
    );
  }
}

class BugReportTriage {
  final String reportId;
  final TriageTag? tag;
  final String? comment;
  final DateTime? updatedAt;

  const BugReportTriage({
    required this.reportId,
    this.tag,
    this.comment,
    this.updatedAt,
  });

  factory BugReportTriage.fromJson(Map<String, dynamic> json) {
    return BugReportTriage(
      reportId: json['report_id'] as String,
      tag: TriageTag.fromValue(json['triage_tag'] as String?),
      comment: json['comment'] as String?,
      updatedAt:
          json['updated_at'] != null
              ? DateTime.parse(json['updated_at'] as String)
              : null,
    );
  }
}
