import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';

import 'package:issueinator/infrastructure/debug/bug_report_log_buffer.dart';
import 'package:issueinator/core/dev_log.dart';

/// Service for capturing bug reports with screenshots, logs, and descriptions.
///
/// Submits reports directly to the Supabase `bug_reports` table.
class BugReportService {
  BugReportService._();

  static final BugReportService _instance = BugReportService._();

  /// Get the singleton instance
  static BugReportService get instance => _instance;

  /// Global key for the app's RepaintBoundary (set by AppShell)
  GlobalKey? repaintBoundaryKey;

  /// Max screenshot width in pixels.
  static const double _maxScreenshotWidth = 720;

  /// Capture a screenshot from the global RepaintBoundary
  Future<Uint8List?> captureScreenshot() async {
    try {
      if (repaintBoundaryKey == null) {
        devLog('[BugReport] No RepaintBoundary key set');
        return null;
      }

      final boundary = repaintBoundaryKey!.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        devLog('[BugReport] Could not find RenderRepaintBoundary');
        return null;
      }

      final deviceDpr =
          ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
      final logicalWidth = boundary.size.width;
      final maxDpr = _maxScreenshotWidth / logicalWidth;
      final pixelRatio = deviceDpr > maxDpr ? maxDpr : deviceDpr;

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        devLog('[BugReport] Failed to convert image to bytes');
        return null;
      }

      devLog(
          '[BugReport] Screenshot captured: ${byteData.lengthInBytes} bytes '
          '(${image.width}x${image.height}, dpr=${pixelRatio.toStringAsFixed(2)})');
      return byteData.buffer.asUint8List();
    } catch (e) {
      devLog('[BugReport] Screenshot capture failed: $e');
      return null;
    }
  }

  /// Get device information for the report
  Future<String> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return '${info.manufacturer} ${info.model} '
            '(Android ${info.version.release}, SDK ${info.version.sdkInt})';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return '${info.name} ${info.model} '
            '(${info.systemName} ${info.systemVersion})';
      }
      return 'Unknown device';
    } catch (e) {
      return 'Unknown device';
    }
  }

  /// Get the platform string
  String _getPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Get app version information
  Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (e) {
      return 'Unknown version';
    }
  }

  /// Submit bug report to Supabase
  Future<void> submit({
    required String description,
    Uint8List? screenshot,
    bool extendedContext = false,
  }) async {
    devLog(
        '[BugReport] Submitting bug report to Supabase... (extended=$extendedContext)');

    final deviceInfo = await _getDeviceInfo();
    final appVersion = await _getAppVersion();
    final logs =
        BugReportLogBuffer().exportAsMarkdown(extended: extendedContext);

    final screenshotBase64 =
        screenshot != null ? base64Encode(screenshot) : null;

    final userId = SupabaseConfig.client.auth.currentUser?.id;

    await SupabaseConfig.client.from('bug_reports').insert({
      'user_id': userId,
      'source_app': 'issueinator',
      'description': description,
      'app_version': appVersion,
      'device_info': deviceInfo,
      'platform': _getPlatform(),
      'logs': logs,
      'screenshot_base64': screenshotBase64,
    });

    devLog('[BugReport] Bug report submitted successfully');
  }

  /// Get a brief summary of the current log buffer state
  String getLogBufferSummary() {
    final stats = BugReportLogBuffer().getStats();
    return '${stats['entryCount']} entries (${stats['sizeKB']} KB / ${stats['maxSizeMB']} MB)';
  }
}
