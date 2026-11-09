import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/settings_page.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/router_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'background identity recognition preserves unsaved settings and has no software selector',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'clash_host': 'router.local:9090',
      'router_tool': 'generic'
    });
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(home: SettingsPage())));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<RouterTool>), findsNothing);
    expect(find.text('Identify proxy software and core'), findsNothing);
    final host = find.byType(TextField).first;
    await tester.enterText(host, 'unsaved-router.local:9095');
    final store = ConnectionSettingsStore.instance;
    await store.applyRouterDetection(
        expectedHost: 'router.local:9090',
        expectedRevision: store.revision,
        tool: RouterTool.nikki,
        core: ProxyCore.mihomo);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(host).controller!.text,
        'unsaved-router.local:9095');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings load custom SSH port and reject an invalid save',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'clash_host': 'router.local:9090',
      'ssh_port': 2222,
    });
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    var writes = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'write') writes++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: const MaterialApp(home: SettingsPage()),
    ));
    await tester.pumpAndSettle();
    final port = find.byKey(const ValueKey('ssh_port_field'));
    expect(tester.widget<TextField>(port).controller!.text, '2222');
    await tester.ensureVisible(port);
    await tester.enterText(port, '0');
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('SSH port must be an integer between 1 and 65535'),
        findsOneWidget);
    expect(writes, 0);
    expect((await SharedPreferences.getInstance()).getInt('ssh_port'), 2222);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('connection settings appear before appearance settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pump();

    final connectionCard =
        find.byKey(const ValueKey('settings_connection_card'));
    final themeCard = find.byKey(const ValueKey('settings_theme_card'));
    expect(connectionCard, findsOneWidget);
    expect(themeCard, findsOneWidget);
    expect(
      tester.getTopLeft(connectionCard).dy,
      lessThan(tester.getTopLeft(themeCard).dy),
    );
  });

  testWidgets(
      'settings scroll padding stays compact on short safe-area screens',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(bottom: 18),
            ),
            child: child!,
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pump();

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scrollView.padding, const EdgeInsets.fromLTRB(16, 24, 16, 42));
    expect((scrollView.padding! as EdgeInsets).bottom, lessThan(80));
  });
}
