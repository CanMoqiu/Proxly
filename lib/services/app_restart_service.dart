import 'package:flutter/services.dart';
import 'app_platform.dart';

class AppRestartService {
  static const _channel = MethodChannel('proxly/app');

  static Future<void> restartApp() async {
    if (!AppPlatform.supportsApkUpdates) {
      throw UnsupportedError('Process restart is only available on Android');
    }
    try {
      await _channel.invokeMethod<void>('restartApp');
    } catch (_) {
      await SystemNavigator.pop(animated: true);
    }
  }
}
