import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/app_navigator.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/services/ssh_host_trust_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{};

  setUp(() async {
    values.clear();
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final key = arguments['key'] as String?;
      switch (call.method) {
        case 'read':
          return values[key];
        case 'write':
          values[key!] = arguments['value'] as String;
          return null;
        case 'delete':
          values.remove(key);
          return null;
        case 'deleteAll':
          values.clear();
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('first connection is confirmed and fingerprint changes warn',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    final first = SshHostTrustService.instance.verify(
      'Router.Local',
      22,
      'ssh-ed25519',
      Uint8List.fromList(utf8.encode('SHA256:firstFingerprint')),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认 SSH 设备身份'), findsOneWidget);
    expect(values, isEmpty);
    await tester.tap(find.text('信任并继续'));
    await tester.pumpAndSettle();
    expect(await first, isTrue);
    expect(await SshHostTrustService.instance.trustedHostCount(), 1);

    expect(
      await SshHostTrustService.instance.verify(
        'router.local',
        22,
        'ssh-ed25519',
        Uint8List.fromList(utf8.encode('SHA256:firstFingerprint')),
      ),
      isTrue,
    );
    expect(find.byType(AlertDialog), findsNothing);

    final changed = SshHostTrustService.instance.verify(
      'router.local',
      22,
      'ssh-ed25519',
      Uint8List.fromList(utf8.encode('SHA256:secondFingerprint')),
    );
    await tester.pumpAndSettle();
    expect(find.text('SSH 身份指纹已变化'), findsOneWidget);
    expect(find.text('旧指纹'), findsOneWidget);
    expect(find.text('新指纹'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await changed, isFalse);

    final stored = jsonDecode(values['ssh_host_fingerprints']!) as Map;
    expect(stored['router.local:22']['fingerprint'], 'SHA256:firstFingerprint');
  });
}
