import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:issueinator/domain/models/bug_report_detail.dart';
import 'package:issueinator/domain/models/bug_report_summary.dart';
import 'package:issueinator/domain/models/bug_report_triage.dart';
import 'package:issueinator/domain/models/product_report_count.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';

class BugReportRepository {
  /// Returns per-product total and unprocessed counts.
  ///
  /// "Processed" = has a triage_tag OR has a github_issue_url.
  /// Uses parallel fetch: triaged IDs + per-product IDs, then set difference.
  Future<List<ProductReportCount>> getProductCounts(
    List<String> productNames,
  ) async {
    // Fetch all triaged report_ids (with non-null triage_tag) across all products.
    final triagedResponse = await SupabaseConfig.client
        .from('bug_report_triage')
        .select('report_id')
        .not('triage_tag', 'is', null);
    final triagedIds =
        (triagedResponse as List)
            .map((r) => r['report_id'] as String)
            .toSet();

    final results = <ProductReportCount>[];

    for (final name in productNames) {
      // Fetch IDs and github_issue_url for this product.
      final productResponse = await SupabaseConfig.client
          .from('bug_reports')
          .select('id, github_issue_url')
          .eq('source_app', name);
      final productRows = productResponse as List;

      // A report is processed if it has a triage tag or a github_issue_url.
      final unprocessedCount = productRows.where((r) {
        final id = r['id'] as String;
        final hasGithubUrl = r['github_issue_url'] != null;
        return !triagedIds.contains(id) && !hasGithubUrl;
      }).length;

      results.add(
        ProductReportCount(
          productName: name,
          totalCount: productRows.length,
          unprocessedCount: unprocessedCount,
        ),
      );
    }

    return results;
  }

  /// Returns a column-projected list of bug reports for [productName],
  /// enriched with triage data from a parallel fetch.
  ///
  /// CRITICAL: screenshot_base64 is intentionally excluded — it averages
  /// 166–350 KB per row. Use getReportDetail() to fetch the full record.
  Future<List<BugReportSummary>> getReportsByProduct(
    String productName,
  ) async {
    // Parallel fetch: bug_reports + all triage rows
    final results = await Future.wait([
      SupabaseConfig.client
          .from('bug_reports')
          .select(
            'id, description, app_version, platform, created_at, github_issue_url, source_app',
          )
          .eq('source_app', productName)
          .order('created_at', ascending: false),
      SupabaseConfig.client
          .from('bug_report_triage')
          .select('report_id, triage_tag'),
    ]);

    final rows = results[0] as List<dynamic>;
    final triagedRows = results[1] as List<dynamic>;

    // Build triage lookup map keyed by report_id
    final triageMap = <String, String?>{};
    for (final t in triagedRows) {
      triageMap[t['report_id'] as String] = t['triage_tag'] as String?;
    }

    return rows.map((row) {
      final summary = BugReportSummary.fromJson(row as Map<String, dynamic>);
      final tag = triageMap[summary.id];
      return tag != null ? summary.copyWith(triageTag: tag) : summary;
    }).toList();
  }

  /// Returns bug report detail WITHOUT screenshot_base64.
  /// Use [getReportScreenshot] to fetch the screenshot separately.
  Future<BugReportDetail> getReportDetail(String reportId) async {
    final row = await SupabaseConfig.client
        .from('bug_reports')
        .select(
          'id, description, app_version, platform, created_at, github_issue_url, source_app, device_info, logs, user_id',
        )
        .eq('id', reportId)
        .single();

    return BugReportDetail.fromJson(row);
  }

  /// Returns the screenshot_base64 string for a single report, or null.
  Future<String?> getReportScreenshot(String reportId) async {
    final row = await SupabaseConfig.client
        .from('bug_reports')
        .select('screenshot_base64')
        .eq('id', reportId)
        .single();

    return row['screenshot_base64'] as String?;
  }

  // ---------------------------------------------------------------------------
  // Triage methods
  // ---------------------------------------------------------------------------

  /// Upserts a triage record for [reportId].
  ///
  /// Pass [tag] and/or [comment] — only non-null values are written.
  /// Always updates [updated_at].
  Future<void> saveTriage(
    String reportId, {
    String? tag,
    String? comment,
  }) async {
    await SupabaseConfig.client.from('bug_report_triage').upsert(
      {
        'report_id': reportId,
        if (tag != null) 'triage_tag': tag,
        if (comment != null) 'comment': comment,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'report_id',
    );
  }

  /// Returns the triage record for [reportId], or null if none exists.
  Future<BugReportTriage?> getTriageForReport(String reportId) async {
    final rows = await SupabaseConfig.client
        .from('bug_report_triage')
        .select('report_id, triage_tag, comment, updated_at')
        .eq('report_id', reportId);

    final list = rows as List;
    if (list.isEmpty) return null;
    return BugReportTriage.fromJson(list.first as Map<String, dynamic>);
  }

  /// Updates github_issue_url on the bug_reports table for [reportId].
  Future<void> updateGithubIssueUrl(String reportId, String url) async {
    await SupabaseConfig.client
        .from('bug_reports')
        .update({'github_issue_url': url})
        .eq('id', reportId);
  }

  /// Batch-upserts [tag] for all [reportIds] in a single Supabase call.
  Future<void> batchSaveTriage(List<String> reportIds, String tag) async {
    final now = DateTime.now().toIso8601String();
    final rows =
        reportIds
            .map(
              (id) => {
                'report_id': id,
                'triage_tag': tag,
                'updated_at': now,
              },
            )
            .toList();

    await SupabaseConfig.client
        .from('bug_report_triage')
        .upsert(rows, onConflict: 'report_id');
  }
}
