import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:issueinator/application/controllers/sync_controller.dart';
import 'package:issueinator/application/controllers/triage_controller.dart';
import 'package:issueinator/domain/models/bug_report_detail.dart';
import 'package:issueinator/domain/models/bug_report_triage.dart';
import 'package:issueinator/domain/models/sync_result.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';
import 'package:issueinator/presentation/widgets/github_device_flow_dialog.dart';

class ReportDetailScreen extends StatefulWidget {
  final String reportId;

  const ReportDetailScreen({super.key, required this.reportId});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  BugReportDetail? _detail;
  bool _isLoading = true;
  String? _error;
  Uint8List? _screenshotBytes;
  bool _screenshotLoading = false;
  bool _showFullLogs = false;

  BugReportTriage? _triage;
  final TextEditingController _commentController = TextEditingController();
  final SyncController _syncController = GetIt.instance<SyncController>();

  /// 512 KB log truncation limit
  static const int _logTruncateBytes = 512 * 1024;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = GetIt.instance<BugReportRepository>();
      final detail = await repo.getReportDetail(widget.reportId);

      if (mounted) {
        setState(() {
          _detail = detail;
          _isLoading = false;
        });
      }

      // Fetch triage data after detail loads
      final triageController = GetIt.instance<TriageController>();
      final triage = await triageController.getTriage(widget.reportId);
      if (mounted) {
        setState(() {
          _triage = triage;
          _commentController.text = triage?.comment ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadScreenshot(BugReportRepository repo) async {
    setState(() => _screenshotLoading = true);
    try {
      final b64 = await repo.getReportScreenshot(widget.reportId);
      if (b64 != null && mounted) {
        final bytes = await compute(base64Decode, b64);
        if (mounted) {
          setState(() {
            _screenshotBytes = bytes;
            _screenshotLoading = false;
          });
        }
      } else if (mounted) {
        setState(() => _screenshotLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _screenshotLoading = false);
    }
  }

  Future<void> _launchGitHubUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: $url')),
        );
      }
    }
  }

  Future<void> _syncReport(BuildContext context) async {
    // Capture refs before any await per project convention (03-02 decision).
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await _syncController.sync(widget.reportId, _detail!);
    switch (result) {
      case SyncSuccess(:final issueUrl):
        messenger.showSnackBar(
          SnackBar(
            content: const Text('GitHub issue created'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _launchGitHubUrl(issueUrl),
            ),
          ),
        );
        _fetchDetail();
      case SyncDuplicate(:final existingUrl):
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Existing GitHub issue linked'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _launchGitHubUrl(existingUrl),
            ),
          ),
        );
        _fetchDetail();
      case SyncError(:final message, :final requiresReAuth):
        if (requiresReAuth) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('GitHub token expired — please re-authenticate'),
            ),
          );
          if (mounted) {
            await showModalBottomSheet<void>(
              context: navigator.context,
              isDismissible: false,
              enableDrag: false,
              builder: (_) => const GitHubDeviceFlowSheet(),
            );
          }
        } else {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
    }
  }

  void _showTagPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Apply Triage Tag',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...TriageTag.values.map(
              (tag) => ListTile(
                leading: Icon(_iconForTag(tag), color: _colorForTag(tag)),
                title: Text(tag.label),
                trailing: _triage?.tag == tag ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(context);
                  _applyTag(tag);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyTag(TriageTag tag) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = GetIt.instance<TriageController>();
    final success = await controller.applyTag(widget.reportId, tag);
    if (success && mounted) {
      // Re-fetch triage to confirm persistence
      final triage = await controller.getTriage(widget.reportId);
      setState(() => _triage = triage);
    } else if (mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to apply tag: ${controller.error}')),
      );
    }
  }

  Future<void> _saveComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = GetIt.instance<TriageController>();
    final success = await controller.saveComment(widget.reportId, text);
    if (success && mounted) {
      final triage = await controller.getTriage(widget.reportId);
      setState(() => _triage = triage);
      messenger.showSnackBar(
        const SnackBar(content: Text('Comment saved')),
      );
    } else if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to save comment: ${controller.error}'),
        ),
      );
    }
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

  Color _chipColorForTag(TriageTag? tag) {
    if (tag == null) return Colors.grey.shade600;
    return _colorForTag(tag);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
        title: Text(
          _detail != null
              ? 'Report ${widget.reportId.substring(0, 8)}…'
              : 'Report Detail',
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _fetchDetail,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final detail = _detail!;
    final dateFormat = DateFormat('MMMM d, yyyy h:mm a');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Status bar
          _buildStatusBar(context, detail),
          const SizedBox(height: 24),

          // Section 2: Triage comment
          _buildTriageComment(context),
          const SizedBox(height: 24),

          // Section 3: Core fields
          _buildCoreFields(context, detail, dateFormat),
          const SizedBox(height: 24),

          // Section 4: Device info
          _buildDeviceInfo(context, detail),
          const SizedBox(height: 24),

          // Section 5: Logs
          _buildLogs(context, detail),
          const SizedBox(height: 24),

          // Section 6: Screenshot
          _buildScreenshot(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, BugReportDetail detail) {
    final currentTag = _triage?.tag;
    final isDuplicate = currentTag == TriageTag.duplicate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tappable triage chip
        ActionChip(
          avatar: Icon(
            currentTag != null ? _iconForTag(currentTag) : Icons.label_outline,
            size: 16,
            color: _chipColorForTag(currentTag),
          ),
          label: Text(
            currentTag?.label ?? 'Not yet triaged',
            style: TextStyle(color: _chipColorForTag(currentTag)),
          ),
          onPressed: () => _showTagPicker(context),
        ),
        const SizedBox(height: 8),

        // Sync status slot
        if (isDuplicate)
          const Chip(label: Text('Duplicate — excluded from GitHub sync'))
        else if (detail.githubIssueUrl != null)
          ActionChip(
            avatar: const Icon(Icons.open_in_new, size: 16),
            label: const Text('View GitHub Issue'),
            onPressed: () => _launchGitHubUrl(detail.githubIssueUrl!),
          )
        else if (currentTag == TriageTag.issue ||
            currentTag == TriageTag.feedback ||
            currentTag == TriageTag.needsInfo)
          ListenableBuilder(
            listenable: _syncController,
            builder: (context, _) {
              final isSyncing = _syncController.isSyncing;
              return FilledButton.icon(
                onPressed: isSyncing ? null : () => _syncReport(context),
                icon: isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload),
                label: Text(isSyncing ? 'Syncing\u2026' : 'Sync to GitHub'),
              );
            },
          )
        else
          Text(
            'Not synced to GitHub',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
      ],
    );
  }

  Widget _buildTriageComment(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Triage Comment', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _commentController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Add a comment...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saveComment,
          child: const Text('Save Comment'),
        ),
      ],
    );
  }

  Widget _buildCoreFields(
    BuildContext context,
    BugReportDetail detail,
    DateFormat dateFormat,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelValue(context, 'Description', detail.description),
        const SizedBox(height: 12),
        _labelValue(context, 'Platform', detail.platform ?? 'Unknown'),
        const SizedBox(height: 12),
        _labelValue(context, 'App Version', detail.appVersion ?? 'Unknown'),
        const SizedBox(height: 12),
        _labelValue(
          context,
          'Created At',
          dateFormat.format(detail.createdAt.toLocal()),
        ),
      ],
    );
  }

  Widget _labelValue(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildDeviceInfo(BuildContext context, BugReportDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Device Info', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            detail.deviceInfo ?? 'No device info available',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFFD4D4D4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogs(BuildContext context, BugReportDetail detail) {
    final hasLogs = detail.logs != null && detail.logs!.isNotEmpty;
    if (!hasLogs) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Logs', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            'No logs available',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
        ],
      );
    }

    final fullLogs = detail.logs!;
    final isOversized = fullLogs.length > _logTruncateBytes;
    final displayLogs = _showFullLogs || !isOversized
        ? fullLogs
        : fullLogs.substring(fullLogs.length - _logTruncateBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Logs', style: Theme.of(context).textTheme.titleSmall),
            if (isOversized) ...[
              const SizedBox(width: 8),
              Text(
                '(${(fullLogs.length / 1024).toStringAsFixed(0)} KB)',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (isOversized && !_showFullLogs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Showing last 512 KB of ${(fullLogs.length / 1024).toStringAsFixed(0)} KB',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.orange),
            ),
          ),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 400),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              displayLogs,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFD4D4D4),
              ),
            ),
          ),
        ),
        if (isOversized)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _showFullLogs = !_showFullLogs),
              icon: Icon(_showFullLogs ? Icons.compress : Icons.expand),
              label: Text(
                _showFullLogs
                    ? 'Show truncated (512 KB)'
                    : 'Show full logs (${(fullLogs.length / 1024).toStringAsFixed(0)} KB)',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildScreenshot(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Screenshot', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_screenshotBytes != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: InteractiveViewer(
              child: Image.memory(_screenshotBytes!),
            ),
          )
        else if (_screenshotLoading)
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(height: 8),
                  Text('Loading screenshot...',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  _loadScreenshot(GetIt.instance<BugReportRepository>()),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Load screenshot'),
            ),
          ),
      ],
    );
  }
}
