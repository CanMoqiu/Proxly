import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/app_route_observer.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/clash_control_center_page.dart';
import 'package:proxly/services/openclash_quick_settings_service.dart';
import 'package:proxly/services/openclash_restart_coordinator.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('control center adapts to a narrow English layout',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        AppLocaleScope(
          controller: AppLocaleController.instance,
          child: MaterialApp(
            key: ValueKey(brightness),
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: const ClashControlCenterPage(autoLoad: false),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Clash Control Center'), findsOneWidget);
      expect(find.text('Maintenance'), findsOneWidget);
      expect(find.text('OpenClash quick settings'), findsOneWidget);
      expect(find.text('Clear DNS cache'), findsOneWidget);
      expect(find.text('Close connections'), findsOneWidget);
      expect(find.byTooltip('Refresh quick settings'), findsNothing);
      expect(
          find.byKey(const ValueKey('quick_setting_sniffer')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_setting_dns_proxy')),
          findsOneWidget);
      expect(
        find.byKey(const ValueKey('quick_setting_stream_unlock')),
        findsOneWidget,
      );

      final maintenanceY = tester.getTopLeft(find.text('Maintenance')).dy;
      final quickSettingsY =
          tester.getTopLeft(find.text('OpenClash quick settings')).dy;
      expect(maintenanceY, lessThan(quickSettingsY));
      await tester.scrollUntilVisible(
        find.text('YAML configuration files'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Active configuration'), findsOneWidget);
      expect(find.text('YAML configuration files'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('quick settings stay between maintenance and configuration',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ClashControlCenterPage(autoLoad: false),
        ),
      ),
    );

    final maintenanceY = tester.getTopLeft(find.text('Maintenance')).dy;
    final quickSettingsY =
        tester.getTopLeft(find.text('OpenClash quick settings')).dy;
    final activeConfigY =
        tester.getTopLeft(find.text('Active configuration')).dy;
    final yamlY = tester.getTopLeft(find.text('YAML configuration files')).dy;
    final restartY =
        tester.getTopLeft(find.byKey(const ValueKey('maintenance_restart'))).dy;
    final dnsY = tester
        .getTopLeft(find.byKey(const ValueKey('maintenance_flush_dns')))
        .dy;
    final closeConnectionsY = tester
        .getTopLeft(
          find.byKey(const ValueKey('maintenance_close_connections')),
        )
        .dy;
    expect(restartY, lessThan(dnsY));
    expect(closeConnectionsY, dnsY);
    final restartButton = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('maintenance_restart')),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(
      restartButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      const Color(0xFFD97706),
    );
    expect(
      restartButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      Colors.white,
    );
    for (final key in <String>[
      'maintenance_flush_dns',
      'maintenance_close_connections',
      'current_config_switch',
    ]) {
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      expect(
        button.style,
        isNull,
        reason: '$key must inherit the shared FilledButton theme',
      );
    }
    expect(maintenanceY, lessThan(quickSettingsY));
    expect(quickSettingsY, lessThan(activeConfigY));
    expect(activeConfigY, lessThan(yamlY));
  });

  testWidgets('control center uses ordinary scroll without pull refresh',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(
          home: ClashControlCenterPage(autoLoad: false),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'AdaptivePullRefresh',
      ),
      findsNothing,
    );
    expect(find.byType(RefreshIndicator), findsNothing);

    final listView = tester.widget<ListView>(find.byType(ListView).first);
    expect(listView.physics, isA<ClampingScrollPhysics>());
  });

  testWidgets('maintenance actions require confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(
          home: ClashControlCenterPage(autoLoad: false),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('maintenance_flush_dns')));
    await tester.pumpAndSettle();
    expect(find.text('Clear DNS cache?'), findsOneWidget);
    expect(
      find.text('This clears the Clash core DNS cache. Continue?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Clear DNS cache?'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('maintenance_close_connections')));
    await tester.pumpAndSettle();
    expect(find.text('Close all connections?'), findsOneWidget);
    expect(find.textContaining('Some apps may reconnect automatically'),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Close all connections?'), findsNothing);
  });

  testWidgets('quick setting changes apply immediately without restart',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final service = _FakeQuickSettingsService();
    var restartCount = 0;
    final coordinator = OpenClashRestartCoordinator(
      restartCommand: (_) async => restartCount++,
      healthProbe: () async {},
      delay: (_) async {},
      initialWait: Duration.zero,
      requiredHealthyChecks: 1,
      terminalStateDuration: Duration.zero,
    );
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ClashControlCenterPage(
                      quickSettingsService: service,
                      restartCoordinator: coordinator,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Changes apply immediately'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey(
          'quick_setting_proxy_OpenClashProxyMode.global',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.applyCount, 1);
    expect(restartCount, 0);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Apply quick settings?'), findsNothing);
    expect(service.applyCount, 1);
    expect(restartCount, 0);
  });

  testWidgets('all quick settings can enter applying state', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();

    final targets = <({
      String name,
      OpenClashQuickSettingKey key,
      Finder Function() finder,
    })>[
      (
        name: 'run variant',
        key: OpenClashQuickSettingKey.runVariant,
        finder: () => find.byKey(
              const ValueKey('quick_setting_run_OpenClashRunVariant.tun'),
            ),
      ),
      (
        name: 'proxy mode',
        key: OpenClashQuickSettingKey.proxyMode,
        finder: () => find.byKey(
              const ValueKey(
                'quick_setting_proxy_OpenClashProxyMode.global',
              ),
            ),
      ),
      (
        name: 'area bypass',
        key: OpenClashQuickSettingKey.areaBypass,
        finder: () => find.byKey(
              const ValueKey(
                'quick_setting_area_OpenClashAreaBypass.overseas',
              ),
            ),
      ),
      (
        name: 'sniffer',
        key: OpenClashQuickSettingKey.sniffer,
        finder: () => find.descendant(
              of: find.byKey(const ValueKey('quick_setting_sniffer')),
              matching: find.byType(Switch),
            ),
      ),
      (
        name: 'DNS proxy',
        key: OpenClashQuickSettingKey.dnsProxy,
        finder: () => find.descendant(
              of: find.byKey(const ValueKey('quick_setting_dns_proxy')),
              matching: find.byType(Switch),
            ),
      ),
      (
        name: 'stream unlock',
        key: OpenClashQuickSettingKey.streamUnlock,
        finder: () => find.descendant(
              of: find.byKey(const ValueKey('quick_setting_stream_unlock')),
              matching: find.byType(Switch),
            ),
      ),
    ];

    for (final target in targets) {
      final service = _FakeQuickSettingsService()..gate = Completer<void>();
      await tester.pumpWidget(
        AppLocaleScope(
          controller: AppLocaleController.instance,
          child: MaterialApp(
            home: ClashControlCenterPage(quickSettingsService: service),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final control = target.finder();
      await tester.ensureVisible(control);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(control, warnIfMissed: false);
      await tester.pump();

      expect(service.applyCount, 1, reason: target.name);
      expect(service.lastKey, target.key, reason: target.name);
      expect(
        find.byKey(
          const ValueKey('control_center_app_bar_activity_indicator'),
        ),
        findsOneWidget,
        reason: target.name,
      );
      expect(
        find.byKey(const ValueKey('quick_setting_loading_indicator')),
        findsNothing,
        reason: target.name,
      );

      service.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });

  testWidgets('quick setting controls stay locked during an apply operation',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final service = _FakeQuickSettingsService()..gate = Completer<void>();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: ClashControlCenterPage(quickSettingsService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('quick_setting_proxy_OpenClashProxyMode.global'),
      ),
    );
    await tester.pump();
    expect(service.applyCount, 1);
    expect(find.text('Applying setting...'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('control_center_app_bar_activity_indicator'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('quick_setting_loading_indicator')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('quick_setting_area_OpenClashAreaBypass.overseas'),
      ),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(service.applyCount, 1);

    service.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Proxy mode updated'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('control_center_app_bar_activity_indicator'),
      ),
      findsNothing,
    );
  });

  testWidgets('auto sync refreshes while visible and pauses when covered',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final service = _FakeQuickSettingsService();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          navigatorObservers: [shellRouteObserver],
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ClashControlCenterPage(
                      quickSettingsService: service,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(service.loadCount, 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(service.loadCount, 2);

    unawaited(
      Navigator.of(tester.element(find.byType(ClashControlCenterPage))).push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final coveredLoadCount = service.loadCount;
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(service.loadCount, coveredLoadCount);

    Navigator.of(tester.element(find.text('covered'))).pop();
    await tester.pumpAndSettle();
    expect(service.loadCount, greaterThan(coveredLoadCount));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('silent auto sync does not block quick setting taps',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final service = _FakeQuickSettingsService()..captureLoadSnapshot = true;

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          navigatorObservers: [shellRouteObserver],
          home: ClashControlCenterPage(quickSettingsService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.loadCount, 1);

    service.loadGate = Completer<void>();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(service.loadCount, 2);

    await tester.tap(
      find.byKey(
        const ValueKey('quick_setting_proxy_OpenClashProxyMode.global'),
      ),
    );
    await tester.pump();
    expect(service.applyCount, 1);

    service.loadGate!.complete();
    await tester.pumpAndSettle();
    expect(service._settings.proxyMode, OpenClashProxyMode.global);
    expect(service.applyCount, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('silent auto sync failures do not show feedback banners',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final service = _FakeQuickSettingsService();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          navigatorObservers: [shellRouteObserver],
          home: ClashControlCenterPage(quickSettingsService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.loadCount, 1);

    service.loadError = Exception('boom');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(service.loadCount, 2);
    expect(find.byKey(const ValueKey('app_feedback_banner')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quick setting failures use the transient feedback banner',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final service = _FakeQuickSettingsService()
      ..failureCode = 'controller_unauthorized'
      ..failureDetail = 'HTTP 401: invalid token';

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: ClashControlCenterPage(quickSettingsService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('quick_setting_proxy_OpenClashProxyMode.global'),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('app_feedback_banner')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.textContaining('HTTP 401: invalid token'), findsOneWidget);
    expect(find.text('Applying setting...'), findsNothing);
  });

  testWidgets('saved run mode failure offers a restart retry', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh'});
    await AppLocaleController.instance.load();
    final service = _FakeQuickSettingsService()
      ..failureCode = 'restart_failed'
      ..failureDetail = '重启或等待 OpenClash 上线：连接超时'
      ..failureChangesPersisted = true
      ..failureCanRetry = true;

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: ClashControlCenterPage(quickSettingsService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('quick_setting_run_OpenClashRunVariant.tun'),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('设置已保存，但 OpenClash 未恢复正常'),
      findsOneWidget,
    );
    expect(find.textContaining('可使用重启按钮重试'), findsOneWidget);
  });

  testWidgets('reopened control center keeps showing a running restart',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final gate = Completer<void>();
    final coordinator = OpenClashRestartCoordinator(
      restartCommand: (_) => gate.future,
      healthProbe: () async {},
      delay: (_) async {},
      initialWait: Duration.zero,
      requiredHealthyChecks: 1,
      terminalStateDuration: Duration.zero,
    );
    addTearDown(coordinator.dispose);
    final restart = coordinator.restart();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: ClashControlCenterPage(
            autoLoad: false,
            restartCoordinator: coordinator,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Restarting OpenClash...'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('control_center_app_bar_activity_indicator'),
      ),
      findsOneWidget,
    );
    final restartButton = find.descendant(
      of: find.byKey(const ValueKey('maintenance_restart')),
      matching: find.byType(FilledButton),
    );
    expect(
      find.descendant(
        of: restartButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: ClashControlCenterPage(
            autoLoad: false,
            restartCoordinator: coordinator,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Restarting OpenClash...'), findsOneWidget);

    gate.complete();
    await restart;
  });
}

class _FakeQuickSettingsService extends OpenClashQuickSettingsService {
  _FakeQuickSettingsService() : super(commandRunner: (_) async => '');

  int applyCount = 0;
  int loadCount = 0;
  OpenClashQuickSettingKey? lastKey;
  OpenClashQuickSettings? lastDesired;
  Completer<void>? gate;
  Completer<void>? loadGate;
  bool captureLoadSnapshot = false;
  Object? loadError;
  String? failureCode;
  String? failureDetail;
  bool failureChangesPersisted = false;
  bool failureCanRetry = false;
  OpenClashQuickSettings _settings = _initialSettings;

  @override
  Future<OpenClashQuickSettings> load({bool preferLiveProxyMode = true}) async {
    loadCount++;
    final error = loadError;
    if (error != null) throw error;
    final snapshot = _settings;
    await loadGate?.future;
    return captureLoadSnapshot ? snapshot : _settings;
  }

  @override
  Future<OpenClashQuickSettingApplyResult> applyChange({
    required OpenClashQuickSettings original,
    required OpenClashQuickSettings desired,
    required OpenClashQuickSettingKey key,
  }) async {
    applyCount++;
    lastKey = key;
    lastDesired = desired;
    await gate?.future;
    if (failureCode != null) {
      return OpenClashQuickSettingApplyResult.failure(
        settings: original,
        errorCode: failureCode!,
        errorDetail: failureDetail,
        failureStage: failureChangesPersisted ? '重启 OpenClash' : null,
        rollbackAttempted: true,
        rollbackSucceeded: true,
        changesPersisted: failureChangesPersisted,
        canRetry: failureCanRetry,
      );
    }
    _settings = desired;
    return OpenClashQuickSettingApplyResult.success(desired);
  }

  static const _initialSettings = OpenClashQuickSettings(
    baseMode: OpenClashBaseMode.fakeIp,
    runVariant: OpenClashRunVariant.compatibility,
    proxyMode: OpenClashProxyMode.rule,
    areaBypass: OpenClashAreaBypass.disabled,
    snifferEnabled: false,
    dnsProxyEnabled: false,
    streamUnlockEnabled: false,
    routerSelfProxyEnabled: true,
    streamUnlockSupported: true,
    rawRunMode: 'fake-ip',
  );
}
