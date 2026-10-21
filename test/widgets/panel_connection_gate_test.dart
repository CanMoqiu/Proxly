import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/services/controller_connection_state.dart';
import 'package:proxly/services/connection_feedback.dart';
import 'package:proxly/services/openclash_restart_coordinator.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/dashboard/dashboard_status.dart';
import 'package:proxly/widgets/panel_connection_gate.dart';

void main() {
  testWidgets(
      'home and panel reflect the same offline and recovery observations',
      (tester) async {
    final state = ControllerConnectionState.instance;
    state.reset();
    addTearDown(state.reset);
    var retries = 0;
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
                body: Column(children: [
              DashboardStatus(
                  active: false, builder: (_, cards) => cards.status),
              Expanded(
                  child: PanelConnectionGate(
                      connectionState: state,
                      isActive: () => true,
                      onRetry: () async {
                        retries++;
                      },
                      onUnavailable: () {},
                      child: const Text('panel-ready'))),
            ])))));
    state.reportOffline(state.observe());
    await tester.pump();
    expect(
        find.text(tr(ConnectionFeedback.routerUnavailable)), findsNWidgets(2));
    expect(find.text('panel-ready'), findsNothing);
    state.reportStatus(state.observe(), 200);
    await tester.pump();
    await tester.pump();
    expect(find.text(tr('运行中')), findsOneWidget);
    expect(find.text('panel-ready'), findsOneWidget);
    expect(retries, 1);
    state.reportStatus(state.observe(), 200);
    await tester.pump();
    expect(retries, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hidden panels defer recovery until visible and rebuild once',
      (tester) async {
    final state = ControllerConnectionState();
    addTearDown(state.dispose);
    var active = false;
    var retries = 0;
    Future<void> pump() => tester.pumpWidget(MaterialApp(
        home: PanelConnectionGate(
            connectionState: state,
            isActive: () => active,
            onRetry: () async {
              retries++;
            },
            onUnavailable: () {},
            child: const Text('ready'))));
    await pump();
    state.reportOffline(state.observe());
    await tester.pump();
    state.reportStatus(state.observe(), 200);
    await tester.pump();
    expect(retries, 0);
    active = true;
    await pump();
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('restart overlays the panel until verified success',
      (tester) async {
    final command = Completer<void>();
    final restart = OpenClashRestartCoordinator(
        restartCommand: (_) => command.future,
        healthProbe: () async {},
        delay: (_) async {},
        terminalStateDuration: Duration.zero);
    final state = ControllerConnectionState(restartCoordinator: restart);
    addTearDown(state.dispose);
    addTearDown(restart.dispose);
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
        home: PanelConnectionGate(
            connectionState: state,
            isActive: () => true,
            onRetry: () async {
              retries++;
            },
            onUnavailable: () {},
            child: const Text('ready'))));
    final operation = restart.restart();
    await tester.pump();
    expect(find.text(tr('正在重启 OpenClash...')), findsOneWidget);
    expect(find.text('ready'), findsNothing);
    expect(retries, 0);
    command.complete();
    await tester.pump();
    await operation;
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
    expect(retries, 1);
  });
}
