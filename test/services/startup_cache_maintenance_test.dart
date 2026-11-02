import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:proxly/services/startup_cache_maintenance.dart';

class _Storage extends PlatformWebStorageManager {
  _Storage()
      : super.implementation(const PlatformWebStorageManagerCreationParams());
  Set<WebsiteDataType>? removed;
  DateTime? since;

  @override
  Future<void> removeDataModifiedSince(
      {required Set<WebsiteDataType> dataTypes, required DateTime date}) async {
    removed = dataTypes;
    since = date;
  }
}

class _WebPlatform extends InAppWebViewPlatform {
  final storage = _Storage();
  @override
  PlatformWebStorageManager createPlatformWebStorageManager(
          PlatformWebStorageManagerCreationParams params) =>
      storage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'Proxly',
        packageName: 'top.canmoqiu.proxly',
        version: '26.8.2',
        buildNumber: '37',
        buildSignature: '');
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('cache cleanup runs on upgrade or after a week, not every launch',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var calls = 0;
    Future<void> run(DateTime date) => StartupCacheMaintenance.run(
        now: date,
        cleanupPanel: () async {},
        clearHttpCache: () async {
          calls++;
        });
    await run(DateTime(2026, 11, 1));
    await run(DateTime(2026, 11, 2));
    expect(calls, 1);
    await run(DateTime(2026, 11, 8));
    expect(calls, 2);
    PackageInfo.setMockInitialValues(
        appName: 'Proxly',
        packageName: 'top.canmoqiu.proxly',
        version: '26.8.3',
        buildNumber: '37',
        buildSignature: '');
    await run(DateTime(2026, 11, 8));
    expect(calls, 3);
  });

  test('failed HTTP cleanup is retried without clearing user preferences',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webpanel_localstorage', '{"theme":"dark"}');
    await StartupCacheMaintenance.run(
        cleanupPanel: () async {},
        clearHttpCache: () async => throw StateError('unavailable'));
    expect(prefs.getInt('http_cache_cleaned_at'), isNull);
    var retried = false;
    await StartupCacheMaintenance.run(
        cleanupPanel: () async {},
        clearHttpCache: () async {
          retried = true;
        });
    expect(retried, isTrue);
    expect(prefs.getString('webpanel_localstorage'), '{"theme":"dark"}');
  });

  test('iOS removes only HTTP caches and never invokes APK cleanup', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final previous = InAppWebViewPlatform.instance;
    final platform = _WebPlatform();
    InAppWebViewPlatform.instance = platform;
    if (previous != null) {
      addTearDown(() => InAppWebViewPlatform.instance = previous);
    }
    var apkCalls = 0;
    await StartupCacheMaintenance.run(cleanupApk: () async {
      apkCalls++;
    });
    expect(apkCalls, 0);
    expect(platform.storage.removed, {
      WebsiteDataType.WKWebsiteDataTypeMemoryCache,
      WebsiteDataType.WKWebsiteDataTypeDiskCache,
    });
    expect(platform.storage.since?.millisecondsSinceEpoch, 0);
  });

  test('one Android cleanup failure does not skip the other cleanup', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var cacheCalls = 0;
    await StartupCacheMaintenance.run(
      cleanupApk: () async => throw StateError('unavailable'),
      clearHttpCache: () async {
        cacheCalls++;
      },
    );
    expect(cacheCalls, 1);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform slow cache plugin cannot indefinitely block startup',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final pending = Completer<void>();
      var finished = false;
      final run = StartupCacheMaintenance.run(
          cleanupApk: () async {},
          clearHttpCache: () => pending.future).then((_) => finished = true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(finished, isTrue);
      pending.complete();
      await run;
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
