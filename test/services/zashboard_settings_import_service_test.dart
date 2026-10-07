import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/zashboard_config_validator.dart';
import 'package:proxly/services/zashboard_settings_import_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureValues = <String, String>{};

  setUp(() {
    secureValues
      ..clear()
      ..['clash_token'] = 'controller-secret';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final key = arguments['key'] as String?;
      switch (call.method) {
        case 'read':
          return secureValues[key];
        case 'write':
          secureValues[key!] = arguments['value'] as String;
          return null;
        case 'delete':
          secureValues.remove(key);
          return null;
        case 'deleteAll':
          secureValues.clear();
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('file and core imports share managed and sensitive data filtering',
      () async {
    SharedPreferences.setMockInitialValues({
      ZashboardSettingsImportService.preferenceKey: jsonEncode({
        'config/existing': 'old',
        'config/language': 'en',
      }),
    });

    final result = await ZashboardSettingsImportService.instance
        .importSnapshot(jsonEncode({
      'config/existing': 'new',
      'config/custom-theme-name': 'midnight',
      'setup/api-list': '[{"password":"leak"}]',
      'config/language': 'zh-CN',
      'config/connection-display-style': 'table',
      'config/disable-pull-to-refresh': 'true',
      'cache/auto-sync-settings-hash': 'hash',
      'config/private': 'controller-secret',
      'config/object': {'authorization': 'Bearer leaked'},
    }));

    expect(result, isNotNull);
    expect(result!.acceptedCount, 2);
    expect(result.skippedCount, 7);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(
      prefs.getString(ZashboardSettingsImportService.preferenceKey)!,
    ) as Map<String, dynamic>;
    expect(saved, {
      'config/existing': 'new',
      'config/custom-theme-name': 'midnight',
    });
  });

  test('an import with no safe entries leaves the previous snapshot intact',
      () async {
    const previous = '{"config/keep":"yes"}';
    SharedPreferences.setMockInitialValues({
      ZashboardSettingsImportService.preferenceKey: previous,
    });

    final result = await ZashboardSettingsImportService.instance
        .importSnapshot('{"config/language":"en"}');

    expect(result!.acceptedCount, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ZashboardSettingsImportService.preferenceKey),
      previous,
    );
  });

  test('rejects oversized and structurally invalid core snapshots', () async {
    SharedPreferences.setMockInitialValues({});
    final oversized = List.filled(
      ZashboardConfigValidator.maxBytes + 1,
      'x',
    ).join();

    await expectLater(
      ZashboardSettingsImportService.instance.importSnapshot(oversized),
      throwsFormatException,
    );
    expect(
      await ZashboardSettingsImportService.instance.importSnapshot('[]'),
      isNull,
    );
  });
}
