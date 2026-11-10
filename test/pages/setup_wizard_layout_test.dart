import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/router_detection_service.dart';
import 'package:proxly/services/router_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/setup_wizard_page.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/adaptive_ui.dart';
import 'package:proxly/widgets/keyboard_focus_reveal.dart';
import 'package:proxly/widgets/app_popup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'next detects software before preferences and preserves a manual choice',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    var calls = 0;
    final service = _Detection(() async {
      calls++;
      return const RouterDetectionResult(
          tool: RouterTool.nikki, core: ProxyCore.mihomo, version: 'v1');
    });
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: SetupWizardPage(detectionService: service))));
    final language = find.byType(AppLanguagePicker);
    expect(
        find.descendant(
            of: language, matching: find.byIcon(Icons.play_arrow_rounded)),
        findsOneWidget);
    expect(tester.getRect(language).right,
        closeTo(tester.getRect(find.byType(SetupWizardPage)).right - 32, 0.01));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<RouterTool>), findsNothing);
    expect(find.text('Identify proxy software and core'), findsNothing);
    final selector = find.byKey(const ValueKey('setup_router_tool'));
    expect(selector, findsNothing);
    await tester.enterText(find.byType(TextField).first, 'router.local:9090');
    await tester.ensureVisible(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, 'test-only-password');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    expect(selector, findsOneWidget);
    final pickerRect = tester.getRect(selector);
    final pickerRow =
        find.ancestor(of: selector, matching: find.byType(AppSettingPickerRow));
    expect(pickerRect.right, closeTo(tester.getRect(pickerRow).right, 0.01));
    expect(tester.getRect(find.text('Proxy software')).right,
        lessThan(pickerRect.left));
    expect(
        tester
            .getRect(find.text(
                'Selected from your connection; you can change it manually'))
            .right,
        lessThan(pickerRect.left));
    expect(
        find.descendant(
            of: selector, matching: find.byIcon(Icons.play_arrow_rounded)),
        findsOneWidget);
    expect(tester.getTopLeft(find.text('Appearance')).dy,
        lessThan(tester.getTopLeft(find.text('Proxy software')).dy));
    expect(tester.getTopLeft(find.text('Proxy software')).dy,
        lessThan(tester.getTopLeft(find.text('Connections page display')).dy));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<AppOptionsSheet<RouterTool>>(
                find.byType(AppOptionsSheet<RouterTool>))
            .selectedValue,
        RouterTool.nikki);
    expect(service.lastHost, 'router.local:9090');
    expect(service.lastPassword, 'test-only-password');
    expect(service.lastPort, 22);
    await tester.tap(find.text('OpenClash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('OpenClash'), findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    final options = tester.widget<AppOptionsSheet<RouterTool>>(
        find.byType(AppOptionsSheet<RouterTool>));
    expect(options.options.map((option) => option.value), RouterTool.values);
    expect(find.text('Automatic detection'), findsNothing);
    await tester.tap(find.text('Mihomo generic configuration'));
    await tester.pumpAndSettle();
    expect(find.text('Mihomo generic configuration'), findsOneWidget);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'old detection cannot advance changed inputs or duplicate requests',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final response = Completer<RouterDetectionResult>();
    var calls = 0;
    final detector = _Detection(() async {
      calls++;
      if (calls == 1) return response.future;
      throw StateError('offline');
    });
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: SetupWizardPage(detectionService: detector))));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    final address = find.byType(TextField).first;
    await tester.enterText(address, 'old-router.local:9090');
    final nextPosition = tester.getCenter(find.text('Continue'));
    await tester.tapAt(nextPosition);
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Preferences'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tapAt(nextPosition);
    await tester.pump();
    expect(calls, 1);
    await tester.enterText(address, 'new-router.local:9090');
    response.complete(const RouterDetectionResult(
        tool: RouterTool.nikki, core: ProxyCore.mihomo, version: 'old'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Mihomo generic configuration'), findsOneWidget);
    expect(find.byType(AppOptionsSheet<RouterTool>), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final choice in [RouterTool.nikki, RouterTool.generic, null]) {
    testWidgets('finishing setup persists software choice $choice',
        (tester) async {
      SharedPreferences.setMockInitialValues(
          {'app_language': 'en', 'automatic_update_check_enabled': false});
      const channel =
          MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
      final secrets = <String, String>{};
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        if (call.method == 'write') secrets[args['key']] = args['value'];
        if (call.method == 'read') return secrets[args['key']];
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await AppLocaleController.instance.load();
      final detector = _Detection(() async {
        if (choice == null) throw StateError('offline');
        return RouterDetectionResult(
            tool: choice, core: ProxyCore.mihomo, version: 'test');
      });
      await tester.pumpWidget(AppLocaleScope(
          controller: AppLocaleController.instance,
          child: MaterialApp(
              theme: AppTheme.light(),
              home: SetupWizardPage(detectionService: detector))));
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'router.local:9090');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      if (choice != null) {
        final selector = find.byKey(const ValueKey('setup_router_tool'));
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(
            of: find.byType(AppOptionsSheet<RouterTool>),
            matching: find.text(tr(choice.label))));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Finish setup'));
      final prefs = await SharedPreferences.getInstance();
      for (var i = 0; i < 30 && prefs.getString('clash_host') == null; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      final saved = await ConnectionSettingsStore.instance.load();
      expect(saved.host, 'router.local:9090');
      expect(saved.routerTool, choice ?? RouterTool.generic);
      expect(saved.core, choice == null ? ProxyCore.unknown : ProxyCore.mihomo);
      expect(prefs.getBool('router_tool_confirmed'), isTrue);
      expect(prefs.getBool('router_tool_selection_pending'), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keyboard reveals setup inputs without lifting navigation',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (_, child) => KeyboardFocusReveal(child: child!),
        home: const SetupWizardPage(),
      ),
    ));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    final backBefore = tester.getRect(find.text('Back'));
    final nextBefore = tester.getRect(find.text('Continue'));
    final field = find.byType(TextField).last;
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.enterText(field, 'test-only');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    tester.view.padding = FakeViewPadding.zero;
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(tester.getRect(find.text('Back')), backBefore);
    expect(tester.getRect(find.text('Continue')), nextBefore);
    expect(tester.getBottomLeft(field).dy, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('setup rejects invalid SSH ports before preferences',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child:
          MaterialApp(theme: AppTheme.light(), home: const SetupWizardPage()),
    ));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'router.local:9090');
    final port = find.byKey(const ValueKey('ssh_port_field'));
    await tester.ensureVisible(port);
    await tester.enterText(port, '65536');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('SSH port must be an integer between 1 and 65535'),
        findsOneWidget);
    expect((await SharedPreferences.getInstance()).containsKey('clash_host'),
        isFalse);
    await tester.enterText(port, '2222');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('English setup preferences scroll without scaling the page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppLocaleController.instance.setLanguage(AppLanguage.english);
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await AppLocaleController.instance.setLanguage(AppLanguage.english);
    });

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.2),
            ),
            child: child!,
          ),
          home: const SetupWizardPage(),
        ),
      ),
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '192.168.1.1:9090');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Preferences'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('setup_preferences_scroll')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Preferences'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    expect(find.byType(ThemeModeSelector), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme_mode_system_switch')),
      findsOneWidget,
    );
    final zashboardOption = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('Zashboard panel'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final decoration = zashboardOption.decoration! as BoxDecoration;
    expect(decoration.border!.top.color, AppTheme.lightPrimary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short screens keep setup typography at its intended size',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppLocaleController.instance.setLanguage(AppLanguage.english);
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await AppLocaleController.instance.setLanguage(AppLanguage.english);
    });

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SetupWizardPage(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('setup_welcome_scroll')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Welcome to Proxly'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('setup_config_scroll')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Connection settings'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );

    await tester.enterText(
      find.byType(TextField).first,
      '192.168.1.1:9090',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('setup_preferences_scroll')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Preferences'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

class _Detection extends RouterDetectionService {
  _Detection(this.result);
  final Future<RouterDetectionResult> Function() result;
  String? lastHost, lastPassword;
  int? lastPort;
  @override
  Future<RouterDetectionResult> detect(
      {required String host,
      required String token,
      required String sshPassword,
      required int sshPort}) {
    lastHost = host;
    lastPassword = sshPassword;
    lastPort = sshPort;
    return result();
  }
}
