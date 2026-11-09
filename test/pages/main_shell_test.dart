import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/app_route_observer.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/connections_page.dart';
import 'package:proxly/pages/main_shell.dart';
import 'package:proxly/services/router_detection_session.dart';
import 'package:proxly/pages/native_connections_page.dart';
import 'package:proxly/pages/proxy_page.dart';
import 'package:proxly/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'software recognition runs once at cold start and once per background return',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'app_language': 'en', 'automatic_update_check_enabled': false});
    await AppLocaleController.instance.load();
    final session = _CountingSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            navigatorObservers: [shellRouteObserver],
            home: MainShell(detectionSession: session))));
    await tester.pump();
    expect(session.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(session.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(session.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(session.calls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(session.calls, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('tabs mount on first visit and retain state while hidden',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'zh_CN',
      'automatic_update_check_enabled': false,
      'connections_tab_mode': 'native',
    });
    await AppLocaleController.instance.load();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [shellRouteObserver],
        home: const MainShell(),
      ),
    ));
    await tester.pump();
    expect(find.byType(ProxyPage, skipOffstage: false), findsNothing);
    expect(find.byType(ConnectionsPage, skipOffstage: false), findsNothing);
    expect(
        find.byType(NativeConnectionsPage, skipOffstage: false), findsNothing);
    expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);

    void select(int index) => tester
        .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
        .onTap!(index);
    select(2);
    await tester.pump();
    final page = find.byType(NativeConnectionsPage, skipOffstage: false);
    final state = tester.state(page);
    expect(tester.widget<NativeConnectionsPage>(page).active, isTrue);
    select(0);
    await tester.pump();
    expect(tester.state(page), same(state));
    expect(tester.widget<NativeConnectionsPage>(page).active, isFalse);
    expect(TickerMode.valuesOf(tester.element(page)).enabled, isFalse);
    select(2);
    await tester.pump();
    expect(tester.state(page), same(state));
    expect(tester.widget<NativeConnectionsPage>(page).active, isTrue);

    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover'))));
    await tester.pumpAndSettle();
    expect(tester.widget<NativeConnectionsPage>(page).active, isFalse);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.widget<NativeConnectionsPage>(page).active, isTrue);
    expect(find.byType(ProxyPage, skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}

class _CountingSession extends RouterDetectionSession {
  int calls = 0;
  @override
  Future<void> refresh() async {
    calls++;
  }
}
