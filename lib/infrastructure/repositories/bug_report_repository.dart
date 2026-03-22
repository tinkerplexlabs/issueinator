import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:issueinator/domain/models/bug_report_detail.dart';
import 'package:issueinator/domain/models/bug_report_summary.dart';
import 'package:issueinator/domain/models/product_report_count.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';

class BugReportRepository {
  /// Returns per-product total and unprocessed (no GitHub issue) counts.
  ///
  /// "Unprocessed" in Phase 2 is proxied by github_issue_url IS NULL.
  /// Phase 2 proxy: replace with triage_tag IS NULL in Phase 3.
  Future<List<ProductReportCount>> getProductCounts(
    List<String> productNames,
  ) async {
    final results = <ProductReportCount>[];

    for (final name in productNames) {
      final totalResponse = await SupabaseConfig.client
          .from('bug_reports')
          .select('id')
          .eq('source_app', name)
          .count(CountOption.exact);

      // Phase 2 proxy: replace with triage_tag IS NULL in Phase 3
      final unprocessedResponse = await SupabaseConfig.client
          .from('bug_reports')
          .select('id')
          .eq('source_app', name)
          .isFilter('github_issue_url', null)
          .count(CountOption.exact);

      results.add(
        ProductReportCount(
          productName: name,
          totalCount: totalResponse.count,
          unprocessedCount: unprocessedResponse.count,
        ),
      );
    }

    return results;
  }

  /// Returns a column-projected list of bug reports for [productName].
  ///
  /// CRITICAL: screenshot_base64 is intentionally excluded — it averages
  /// 166–350 KB per row. Use getReportDetail() to fetch the full record.
  Future<List<BugReportSummary>> getReportsByProduct(
    String productName,
  ) async {
    final rows = await SupabaseConfig.client
        .from('bug_reports')
        .select(
          'id, description, app_version, platform, created_at, github_issue_url, source_app',
        )
        .eq('source_app', productName)
        .order('created_at', ascending: false);

    return rows.map((row) => BugReportSummary.fromJson(row)).toList();
  }

  /// Returns the full bug report detail including screenshot_base64.
  ///
  /// Only call this for single-record detail view — NOT in list queries.
  Future<BugReportDetail> getReportDetail(String reportId) async {
    final row = await SupabaseConfig.client
        .from('bug_reports')
        .select('*')
        .eq('id', reportId)
        .single();

    return BugReportDetail.fromJson(row);
  }
}
