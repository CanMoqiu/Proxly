import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_platform.dart';
import 'update_service.dart';
import 'web_panel_service.dart';

/// Reclaim HTTP caches without clearing cookies or persistent web storage.
class StartupCacheMaintenance {
  static Future<void> run({
    Future<void> Function()? cleanupApk,
    Future<void> Function()? clearHttpCache,
    Future<void> Function()? cleanupPanel,
    DateTime? now,
  }) async {
    if (!AppPlatform.supportsApkUpdates && !AppPlatform.isIOS) return;
    await Future.wait([
      if (AppPlatform.supportsApkUpdates)
        _bestEffort(cleanupApk ?? UpdateService.instance.cleanupInstalledApk),
      _bestEffort(cleanupPanel ?? WebPanelService.cleanupTemporaryFiles),
      _bestEffort(() => _clearDueHttpCache(
          clearHttpCache ?? _clearHttpCache, now ?? DateTime.now())),
    ]);
  }

  static Future<void> _clearDueHttpCache(
      Future<void> Function() clear, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    final version = '${info.version}+${info.buildNumber}';
    final previous = prefs.getInt('http_cache_cleaned_at');
    final elapsed = previous == null
        ? null
        : now.difference(DateTime.fromMillisecondsSinceEpoch(previous));
    if (prefs.getString('http_cache_cleaned_version') == version &&
        elapsed != null &&
        !elapsed.isNegative &&
        elapsed < const Duration(days: 7)) {
      return;
    }
    await clear();
    // Failed cleanup is retried next launch; preferences and cookies are untouched.
    await prefs.setInt('http_cache_cleaned_at', now.millisecondsSinceEpoch);
    await prefs.setString('http_cache_cleaned_version', version);
  }

  static Future<void> _clearHttpCache() {
    if (AppPlatform.isIOS) {
      // Do not include Fetch caches, offline data, databases or user preferences.
      return WebStorageManager.instance().removeDataModifiedSince(
        dataTypes: {
          WebsiteDataType.WKWebsiteDataTypeMemoryCache,
          WebsiteDataType.WKWebsiteDataTypeDiskCache,
        },
        date: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }
    return InAppWebViewController.clearAllCache(includeDiskFiles: true);
  }

  static Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action().timeout(const Duration(seconds: 2));
    } catch (_) {
      // An unavailable plugin or cache must not block use of the application.
    }
  }
}
