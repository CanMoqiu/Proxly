import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/app_navigator.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/services/dashboard_layout_store.dart';
import 'package:proxly/services/ssh_host_trust_service.dart';
import 'package:proxly/widgets/dashboard/dashboard_card_list.dart';
import 'package:proxly/widgets/dashboard/dashboard_controls.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('rejected SSH hides dependent cards and stops home polling',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'zh_CN',
      'clash_host': 'router.local:9090',
    });
    await AppLocaleController.instance.load();
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final storage = <String, String>{'ssh_password': 'test-only'};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final key = args['key'] as String?;
      if (call.method == 'read') return storage[key];
      if (call.method == 'write') storage[key!] = args['value'] as String;
      if (call.method == 'delete') storage.remove(key);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final trust = SshHostTrustService.instance;
    await trust.clearAll();
    final layout = DashboardLayoutStore();
    await layout.load();
    var sessions = 0;
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.light(),
          home: DashboardControls(
            readSession: (_) async {
              sessions++;
              final accepted = await trust.verify(
                  'router.local',
                  22,
                  'ssh-ed25519',
                  Uint8List.fromList(utf8.encode('SHA256:test')));
              if (!accepted) throw StateError('SSH refused');
            },
            builder: (_, cards) => Scaffold(
                body: DashboardCardList(
              layout: layout,
              editing: false,
              onEditPressed: () {},
              onSave: (_) {},
              sshTrustNotice: cards.trustNotice,
              cards: {
                for (final id in DashboardCardId.values)
                  id: Text('card-${id.name}')
              },
            )),
          )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('card-currentYaml'), findsNothing);
    expect(find.text('card-operations'), findsNothing);
    expect(find.text('card-quickSettings'), findsNothing);
    expect(find.text('card-overview'), findsOneWidget);
    await tester.ensureVisible(
        find.byKey(const ValueKey('dashboard_ssh_trust_notice')));
    expect(find.text('查看并确认 SSH 身份'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(sessions, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(layout.isVisible(DashboardCardId.currentYaml), isTrue);
    await tester.pumpWidget(const SizedBox());
    await trust.clearAll();
    layout.dispose();
  });
}
