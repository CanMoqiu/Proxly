import 'package:flutter/foundation.dart';

/// Uses Flutter's platform override so platform behavior can be tested.
class AppPlatform {
  AppPlatform._();

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get supportsApkUpdates =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get supportsUpdateChecks => isIOS || supportsApkUpdates;
}
