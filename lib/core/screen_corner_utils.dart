import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Utilities for handling physically rounded display corners on modern phones.
class ScreenCornerUtils {
  ScreenCornerUtils._();

  /// Estimate the display corner radius from [viewPadding].
  static double estimateCornerRadius(EdgeInsets viewPadding) {
    final barHeight = math.max(viewPadding.top, viewPadding.bottom);
    return math.max(36.0, barHeight * 1.0);
  }

  /// How far the corner arc intrudes horizontally at [dy] pixels from the
  /// screen edge, for a circle of radius [r].
  static double cornerIntrusion(double r, double dy) {
    if (dy >= r) return 0;
    final d = r - dy;
    return r - math.sqrt(r * r - d * d);
  }
}
