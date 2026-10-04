import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/app_platform.dart';
import 'package:proxly/services/app_restart_service.dart';
import 'package:proxly/services/app_secure_storage.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({'clash_host': '192.168.1.1:9090'});
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('iOS checks releases but cannot download APKs or restart the process',
      () async {
    expect(AppPlatform.supportsApkUpdates, isFalse);
    expect(AppPlatform.supportsUpdateChecks, isTrue);
    final cancel = ValueNotifier(false);
    addTearDown(cancel.dispose);
    await expectLater(
      UpdateService.instance.downloadApk('invalid', 'v1', null, (_) {}, cancel),
      throwsUnsupportedError,
    );
    await expectLater(UpdateService.instance.installApk(File('absent.apk')),
        throwsUnsupportedError);
    await expectLater(AppRestartService.restartApp(), throwsUnsupportedError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('last_update_check'), isFalse);
  });

  test('locked Keychain preserves credentials and succeeds on retry', () async {
    var locked = true;
    // The plugin selects options using dart:io, not Flutter's test override.
    final options = AppSecureStorage.instance.iOptions.params;
    expect(options['accessibility'], 'unlocked_this_device');
    expect(options['synchronizable'], 'false');
    final calls = <String>[];
    final stored = {'clash_token': 'secret', 'ssh_password': 'password'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      final args = call.arguments as Map;
      if (locked) throw PlatformException(code: '-25308');
      return stored[args['key']];
    });
    await expectLater(ConnectionSettingsStore.instance.load(),
        throwsA(isA<SecureStorageUnavailableException>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('clash_host'), '192.168.1.1:9090');
    expect(calls, isNot(contains('deleteAll')));
    locked = false;
    final settings = await ConnectionSettingsStore.instance.load();
    expect(settings.token, 'secret');
    expect(settings.sshPassword, 'password');
  });

  test('Android retains APK support', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(AppPlatform.supportsApkUpdates, isTrue);
  });
}
