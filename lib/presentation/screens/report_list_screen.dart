import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:issueinator/application/controllers/report_list_controller.dart';
import 'package:issueinator/presentation/screens/report_detail_screen.dart';

class ReportListScreen extends StatefulWidget {
  final String productName;

  const ReportListScreen({super.key, required this.productName});

  @override
  State<ReportListScreen> createState() => _ReportListScreenState();
}

class _ReportListScreenState extends State<ReportListScreen> {
  @override
  void initState() {
    super.initState();
    GetIt.instance<ReportListController>().loadReports(widget.productName);
  }

  String get _displayName {
    final name = widget.productName;
    if (name.isEmpty) return name;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName),
      ),
      body: ListenableBuilder(
        listenable: GetIt.instance<ReportListController>(),
        builder: (context, _) {
          final controller = GetIt.instance<ReportListController>();

          if (controller.isLoading && controller.reports.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${controller.error}'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        controller.loadReports(widget.productName),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (controller.reports.isEmpty) {
            return const Center(
              child: Text('No reports for this product'),
            );
          }

          return RefreshIndicator(
            onRefresh: () => controller.refresh(),
            child: ListView.builder(
              itemCount: controller.reports.length,
              itemBuilder: (context, index) {
                final report = controller.reports[index];
                final isSynced = report.githubIssueUrl != null;
                final isUnprocessed = !isSynced;
                // Phase 2 proxy: replace with triage tag display in Phase 3
                final triageColor =
                    isSynced ? Colors.green : Colors.deepOrange;
                final triageIcon =
                    isSynced ? Icons.sync : Icons.error_outline;
                final triageLabel = isSynced ? 'Synced' : 'Unprocessed';

                return Container(
                  color: isUnprocessed
                      ? const Color(0xFF3D2E1E)
                      : null,
                  child: ListTile(
                    title: Text(
                      report.descriptionPreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: isUnprocessed
                          ? Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.bold)
                          : null,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (report.platform != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isUnprocessed
                                      ? Colors.deepOrange.withAlpha(60)
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  report.platform!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        fontWeight: isUnprocessed
                                            ? FontWeight.bold
                                            : null,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              DateFormat('MMM d, yyyy')
                                  .format(report.createdAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(triageIcon, size: 16, color: triageColor),
                        const SizedBox(width: 4),
                        Text(
                          triageLabel,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: triageColor,
                                    fontWeight: isUnprocessed
                                        ? FontWeight.bold
                                        : null,
                                  ),
                        ),
                      ],
                    ),
                    isThreeLine: report.platform != null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ReportDetailScreen(reportId: report.id),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
