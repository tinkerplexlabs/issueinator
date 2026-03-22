class BugReportDetail {
  final String id;
  final String description;
  final String? appVersion;
  final String? platform;
  final DateTime createdAt;
  final String? githubIssueUrl;
  final String sourceApp;
  final String? deviceInfo;
  final String? logs;
  final String? screenshotBase64;
  final String? userId;

  const BugReportDetail({
    required this.id,
    required this.description,
    this.appVersion,
    this.platform,
    required this.createdAt,
    this.githubIssueUrl,
    required this.sourceApp,
    this.deviceInfo,
    this.logs,
    this.screenshotBase64,
    this.userId,
  });

  factory BugReportDetail.fromJson(Map<String, dynamic> json) {
    return BugReportDetail(
      id: json['id'] as String,
      description: json['description'] as String,
      appVersion: json['app_version'] as String?,
      platform: json['platform'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      githubIssueUrl: json['github_issue_url'] as String?,
      sourceApp: json['source_app'] as String,
      deviceInfo: json['device_info'] as String?,
      logs: json['logs'] as String?,
      screenshotBase64: json['screenshot_base64'] as String?,
      userId: json['user_id'] as String?,
    );
  }
}
