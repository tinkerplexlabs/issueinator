import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:issueinator/domain/models/bug_report_detail.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';

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
  Future<Uint8List>? _screenshotFuture;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final detail = await GetIt.instance<BugReportRepository>()
          .getReportDetail(widget.reportId);

      if (mounted) {
        setState(() {
          _detail = detail;
          _isLoading = false;
          if (detail.screenshotBase64 != null) {
            // Decode async to avoid blocking UI thread
            _screenshotFuture = Future.microtask(
              () => base64Decode(detail.screenshotBase64!),
            );
          }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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

          // Section 2: Core fields
          _buildCoreFields(context, detail, dateFormat),
          const SizedBox(height: 24),

          // Section 3: Device info
          _buildDeviceInfo(context, detail),
          const SizedBox(height: 24),

          // Section 4: Logs
          _buildLogs(context, detail),
          const SizedBox(height: 24),

          // Section 5: Screenshot
          _buildScreenshot(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, BugReportDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase 3: replace with actual triage tag from bug_report_triage table
        Chip(
          avatar: const Icon(Icons.label_outline, size: 16),
          label: const Text('Not yet triaged'),
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          labelStyle: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        if (detail.githubIssueUrl != null)
          ActionChip(
            avatar: const Icon(Icons.open_in_new, size: 16),
            label: const Text('View GitHub Issue'),
            onPressed: () => _launchGitHubUrl(detail.githubIssueUrl!),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Logs', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (hasLogs)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              detail.logs!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFD4D4D4),
              ),
            ),
          )
        else
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

  Widget _buildScreenshot(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Screenshot', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_screenshotFuture != null)
          FutureBuilder<Uint8List>(
            future: _screenshotFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text(
                  'Failed to decode screenshot: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                );
              }
              if (snapshot.hasData) {
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: InteractiveViewer(
                    child: Image.memory(snapshot.data!),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          )
        else
          Text(
            'No screenshot available',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
      ],
    );
  }
}
