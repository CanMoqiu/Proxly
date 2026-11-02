import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxly/services/clash_service.dart';
import 'package:proxly/services/openclash_quick_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/dashboard/dashboard_controls.dart';
import 'package:proxly/widgets/dashboard/clash_overview_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'dashboard shares one read session and reuses unchanged card widgets',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    var sessions = 0;
    var commands = 0;
    late DashboardControlCards cards;
    late StateSetter rebuild;
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return DashboardControls(
                quickSettingsService: OpenClashQuickSettingsService(
                    clashService: ClashService.forTesting(
                  config:
                      const ClashConfig(host: '192.168.1.1:9090', token: ''),
                  client: MockClient(
                      (_) async => http.Response('{"mode":"rule"}', 200)),
                )),
                readSession: (read) async {
                  sessions++;
                  await read((command) async {
                    commands++;
                    return "en_mode=fake-ip\nproxy_mode=rule\nopenclash.config.config_path='/etc/openclash/config/home.yaml'\n";
                  });
                },
                builder: (_, value) {
                  cards = value;
                  return const SizedBox();
                },
              );
            },
          )),
    ));
    await tester.pumpAndSettle();
    expect(sessions, 1);
    expect(commands, 2);
    final previous = cards;
    rebuild(() {});
    await tester.pump();
    expect(cards.currentYaml, same(previous.currentYaml));
    expect(cards.quickSettings, same(previous.quickSettings));
    expect(cards.operations, same(previous.operations));
    await tester.pump(const Duration(seconds: 5));
    expect(sessions, 1);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(sessions, 2);
    await cards.refresh();
    await tester.pump();
    expect(sessions, 3,
        reason: 'Explicit refresh bypasses the stable polling interval');
    expect(commands, 6);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'overview repaints shifted history even when the latest speed is unchanged',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    Future<CustomPainter> render(List<double> speeds) async {
      await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
                body: ClashOverviewCard(
              activeConnections: 0,
              totalDownload: 0,
              totalUpload: 0,
              downloadSpeeds: speeds,
              uploadSpeeds: const [0, 0, 0],
              currentDownSpeed: 0,
              currentUpSpeed: 0,
            ))),
      ));
      return tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<CustomPainter>()
          .firstWhere((painter) =>
              painter.runtimeType.toString() == '_SpeedChartPainter');
    }

    final first = await render([100, 0, 0]);
    final next = await render([0, 100, 0]);
    expect(next.shouldRepaint(first), isTrue);
    final unchanged = await render([0, 100, 0]);
    expect(unchanged.shouldRepaint(next), isFalse);
  });

  testWidgets(
      'reconnection replaces one stale shared read without duplicate sessions',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    const output =
        "en_mode=fake-ip\nproxy_mode=rule\nopenclash.config.config_path='/etc/openclash/config/home.yaml'\n";
    final authenticated = Completer<void>();
    final oldResponse = Completer<String>();
    var sessions = 0;
    var commands = 0;
    var revision = 0;
    late StateSetter rebuild;
    late DashboardControlCards cards;
    final service = OpenClashQuickSettingsService(
        clashService: ClashService.forTesting(
      config: const ClashConfig(host: '192.168.1.1:9090', token: ''),
      client: MockClient((_) async => http.Response('{"mode":"rule"}', 200)),
    ));
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return DashboardControls(
              recoveryRevision: revision,
              quickSettingsService: service,
              readSession: (read) async {
                final session = ++sessions;
                if (session == 1) await authenticated.future;
                await read((_) async {
                  commands++;
                  return session == 1 ? oldResponse.future : output;
                });
              },
              builder: (_, value) {
                cards = value;
                return const SizedBox();
              },
            );
          })),
    ));
    await tester.pump();
    expect(cards.activityLabel, isNotNull,
        reason: 'Authentication is part of initial loading');
    authenticated.complete();
    await tester.pump();
    expect(commands, 2);
    rebuild(() => revision++);
    await tester.pump();
    expect(sessions, 1);
    oldResponse.complete(output);
    await tester.pumpAndSettle();
    expect(sessions, 2);
    expect(commands, 4);
    expect(cards.activityLabel, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
