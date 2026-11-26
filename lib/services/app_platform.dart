import 'package:flutter/foundation.dart';

/// Uses Flutter's platform override so platform behavior can be tested.
class AppPlatform {
  AppPlatform._();

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isMobile => isIOS || isAndroid;
  static bool get supportsApkUpdates => isAndroid;
  static bool get supportsUpdateChecks => isMobile;
}
