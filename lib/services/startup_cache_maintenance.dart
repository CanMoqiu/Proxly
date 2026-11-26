import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_platform.dart';
import 'update_service.dart';
import 'web_panel_service.dart';

/// Reclaim HTTP caches without clearing cookies or persistent web storage.
class StartupCacheMaintenance {
  StartupCacheMaintenance({
    Future<void> Function()? cleanupApk,
    Future<void> Function()? clearHttpCache,
    Future<void> Function()? cleanupPanel,
    DateTime? now,
  })  : _cleanupApk = cleanupApk ?? UpdateService.instance.cleanupInstalledApk,
        _clearCache = clearHttpCache ?? _clearHttpCache,
        _cleanupPanel = cleanupPanel ?? WebPanelService.cleanupTemporaryFiles,
        _now = now;

  static final instance = StartupCacheMaintenance();

  final Future<void> Function() _cleanupApk;
  final Future<void> Function() _clearCache;
  final Future<void> Function() _cleanupPanel;
  final DateTime? _now;
  Future<void>? _webCacheCheck;
  bool _webCacheChecked = false;

  Future<void> cleanFiles() async {
    if (!AppPlatform.supportsUpdateChecks) return;
    await Future.wait([
      if (AppPlatform.supportsApkUpdates) _bestEffort(_cleanupApk),
      _bestEffort(_cleanupPanel),
    ]);
  }

  Future<void> prepareWebView() {
    if (_webCacheChecked || !AppPlatform.supportsUpdateChecks) {
      return Future.value();
    }
    return _webCacheCheck ??= _bestEffort(
      () => _clearDueHttpCache(_clearCache, _now ?? DateTime.now()),
    ).whenComplete(() {
      _webCacheChecked = true;
      _webCacheCheck = null;
    });
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
