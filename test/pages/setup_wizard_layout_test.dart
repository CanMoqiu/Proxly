import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxly/app_navigator.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/optional_settings_visibility.dart';
import 'package:proxly/services/router_detection_service.dart';
import 'package:proxly/services/router_tool.dart';
import 'package:proxly/services/ssh_host_trust_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/setup_wizard_page.dart';
import 'package:proxly/pages/settings_page.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/adaptive_ui.dart';
import 'package:proxly/widgets/controller_form_fields.dart';
import 'package:proxly/widgets/keyboard_focus_reveal.dart';
import 'package:proxly/widgets/app_popup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'next detects software before preferences and preserves a manual choice',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      OptionalSettingsVisibility.preferenceKey: true,
    });
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
        find.descendant(of: language, matching: find.byType(AppPickerChevron)),
        findsOneWidget);
    expect(tester.getRect(language).right,
        closeTo(tester.getRect(find.byType(PageView)).right - 32, 0.01));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<RouterTool>), findsNothing);
    expect(find.text('Identify proxy software and core'), findsNothing);
    final selector = find.byKey(const ValueKey('controller_backend_picker'));
    expect(tester.widget(selector), isA<AppSelectionPicker>());
    expect(
      find.descendant(of: selector, matching: find.byType(AppPickerChevron)),
      findsOneWidget,
    );
    await tester.tap(find.text('Proxy backend'));
    await tester.pumpAndSettle();
    expect(find.byType(AppOptionsSheet<RouterTool>), findsNothing);
    final backendValue = find.text('Detect automatically');
    expect(backendValue, findsOneWidget);
    expect(tester.getRect(find.text('Proxy backend')).right,
        lessThanOrEqualTo(tester.getRect(backendValue).left));
    final address = find.byKey(const ValueKey('controller_address_field'));
    final port = find.byKey(const ValueKey('controller_port_field'));
    final sshSecret = find.byKey(const ValueKey('ssh_secret_field'));
    await tester.enterText(address, 'router.local');
    await tester.enterText(port, '9095');
    await tester.ensureVisible(sshSecret);
    await tester.enterText(sshSecret, 'test-only-password');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    expect(selector, findsNothing);
    expect(tester.getTopLeft(find.text('Appearance')).dy,
        lessThan(tester.getTopLeft(find.text('Connections page display')).dy));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    final options = tester.widget<AppOptionsSheet<RouterTool>>(
        find.byType(AppOptionsSheet<RouterTool>));
    expect(options.selectedValue, RouterTool.nikki);
    expect(options.options.map((option) => option.value), RouterTool.values);
    expect(service.lastHost, 'router.local:9095');
    expect(service.lastPassword, 'test-only-password');
    expect(service.lastPort, 22);
    await tester.tap(find.text('OpenClash'));
    await tester.pumpAndSettle();
    await tester.enterText(port, '9096');
    expect(find.text('OpenClash'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('OpenClash'), findsOneWidget);
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
    final address = find.byKey(const ValueKey('controller_address_field'));
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
    expect(find.byType(AppOptionsSheet<RouterTool>), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final choice in [RouterTool.nikki, RouterTool.generic, null]) {
    testWidgets('finishing setup persists software choice $choice',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'app_language': 'en',
        'automatic_update_check_enabled': false,
        'connections_tab_mode': 'native',
      });
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
      final trust = SshHostTrustService.forTesting();
      addTearDown(trust.dispose);
      final fingerprint =
          Uint8List.fromList(utf8.encode('SHA256:initialRouter'));
      late final _Detection detector;
      detector = _Detection(() async {
        if (choice == null) throw StateError('offline');
        if (choice == RouterTool.nikki) {
          expect(detector.lastSshDeviceId, isNotNull);
          expect(
            await trust.verify('192.168.1.42', 2222, 'ssh-ed25519', fingerprint,
                deviceId: detector.lastSshDeviceId),
            isTrue,
          );
        }
        return RouterDetectionResult(
            tool: choice, core: ProxyCore.mihomo, version: 'test');
      });
      await tester.pumpWidget(AppLocaleScope(
          controller: AppLocaleController.instance,
          child: MaterialApp(
              navigatorKey: rootNavigatorKey,
              theme: AppTheme.light(),
              home: SetupWizardPage(detectionService: detector))));
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      final controllerPort =
          find.byKey(const ValueKey('controller_port_field'));
      final sshPort = find.byKey(const ValueKey('ssh_port_field'));
      for (final (field, hint) in [(controllerPort, '9090'), (sshPort, '22')]) {
        final input = tester.widget<TextField>(field);
        expect(input.controller!.text, isEmpty);
        expect(find.descendant(of: field, matching: find.text(hint)),
            findsNothing);
      }
      await tester.enterText(
        find.byKey(const ValueKey('controller_address_field')),
        '192.168.1.42',
      );
      if (choice == RouterTool.nikki) {
        await tester.ensureVisible(controllerPort);
        await tester.enterText(controllerPort, '9095');
        await tester.ensureVisible(sshPort);
        await tester.enterText(sshPort, '2222');
      }
      if (choice == RouterTool.nikki) {
        final name = find.byKey(const ValueKey('controller_name_field'));
        await tester.ensureVisible(name);
        await tester.enterText(name, ' Home Lab ');
      }
      if (choice != null) {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final selector =
            find.byKey(const ValueKey('controller_backend_picker'));
        await tester.ensureVisible(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Detect automatically'));
        await tester.pumpAndSettle();
        final option = choice == RouterTool.generic
            ? 'Mihomo / Clash generic configuration'
            : tr(choice.label);
        await tester.tap(find.descendant(
            of: find.byType(AppOptionsSheet<RouterTool>),
            matching: find.text(option)));
        await tester.pumpAndSettle();
        if (choice == RouterTool.generic) {
          expect(
              find.descendant(
                  of: selector, matching: find.text('Generic config')),
              findsOneWidget);
        }
      }
      await tester.tap(find.text('Continue'));
      if (choice == RouterTool.nikki) {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Verify SSH device identity'), findsOneWidget);
        await tester.tap(find.text('Trust and continue'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Connections page display'), findsNothing);
      await tester.tap(find.text('Finish setup'));
      await tester.pump(const Duration(milliseconds: 20));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('connections_tab_mode'), 'native');
      final store = ConnectionSettingsStore.instance;
      final saved = await store.load();
      expect(
          saved.host,
          choice == RouterTool.nikki
              ? '192.168.1.42:9095'
              : '192.168.1.42:9090');
      expect(saved.sshPort, choice == RouterTool.nikki ? 2222 : 22);
      expect(saved.routerTool, choice ?? RouterTool.generic);
      expect(saved.core, choice == null ? ProxyCore.unknown : ProxyCore.mihomo);
      expect(store.activeDevice?.name,
          choice == RouterTool.nikki ? 'Home Lab' : '192.168.1.42:9090');
      expect(store.activeDevice?.toolConfirmed, isTrue);
      expect(store.activeDevice?.selectionPending, isFalse);
      expect(saved.deviceId, detector.lastSshDeviceId);
      if (choice == RouterTool.nikki) {
        final verified =
            trust.verify('192.168.1.42', 2222, 'ssh-ed25519', fingerprint);
        await tester.pump();
        expect(find.text('Verify SSH device identity'), findsNothing);
        expect(await verified, isTrue);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'a newly focused connection field starts with its caret at the end',
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

    final name = find.byKey(const ValueKey('controller_name_field'));
    final field = tester.widget<TextField>(name);
    final controller = field.controller!;
    controller.text = 'Home Lab';
    await tester.pump();
    final editable = tester.state<EditableTextState>(
      find.descendant(of: name, matching: find.byType(EditableText)),
    );
    expect(editable.widget.focusNode.hasFocus, isFalse);
    Offset earlyPosition() {
      final box = editable.renderEditable;
      return box.localToGlobal(
        box.getLocalRectForCaret(const TextPosition(offset: 2)).center,
      );
    }

    await tester.tapAt(earlyPosition());
    await tester.pumpAndSettle();
    expect(editable.widget.focusNode.hasFocus, isTrue);
    expect(controller.selection.baseOffset, controller.text.length);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(earlyPosition());
    await tester.pump();
    expect(controller.selection.baseOffset, lessThan(controller.text.length));
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('outlined fields float their labels before revealing hints',
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

    final form = find.byType(ControllerFormFields);
    expect(find.descendant(of: form, matching: find.byType(Divider)),
        findsNothing);
    final fields = tester.widgetList<TextField>(
        find.descendant(of: form, matching: find.byType(TextField)));
    expect(fields, hasLength(6));
    for (final field in fields) {
      expect(field.decoration!.border, isA<OutlineInputBorder>());
      expect(field.decoration!.filled, isTrue);
    }

    for (final (key, title, placeholder) in [
      ('controller_address_field', 'Controller address', '192.168.1.1'),
      ('controller_port_field', 'Controller port', '9090'),
      ('ssh_port_field', 'SSH port', '22'),
    ]) {
      final field = find.byKey(ValueKey(key));
      final label = find.descendant(of: field, matching: find.text(title));
      final hint = find.descendant(of: field, matching: find.text(placeholder));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      final restingLabelY =
          tester.getTopLeft(label).dy - tester.getTopLeft(field).dy;
      expect(hint, findsNothing);

      await tester.tap(field);
      await tester.pump();
      final hintOpacity =
          find.ancestor(of: hint, matching: find.byType(Opacity)).first;
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<Opacity>(hintOpacity).opacity, 0);

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(label).dy - tester.getTopLeft(field).dy,
          lessThan(restingLabelY));
      expect(tester.getRect(label).center.dy,
          closeTo(tester.getTopLeft(field).dy, 2));
      expect(tester.widget<Opacity>(hintOpacity).opacity, 1);
      expect(
          tester.getTopLeft(hint).dx, closeTo(tester.getTopLeft(label).dx, .1));
      final palette = AppPalette.of(tester.element(field));
      expect(
          tester.widget<Text>(hint).style!.color,
          Color.alphaBlend(
              palette.textSecondary.withValues(alpha: .84), palette.surface));

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
      expect(tester.getTopLeft(label).dy - tester.getTopLeft(field).dy,
          closeTo(restingLabelY, .1));
    }
  });

  testWidgets('setup and settings show test feedback below their actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'clash_host': 'router.local:9090',
    });
    const secureStorage =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorage, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(secureStorage, null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 560);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await AppLocaleController.instance.load();
    final service = _Detection(() async => const RouterDetectionResult(
        tool: RouterTool.generic, core: ProxyCore.mihomo, version: 'test'));
    Future<void> pumpPage(Widget page) async {
      await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(theme: AppTheme.light(), home: page),
      ));
      await tester.pumpAndSettle();
    }

    final address = find.byKey(const ValueKey('controller_address_field'));
    final testAction = find.text('Test connection');
    final feedback = find.byType(ControllerTestFeedback);
    for (final isSetup in [true, false]) {
      if (isSetup) {
        await pumpPage(SetupWizardPage(detectionService: service));
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();
        await tester.enterText(address, 'router.local');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      } else {
        await pumpPage(SettingsPage(detectionService: service));
      }

      await tester.ensureVisible(testAction);
      await tester.pumpAndSettle();
      await tester.tap(testAction);
      await tester.pumpAndSettle();
      final card = find.byKey(
        ValueKey(
            isSetup ? 'setup_connection_card' : 'settings_connection_card'),
      );
      expect(find.descendant(of: card, matching: feedback), findsOneWidget);
      expect(find.text('Connection successful').hitTestable(), findsOneWidget);
      expect(tester.getRect(feedback).top,
          greaterThan(tester.getRect(testAction).bottom));
      await tester.enterText(address, 'other-router.local');
      await tester.pump();
      expect(feedback, findsNothing);
    }
  });

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
    final field = find.byKey(const ValueKey('ssh_secret_field'));
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
    await tester.enterText(
        find.byKey(const ValueKey('controller_address_field')),
        'router.local:9090');
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
    SharedPreferences.setMockInitialValues({
      OptionalSettingsVisibility.preferenceKey: true,
    });
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
    await tester.enterText(
        find.byKey(const ValueKey('controller_address_field')),
        '192.168.1.1:9090');
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
    final logo = find.byType(Image);
    final shortLogo = tester.getSize(logo);
    expect(find.text('Get started').hitTestable(), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.getSize(logo).width, greaterThan(shortLogo.width));
    final welcomeScroll = find.byKey(const ValueKey('setup_welcome_scroll'));
    final topGap = tester.getRect(logo).top - tester.getRect(welcomeScroll).top;
    expect(topGap, inInclusiveRange(12, 36));
    expect(find.text('Get started').hitTestable(), findsOneWidget);
    tester.view.physicalSize = const Size(360, 520);
    await tester.pumpAndSettle();
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
      find.byKey(const ValueKey('controller_address_field')),
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
  String? lastHost, lastPassword, lastSshDeviceId;
  int? lastPort;
  @override
  Future<RouterDetectionResult> detect(
      {required String host,
      required String token,
      required String sshPassword,
      required int sshPort,
      String? sshDeviceId}) {
    lastHost = host;
    lastSshDeviceId = sshDeviceId;
    lastPassword = sshPassword;
    lastPort = sshPort;
    return result();
  }
}
