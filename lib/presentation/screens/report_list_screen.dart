import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:issueinator/application/controllers/report_list_controller.dart';
import 'package:issueinator/domain/models/bug_report_triage.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';
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

  IconData _iconForTag(TriageTag tag) {
    return switch (tag) {
      TriageTag.issue => Icons.bug_report,
      TriageTag.feedback => Icons.chat_bubble_outline,
      TriageTag.duplicate => Icons.content_copy,
      TriageTag.notABug => Icons.check_circle_outline,
      TriageTag.needsInfo => Icons.help_outline,
    };
  }

  Color _colorForTag(TriageTag tag) {
    return switch (tag) {
      TriageTag.issue => Colors.red,
      TriageTag.feedback => Colors.blue,
      TriageTag.duplicate => Colors.grey,
      TriageTag.notABug => Colors.green,
      TriageTag.needsInfo => Colors.orange,
    };
  }

  void _showBatchTagPicker(
    BuildContext context,
    ReportListController controller,
  ) {
    showModalBottomSheet(
      context: context,
      builder:
          (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Tag Selected Reports',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ...TriageTag.values.map(
                  (tag) => ListTile(
                    leading: Icon(_iconForTag(tag), color: _colorForTag(tag)),
                    title: Text(tag.label),
                    onTap: () async {
                      Navigator.pop(context);
                      final repo = GetIt.instance<BugReportRepository>();
                      await controller.batchTag(tag.value, repo);
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GetIt.instance<ReportListController>(),
      builder: (context, _) {
        final controller = GetIt.instance<ReportListController>();

        return PopScope(
          canPop: !controller.isSelectionMode,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) controller.clearSelection();
          },
          child: Scaffold(
            appBar: _buildAppBar(context, controller),
            body: _buildBody(context, controller),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ReportListController controller,
  ) {
    if (controller.isSelectionMode) {
      return AppBar(
        leading: IconButton(
          icon: SvgPicture.asset(
            'assets/images/close-icon.svg',
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(
              Theme.of(context).appBarTheme.foregroundColor ?? Colors.white,
              BlendMode.srcIn,
            ),
          ),
          onPressed: () => controller.clearSelection(),
        ),
        title: Text('${controller.selectedCount} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Select all',
            onPressed: () {
              for (final r in controller.reports) {
                if (!controller.selectedIds.contains(r.id)) {
                  controller.toggleSelection(r.id);
                }
              }
            },
          ),
        ],
      );
    }

    return AppBar(
      leading: IconButton(
        icon: SvgPicture.asset(
          'assets/images/backarrow-icon.svg',
          width: 24,
          height: 24,
          colorFilter: ColorFilter.mode(
            Theme.of(context).appBarTheme.foregroundColor ?? Colors.white,
            BlendMode.srcIn,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(_displayName),
    );
  }

  Widget _buildBody(BuildContext context, ReportListController controller) {
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
              onPressed: () => controller.loadReports(widget.productName),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (controller.reports.isEmpty) {
      return const Center(child: Text('No reports for this product'));
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => controller.refresh(),
            child: ListView.builder(
              itemCount: controller.reports.length,
              itemBuilder: (context, index) {
                final report = controller.reports[index];
                final triageTag = report.triageTag;
                final hasTag = triageTag != null;
                final isSynced = report.githubIssueUrl != null && !hasTag;
                final isUnprocessed = !hasTag && !isSynced;
                final isSelected = controller.selectedIds.contains(report.id);

                // Determine display properties based on triage state
                Color triageColor;
                IconData triageIcon;
                String triageLabel;

                if (triageTag == null && report.githubIssueUrl != null) {
                  triageColor = Colors.teal;
                  triageIcon = Icons.link;
                  triageLabel = 'Synced';
                } else if (triageTag == null) {
                  triageColor = Colors.deepOrange;
                  triageIcon = Icons.error_outline;
                  triageLabel = 'Unprocessed';
                } else {
                  switch (triageTag) {
                    case 'issue':
                      triageColor = Colors.red;
                      triageIcon = Icons.bug_report;
                      triageLabel = 'Issue';
                    case 'feedback':
                      triageColor = Colors.blue;
                      triageIcon = Icons.chat_bubble_outline;
                      triageLabel = 'Feedback';
                    case 'duplicate':
                      triageColor = Colors.grey;
                      triageIcon = Icons.content_copy;
                      triageLabel = 'Duplicate';
                    case 'not-a-bug':
                      triageColor = Colors.green;
                      triageIcon = Icons.check_circle_outline;
                      triageLabel = 'Not a Bug';
                    case 'needs-info':
                      triageColor = Colors.orange;
                      triageIcon = Icons.help_outline;
                      triageLabel = 'Needs Info';
                    default:
                      triageColor = Colors.grey;
                      triageIcon = Icons.label_outline;
                      triageLabel = triageTag;
                  }
                }

                return Container(
                  color:
                      isSelected
                          ? Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withAlpha(80)
                          : isUnprocessed
                          ? const Color(0xFF3D2E1E)
                          : null,
                  child: Opacity(
                    opacity: isSynced ? 0.5 : 1.0,
                    child: ListTile(
                    leading:
                        controller.isSelectionMode
                            ? Checkbox(
                              value: isSelected,
                              onChanged:
                                  (_) => controller.toggleSelection(report.id),
                            )
                            : null,
                    title: Text(
                      report.descriptionPreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          isUnprocessed
                              ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              )
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
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      isUnprocessed
                                          ? Colors.deepOrange.withAlpha(60)
                                          : Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  report.platform!,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(
                                    fontWeight:
                                        isUnprocessed ? FontWeight.bold : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              DateFormat('MMM d, yyyy').format(report.createdAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: isSynced
                        ? TextButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(report.githubIssueUrl!),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text('GitHub'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(triageIcon, size: 16, color: triageColor),
                              const SizedBox(width: 4),
                              Text(
                                triageLabel,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: triageColor,
                                  fontWeight:
                                      isUnprocessed ? FontWeight.bold : null,
                                ),
                              ),
                              if (report.githubIssueUrl != null) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.link,
                                  size: 14,
                                  color: Colors.green,
                                ),
                              ],
                            ],
                          ),
                    isThreeLine: report.platform != null,
                    onLongPress: () {
                      if (!controller.isSelectionMode) {
                        controller.enterSelectionMode(report.id);
                      }
                    },
                    onTap: () {
                      if (controller.isSelectionMode) {
                        controller.toggleSelection(report.id);
                      } else if (isSynced && report.githubIssueUrl != null) {
                        launchUrl(
                          Uri.parse(report.githubIssueUrl!),
                          mode: LaunchMode.externalApplication,
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) =>
                                    ReportDetailScreen(reportId: report.id),
                          ),
                        ).then((_) => controller.refresh());
                      }
                    },
                  ),
                  ),
                );
              },
            ),
          ),
        ),
        // Bottom action bar — shown when in selection mode with selections
        if (controller.isSelectionMode && controller.selectedCount > 0)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              boxShadow: const [
                BoxShadow(blurRadius: 4, color: Colors.black26),
              ],
            ),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${controller.selectedCount} selected'),
                  FilledButton.icon(
                    onPressed:
                        () => _showBatchTagPicker(context, controller),
                    icon: const Icon(Icons.label),
                    label: const Text('Tag selected'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
