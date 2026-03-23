import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:issueinator/application/services/bug_report_service.dart';
import 'package:issueinator/core/screen_corner_utils.dart';
import 'package:issueinator/presentation/widgets/bug_report_button.dart';

/// Global app wrapper that provides bug reporting functionality
///
/// - Wraps the app in a RepaintBoundary for screenshot capture
/// - Overlays a circular bug report button in the top-right corner
///
/// This widget should be used in MaterialApp.builder to wrap ALL routes,
/// ensuring the bug report button is visible on every screen.
class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({
    super.key,
    required this.child,
  });

  /// Global key for the RepaintBoundary (used for screenshot capture)
  static final GlobalKey repaintBoundaryKey = GlobalKey();

  /// Global key for the Navigator (used to show dialogs from outside Navigator context)
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    BugReportService.instance.repaintBoundaryKey = AppShell.repaintBoundaryKey;
  }

  @override
  Widget build(BuildContext context) {
    // Get safe area padding for proper positioning
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;

    // Corner-safe right inset for rounded screen displays (Android only)
    double rightInset = 8;
    if (!kIsWeb && Platform.isAndroid) {
      final r =
          ScreenCornerUtils.estimateCornerRadius(mediaQuery.viewPadding);
      final buttonY = topPadding + 8;
      rightInset =
          math.max(8, ScreenCornerUtils.cornerIntrusion(r, buttonY) + 12);
    }

    // Wrap in RepaintBoundary for screenshot capture
    return RepaintBoundary(
      key: AppShell.repaintBoundaryKey,
      child: Stack(
        children: [
          // Main app content
          widget.child,

          // Bug report button positioned in top-right corner
          Positioned(
            right: rightInset,
            top: topPadding + 8,
            child: const BugReportButton(),
          ),
        ],
      ),
    );
  }
}
