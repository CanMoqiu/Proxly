import 'dart:ui' show FlutterView, Size;

import 'package:flutter/services.dart';

class TabletLayout {
  TabletLayout._();

  static bool? _lastTablet;

  static bool isTabletDisplay(Size physicalSize, double pixelRatio) =>
      pixelRatio > 0 && physicalSize.shortestSide / pixelRatio >= 600;

  // Use the display, not a keyboard-resized or split-screen window.
  static bool isTablet(FlutterView view) => isTabletDisplay(
        view.display.size,
        view.display.devicePixelRatio,
      );

  static List<DeviceOrientation> orientations(bool tablet) => tablet
      ? const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]
      : const [DeviceOrientation.portraitUp];

  static Future<void> updateOrientations(FlutterView view) async {
    final tablet = isTablet(view);
    if (_lastTablet == tablet) return;
    await SystemChrome.setPreferredOrientations(orientations(tablet));
    _lastTablet = tablet;
  }
}
