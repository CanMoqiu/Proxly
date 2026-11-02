import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:proxly/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File apk;
  late UpdateService service;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    directory = await Directory.systemTemp.createTemp('proxly-apk-cleanup-');
    apk =
        await File('${directory.path}/proxly_update.apk').writeAsString('apk');
    service =
        UpdateService.forTesting(temporaryDirectory: () async => directory);
    PackageInfo.setMockInitialValues(
      appName: 'Proxly',
      packageName: 'top.canmoqiu.proxly',
      version: '26.9.0',
      buildNumber: '38',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'cached_apk_tag': 'v26.9.0',
      'clash_host': '192.168.1.1',
      'webpanel_settings': '{"theme":"dark"}',
    });
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    service.availableUpdate.dispose();
    await directory.delete(recursive: true);
  });

  for (final tag in ['v26.8.0', 'v26.9.0', null]) {
    test('removes obsolete installer $tag without touching user data',
        () async {
      final prefs = await SharedPreferences.getInstance();
      if (tag == null) {
        await prefs.remove('cached_apk_tag');
      } else {
        await prefs.setString('cached_apk_tag', tag);
      }
      final yaml = await File('${directory.path}/config.yaml')
          .writeAsString('rules: []');
      await service.cleanupInstalledApk();
      expect(await apk.exists(), isFalse);
      expect(prefs.containsKey('cached_apk_tag'), isFalse);
      expect(await yaml.readAsString(), 'rules: []');
      expect(prefs.getString('clash_host'), '192.168.1.1');
      expect(prefs.getString('webpanel_settings'), '{"theme":"dark"}');
    });
  }

  for (final tag in ['v26.9.1', 'v26.10.0', 'unknown']) {
    test('preserves retryable or unrecognized installer $tag', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_apk_tag', tag);
      await service.cleanupInstalledApk();
      expect(await apk.readAsString(), 'apk');
      expect(prefs.getString('cached_apk_tag'), tag);
    });
  }

  test('cleanup does not run again after a new download', () async {
    await service.cleanupInstalledApk();
    await apk.writeAsString('new installer');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_apk_tag', 'v26.10.0');
    await service.cleanupInstalledApk();
    expect(await apk.readAsString(), 'new installer');
    expect(prefs.getString('cached_apk_tag'), 'v26.10.0');
  });

  test('does not recursively remove a directory at the installer path',
      () async {
    await apk.delete();
    await Directory(apk.path).create();
    final child = await File('${apk.path}/keep.yaml').writeAsString('keep');
    await service.cleanupInstalledApk();
    expect(await child.readAsString(), 'keep');
    expect((await SharedPreferences.getInstance()).getString('cached_apk_tag'),
        'v26.9.0');
  });

  test('unavailable cache directory preserves the marker and does not throw',
      () async {
    final failing = UpdateService.forTesting(
        temporaryDirectory: () async =>
            throw const FileSystemException('unavailable'));
    addTearDown(failing.availableUpdate.dispose);
    await failing.cleanupInstalledApk();
    expect(await apk.exists(), isTrue);
    expect((await SharedPreferences.getInstance()).getString('cached_apk_tag'),
        'v26.9.0');
  });

  test('iOS does not inspect or delete installer files', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await service.cleanupInstalledApk();
    expect(await apk.readAsString(), 'apk');
    expect((await SharedPreferences.getInstance()).getString('cached_apk_tag'),
        'v26.9.0');
  });
}
