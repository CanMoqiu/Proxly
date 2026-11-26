import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/app_route_observer.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/connections_page.dart';
import 'package:proxly/pages/main_shell.dart';
import 'package:proxly/services/clash_service.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/controller_connection_state.dart';
import 'package:proxly/services/router_detection_session.dart';
import 'package:proxly/services/router_tool.dart';
import 'package:proxly/pages/native_connections_page.dart';
import 'package:proxly/pages/proxy_page.dart';
import 'package:proxly/pages/settings_page.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/adaptive_ui.dart';
import 'package:proxly/widgets/app_popup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    final secrets = <String, String>{};
    messenger.setMockMethodCallHandler(storage, (call) async {
      final arguments = call.arguments as Map;
      final key = arguments['key'] as String?;
      return switch (call.method) {
        'read' => secrets[key],
        'write' => secrets[key!] = arguments['value'] as String,
        'delete' => secrets.remove(key),
        _ => null,
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(storage, null));

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

  testWidgets('cold start and five-minute resume expire manual backend choices',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'automatic_update_check_enabled': false,
    });
    await AppLocaleController.instance.load();
    final store = ConnectionSettingsStore.instance;
    await store.initializeProfiles();
    Future<void> selectBackend() => store.saveController(
          host: 'router.local:9090',
          token: '',
          sshPassword: '',
          routerTool: RouterTool.openClash,
          temporaryBackendSelection: true,
        );

    await selectBackend();
    final id = store.activeDevice!.id;
    expect(store.hasTemporaryBackendSelection(id), isTrue);

    var now = DateTime(2026);
    final session = _CountingSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: MaterialApp(
        navigatorObservers: [shellRouteObserver],
        home: MainShell(
          detectionSession: session,
          backgroundClock: () => now,
        ),
      ),
    ));
    await tester.pump();
    expect(session.calls, 1);
    expect(store.hasTemporaryBackendSelection(id), isFalse);
    tester
        .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
        .onTap!(3);
    await tester.pump();

    await selectBackend();
    await tester.pump();
    expect(store.hasTemporaryBackendSelection(id), isTrue);
    final beforeResume = session.calls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    now = now.add(const Duration(minutes: 4, seconds: 59));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(session.calls, beforeResume + 1);
    expect(store.hasTemporaryBackendSelection(id), isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    now = now.add(const Duration(minutes: 4));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(session.calls, beforeResume + 2);
    expect(store.hasTemporaryBackendSelection(id), isFalse);
    expect((await store.load()).routerTool, RouterTool.openClash);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets(
      'saving clears edited borders and leaving settings discards drafts',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'automatic_update_check_enabled': false,
      'clash_host': 'router.local:9090',
    });
    await AppLocaleController.instance.load();
    final store = ConnectionSettingsStore.instance;
    await store.initializeProfiles();
    final session = _CountingSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: MaterialApp(
        navigatorObservers: [shellRouteObserver],
        theme: AppTheme.light(),
        home: MainShell(detectionSession: session),
      ),
    ));

    void selectTab(int index) => tester
        .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
        .onTap!(index);

    selectTab(3);
    await tester.pumpAndSettle();
    final address = find.byKey(const ValueKey('controller_address_field'));
    final port = find.byKey(const ValueKey('controller_port_field'));
    TextField field(Finder finder) => tester.widget<TextField>(finder);
    Color? editOutline(Finder finder) =>
        field(finder).decoration!.enabledBorder?.borderSide.color;
    final orange = AppPalette.of(tester.element(address)).warning;
    final backend = find.byKey(const ValueKey('controller_backend_picker'));
    AppSelectionPicker backendButton() =>
        tester.widget<AppSelectionPicker>(backend);

    Future<void> chooseBackend(String option) async {
      await tester.ensureVisible(backend);
      await tester.pumpAndSettle();
      await tester.tap(backend);
      await tester.pumpAndSettle();
      final sheet = find.byWidgetPredicate((w) => w is AppOptionsSheet);
      await tester.tap(find.descendant(of: sheet, matching: find.text(option)));
      await tester.pumpAndSettle();
    }

    expect(backendButton().borderColor, isNull);
    await chooseBackend('Nikki');
    expect(backendButton().borderColor, orange);
    expect(editOutline(address), isNull);
    await tester.enterText(address, 'saved-router.local');
    await tester.pumpAndSettle();
    expect(editOutline(address), orange);
    expect(editOutline(port), isNull);
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await store.load()).host, 'saved-router.local:9090');
    expect(editOutline(address), isNull);
    expect(backendButton().label, 'Nikki');
    expect(backendButton().borderColor, isNull);
    expect(
        find.text(
            'Proxy backend switched temporarily. Detection resumes on the next cold start or after 5 minutes in the background.'),
        findsOneWidget);
    expect(find.text('Settings saved'), findsNothing);
    expect(store.hasTemporaryBackendSelection(store.activeDevice!.id), isTrue);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Settings saved'), findsOneWidget);

    await chooseBackend('OpenClash');
    expect(backendButton().borderColor, orange);
    await tester.ensureVisible(address);
    await tester.enterText(address, 'discarded-router.local');
    await tester.enterText(port, '9098');
    await tester.pumpAndSettle();
    expect(editOutline(address), orange);
    expect(editOutline(port), orange);
    selectTab(0);
    await tester.pump();
    selectTab(3);
    await tester.pumpAndSettle();
    expect(field(address).controller!.text, 'saved-router.local');
    expect(field(port).controller!.text, '9090');
    expect(backendButton().label, 'Nikki');
    expect(backendButton().borderColor, isNull);
    expect(editOutline(address), isNull);
    expect(editOutline(port), isNull);
    expect((await store.load()).host, 'saved-router.local:9090');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('proxy warmup starts the web connections warmup immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'automatic_update_check_enabled': false,
      'connections_tab_mode': 'webview',
    });
    await ConnectionSettingsStore.instance.initializeProfiles();
    await ClashService.instance.loadConfig();
    final connection = ControllerConnectionState.instance;
    final session = _CountingSession();
    addTearDown(session.dispose);
    addTearDown(connection.reset);
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: MaterialApp(
        navigatorObservers: [shellRouteObserver],
        home: MainShell(detectionSession: session),
      ),
    ));
    await tester.pump();

    final proxy = find.byType(ProxyPage, skipOffstage: false);
    final connections = find.byType(ConnectionsPage, skipOffstage: false);
    connection.reportStatus(connection.observe(), 200);
    await tester.pump(const Duration(milliseconds: 799));
    expect(proxy, findsNothing);
    expect(connections, findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(proxy, findsOneWidget);
    expect(connections, findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(connections, findsOneWidget);
    final bar =
        tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
    expect(bar.currentIndex, 0);

    await tester.pumpWidget(const SizedBox.shrink());
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
