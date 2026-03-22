class BugReportSummary {
  final String id;
  final String description;
  final String? appVersion;
  final String? platform;
  final DateTime createdAt;
  final String? githubIssueUrl;
  final String sourceApp;

  /// Populated from a parallel triage fetch — NOT from bug_reports columns.
  final String? triageTag;

  const BugReportSummary({
    required this.id,
    required this.description,
    this.appVersion,
    this.platform,
    required this.createdAt,
    this.githubIssueUrl,
    required this.sourceApp,
    this.triageTag,
  });

  factory BugReportSummary.fromJson(Map<String, dynamic> json) {
    return BugReportSummary(
      id: json['id'] as String,
      description: json['description'] as String,
      appVersion: json['app_version'] as String?,
      platform: json['platform'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      githubIssueUrl: json['github_issue_url'] as String?,
      sourceApp: json['source_app'] as String,
      // triageTag is not populated from JSON — comes from parallel triage fetch
    );
  }

  BugReportSummary copyWith({String? triageTag}) {
    return BugReportSummary(
      id: id,
      description: description,
      appVersion: appVersion,
      platform: platform,
      createdAt: createdAt,
      githubIssueUrl: githubIssueUrl,
      sourceApp: sourceApp,
      triageTag: triageTag ?? this.triageTag,
    );
  }

  /// Description truncated to 120 characters with ellipsis if longer.
  String get descriptionPreview {
    if (description.length <= 120) return description;
    return '${description.substring(0, 120)}...';
  }
}
