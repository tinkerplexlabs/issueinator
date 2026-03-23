import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:issueinator/application/services/bug_report_service.dart';
import 'package:issueinator/presentation/widgets/app_shell.dart';
import 'package:issueinator/presentation/widgets/bug_report_dialog.dart';

/// Small circular dark red button positioned in top-right corner
///
/// Tapping opens the bug report dialog for QA personnel to capture
/// screenshots and describe issues.
class BugReportButton extends StatefulWidget {
  const BugReportButton({super.key});

  /// Dark red color for the button background
  static const Color buttonColor = Color(0xFF8B0000);

  /// Button diameter
  static const double buttonSize = 32.0;

  @override
  State<BugReportButton> createState() => _BugReportButtonState();
}

class _BugReportButtonState extends State<BugReportButton> {
  bool _isCapturing = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isCapturing ? null : () => _captureAndShowDialog(context),
      child: Container(
        width: BugReportButton.buttonSize,
        height: BugReportButton.buttonSize,
        decoration: BoxDecoration(
          color: _isCapturing
              ? BugReportButton.buttonColor.withValues(alpha: 0.5)
              : BugReportButton.buttonColor,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: _isCapturing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : SvgPicture.asset(
                  'assets/images/bug-icon.svg',
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
        ),
      ),
    );
  }

  /// Capture screenshot BEFORE showing dialog, then pass it to the dialog
  Future<void> _captureAndShowDialog(BuildContext context) async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    Uint8List? screenshot;
    try {
      screenshot = await BugReportService.instance.captureScreenshot();
    } catch (e) {
      debugPrint('[BugReport] Screenshot capture failed: $e');
    }

    if (!mounted) return;
    setState(() => _isCapturing = false);

    final navigatorContext = AppShell.navigatorKey.currentContext;
    if (navigatorContext != null) {
      showDialog(
        context: navigatorContext,
        barrierDismissible: false,
        builder: (context) => BugReportDialog(preCapture: screenshot),
      );
    }
  }
}
