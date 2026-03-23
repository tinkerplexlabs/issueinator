import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:issueinator/application/services/bug_report_service.dart';
import 'package:issueinator/core/dev_log.dart';

/// Dialog for capturing and submitting bug reports
///
/// Styled as a vintage CRT terminal display:
/// - Green phosphor text on black background
/// - Curved edges simulating CRT barrel distortion
/// - ASCII box-drawing characters (curses-style)
/// - Subtle phosphor glow and scanline effects
class BugReportDialog extends StatefulWidget {
  /// Optional pre-captured screenshot to avoid capturing the dialog itself
  final Uint8List? preCapture;

  const BugReportDialog({super.key, this.preCapture});

  @override
  State<BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<BugReportDialog> {
  final _descriptionController = TextEditingController();
  Uint8List? _screenshot;
  bool _isCapturing = true;
  bool _isSubmitting = false;
  bool _extendedContext = false;
  String? _errorMessage;
  int _selectedButton = 1; // 0 = Cancel, 1 = Submit

  // CRT phosphor colors
  static const _phosphorGreen = Color(0xFF33FF33);
  static const _phosphorDim = Color(0xFF20AA20);
  static const _phosphorGlow = Color(0xFF33FF33);
  static const _crtBlack = Color(0xFF0A0A0A);

  @override
  void initState() {
    super.initState();
    if (widget.preCapture != null) {
      _screenshot = widget.preCapture;
      _isCapturing = false;
    } else {
      _captureScreenshot();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _captureScreenshot() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final screenshot = await BugReportService.instance.captureScreenshot();

      if (mounted) {
        setState(() {
          _screenshot = screenshot;
          _isCapturing = false;
        });
      }
    } catch (e) {
      devLog('[BugReport] Screenshot capture error: $e');
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _errorMessage = 'SCREENSHOT CAPTURE FAILED';
        });
      }
    }
  }

  Future<void> _submitReport() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await BugReportService.instance.submit(
        description: _descriptionController.text.trim(),
        screenshot: _screenshot,
        extendedContext: _extendedContext,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'BUG REPORT TRANSMITTED',
              style: TextStyle(fontFamily: 'monospace'),
            ),
            backgroundColor: _phosphorDim,
          ),
        );
      }
    } catch (e) {
      devLog('[BugReport] Submit error: $e');
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'TRANSMISSION ERROR: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ClipPath(
        clipper: _CRTScreenClipper(),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
          decoration: BoxDecoration(
            color: _crtBlack,
            border: Border.all(color: _phosphorDim, width: 2),
            boxShadow: [
              BoxShadow(
                color: _phosphorGlow.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Scanline overlay
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScanlinePainter(),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTitleBar(),
                    const SizedBox(height: 4),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildScreenshotArea(),
                            const SizedBox(height: 8),
                            _buildDescriptionArea(),
                            const SizedBox(height: 8),
                            _buildLogInfo(),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 8),
                              _buildError(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildButtonBar(),
                    _buildStatusLine(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return _TerminalText(
      '┌${"─" * 44}┐\n'
      '│  TINKERPLEX LABS BUG REPORTER${" " * 13}│\n'
      '├${"─" * 44}┤',
      glow: true,
    );
  }

  Widget _buildScreenshotArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TerminalText('│ SCREENSHOT CAPTURE:', glow: true),
        const SizedBox(height: 4),
        Container(
          height: 100,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _crtBlack,
            border: Border.all(color: _phosphorDim, width: 1),
          ),
          child: _isCapturing
              ? Center(
                  child: _TerminalText(
                    '[ CAPTURING... ]',
                    glow: true,
                    blink: true,
                  ),
                )
              : _screenshot != null
                  ? Image.memory(
                      _screenshot!,
                      fit: BoxFit.contain,
                    )
                  : const Center(
                      child: _TerminalText(
                        '[ NO IMAGE DATA ]',
                        dim: true,
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildDescriptionArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TerminalText('│ ENTER BUG DESCRIPTION:', glow: true),
        const SizedBox(height: 4),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _crtBlack,
            border: Border.all(color: _phosphorDim, width: 1),
          ),
          child: TextField(
            controller: _descriptionController,
            maxLines: 4,
            enabled: !_isSubmitting,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: _phosphorGreen,
              shadows: [
                Shadow(color: _phosphorGlow, blurRadius: 4),
              ],
            ),
            cursorColor: _phosphorGreen,
            decoration: const InputDecoration(
              hintText: '> _',
              hintStyle: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: _phosphorDim,
              ),
              contentPadding: EdgeInsets.all(4),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogInfo() {
    final summary = BugReportService.instance.getLogBufferSummary();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TerminalText(
          '│ LOG BUFFER: $summary',
          dim: true,
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _isSubmitting
              ? null
              : () => setState(() => _extendedContext = !_extendedContext),
          child: _TerminalText(
            '│ [${_extendedContext ? "X" : " "}] EXTENDED CONTEXT (full logs)',
            dim: !_extendedContext,
            glow: _extendedContext,
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return _TerminalText(
      '│ *** ERROR: $_errorMessage ***',
      glow: true,
      blink: true,
    );
  }

  Widget _buildButtonBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _isSubmitting ? null : () => Navigator.of(context).pop(),
          onTapDown: (_) => setState(() => _selectedButton = 0),
          child: _TerminalText(
            _selectedButton == 0 ? '>[CANCEL]<' : ' [CANCEL] ',
            glow: _selectedButton == 0,
            dim: _selectedButton != 0,
          ),
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: _isSubmitting || _isCapturing ? null : _submitReport,
          onTapDown: (_) => setState(() => _selectedButton = 1),
          child: _TerminalText(
            _selectedButton == 1
                ? (_isSubmitting ? '>[SENDING..]<' : '>[SUBMIT]<')
                : (_isSubmitting ? ' [SENDING..] ' : ' [SUBMIT] '),
            glow: _selectedButton == 1,
            dim: _selectedButton != 1 || _isSubmitting,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusLine() {
    return Column(
      children: [
        const SizedBox(height: 8),
        _TerminalText(
          '└${"─" * 44}┘',
          glow: true,
        ),
        const SizedBox(height: 2),
        _TerminalText(
          _isSubmitting
              ? 'STATUS: TRANSMITTING DATA...'
              : 'STATUS: READY  │  ESC=EXIT  ENTER=SUBMIT',
          dim: true,
        ),
      ],
    );
  }
}

/// Renders text with CRT phosphor glow effect
class _TerminalText extends StatefulWidget {
  final String text;
  final bool glow;
  final bool dim;
  final bool blink;

  const _TerminalText(
    this.text, {
    this.glow = false,
    this.dim = false,
    this.blink = false,
  });

  @override
  State<_TerminalText> createState() => _TerminalTextState();
}

class _TerminalTextState extends State<_TerminalText>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    );
    if (widget.blink) {
      _blinkController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TerminalText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.blink && !_blinkController.isAnimating) {
      _blinkController.repeat(reverse: true);
    } else if (!widget.blink && _blinkController.isAnimating) {
      _blinkController.stop();
      _blinkController.value = 1.0;
    }
  }

  static const _phosphorGreen = Color(0xFF33FF33);
  static const _phosphorDim = Color(0xFF20AA20);
  static const _phosphorGlow = Color(0xFF33FF33);

  @override
  Widget build(BuildContext context) {
    final color = widget.dim ? _phosphorDim : _phosphorGreen;

    Widget textWidget = Text(
      widget.text,
      style: TextStyle(
        fontSize: 11,
        fontFamily: 'monospace',
        color: color,
        height: 1.2,
        shadows: widget.glow
            ? [
                Shadow(color: _phosphorGlow.withValues(alpha: 0.8), blurRadius: 4),
                Shadow(color: _phosphorGlow.withValues(alpha: 0.4), blurRadius: 8),
              ]
            : null,
      ),
    );

    if (widget.blink) {
      return AnimatedBuilder(
        animation: _blinkController,
        builder: (context, child) {
          return Opacity(
            opacity: 0.4 + (_blinkController.value * 0.6),
            child: child,
          );
        },
        child: textWidget,
      );
    }

    return textWidget;
  }
}

/// Clips the dialog to simulate CRT screen curvature (barrel distortion)
class _CRTScreenClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    const curvature = 12.0;

    path.moveTo(curvature, 0);

    // Top edge
    path.quadraticBezierTo(
      size.width / 2, curvature / 2,
      size.width - curvature, 0,
    );

    // Top-right corner
    path.quadraticBezierTo(
      size.width, 0,
      size.width, curvature,
    );

    // Right edge
    path.quadraticBezierTo(
      size.width - curvature / 2, size.height / 2,
      size.width, size.height - curvature,
    );

    // Bottom-right corner
    path.quadraticBezierTo(
      size.width, size.height,
      size.width - curvature, size.height,
    );

    // Bottom edge
    path.quadraticBezierTo(
      size.width / 2, size.height - curvature / 2,
      curvature, size.height,
    );

    // Bottom-left corner
    path.quadraticBezierTo(
      0, size.height,
      0, size.height - curvature,
    );

    // Left edge
    path.quadraticBezierTo(
      curvature / 2, size.height / 2,
      0, curvature,
    );

    // Top-left corner
    path.quadraticBezierTo(
      0, 0,
      curvature, 0,
    );

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Paints subtle CRT scanlines
class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x15000000)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 2) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }

    final vignetteRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.3),
        ],
        stops: const [0.5, 1.0],
      ).createShader(vignetteRect);

    canvas.drawRect(vignetteRect, vignettePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
