import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/home_page.dart';
import 'package:proxly/services/connection_feedback.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/dashboard/clash_status_card.dart';
import 'package:proxly/widgets/dashboard/home_app_bar.dart';
import 'package:proxly/widgets/dashboard/clash_traffic_card.dart';
import 'package:proxly/services/clash_service.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/openclash_restart_coordinator.dart';
import 'package:proxly/widgets/adaptive_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpHeader(
    WidgetTester tester, {
    required bool showConsoleButton,
    String? deviceName,
    TextScaler? textScaler,
  }) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'zh_CN',
      if (deviceName != null)
        'connection_profiles_v1': jsonEncode({
          'activeId': 'home',
          'devices': [
            {
              'id': 'home',
              'name': deviceName,
              'host': 'router.local:9090',
              'sshPort': 22,
              'credentials': 'test-only-key',
            },
          ],
        }),
    });
    await ConnectionSettingsStore.instance.initializeProfiles();
    await AppLocaleController.instance.load();
    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          builder: (context, child) => textScaler == null
              ? child!
              : MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
          home: Scaffold(
            appBar: HomeAppBar(
              showConsoleButton: showConsoleButton,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              dividerColor: Colors.black12,
              onConsolePressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'header has no customization button and console is hidden by default',
      (tester) async {
    await pumpHeader(tester, showConsoleButton: false);

    expect(find.byKey(const ValueKey('home_console_button')), findsNothing);
    expect(
      find.byKey(const ValueKey('home_customize_button')),
      findsNothing,
    );
  });

  testWidgets('device identity is on the left and console is on the right',
      (tester) async {
    await pumpHeader(tester, showConsoleButton: true, deviceName: 'Home Lab');

    final consoleButton = find.byKey(const ValueKey('home_console_button'));
    expect(consoleButton, findsOneWidget);
    expect(
      find.byKey(const ValueKey('home_customize_button')),
      findsNothing,
    );

    final consoleIcon = find.descendant(
      of: consoleButton,
      matching: find.byType(SvgPicture),
    );
    expect(consoleIcon, findsOneWidget);
    expect(tester.getSize(consoleIcon), const Size.square(22));

    final tapTargetSize = tester.getSize(consoleButton);
    expect(tapTargetSize.width, greaterThanOrEqualTo(48));
    expect(tapTargetSize.height, greaterThanOrEqualTo(48));
    final deviceIcon = find.byKey(const ValueKey('home_device_icon'));
    final deviceName = find.text('Home Lab');
    expect(tester.getSize(deviceIcon), const Size.square(18));
    expect(tester.getCenter(deviceIcon).dx,
        lessThan(tester.getCenter(deviceName).dx));
    final appBar = find.byType(AppBar);
    expect(
        tester.getCenter(deviceIcon).dx, lessThan(tester.getCenter(appBar).dx));
    expect(tester.getCenter(consoleButton).dx,
        greaterThan(tester.getCenter(appBar).dx));

    await ConnectionSettingsStore.instance.renameDevice('home', 'Living Room');
    await tester.pump();
    expect(
      tester
          .widget<AdaptiveMarqueeText>(
              find.byKey(const ValueKey('home_device_name')))
          .text,
      'Living Room',
    );
  });

  testWidgets('a long device name scrolls inside the left of a narrow bar',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpHeader(
      tester,
      showConsoleButton: true,
      deviceName: 'Router in the office at the other end of the house',
      textScaler: const TextScaler.linear(1.8),
    );

    final name = find.byKey(const ValueKey('home_device_name'));
    final clip = find.descendant(of: name, matching: find.byType(ClipRect));
    final title = find.text('首页');
    final console = find.byKey(const ValueKey('home_console_button'));
    expect(tester.widget(name), isA<AdaptiveMarqueeText>());
    expect(clip, findsOneWidget);
    expect(tester.getRect(clip).right, lessThan(tester.getRect(title).left));
    expect(
        tester.getCenter(title).dx, tester.getCenter(find.byType(AppBar)).dx);
    expect(
        tester.getRect(console).left, greaterThan(tester.getRect(title).right));
    final track = find.descendant(of: name, matching: find.byType(Positioned));
    expect(tester.widget<Positioned>(track).left, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(tester.widget<Positioned>(track).left, lessThan(0));
    expect(tester.getRect(clip).right, lessThan(tester.getRect(title).left));
  });

  testWidgets('offline status places themed retry beside wrapping feedback',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var retries = 0;

    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ClashStatusCard(
                loading: false,
                online: false,
                restartBusy: false,
                restartFailed: false,
                error: ConnectionFeedback.routerUnavailable,
                coreVersion: '--',
                onRetry: () => retries++,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final message = find.text(tr(ConnectionFeedback.routerUnavailable));
      final retry = find.widgetWithText(FilledButton, 'Retry');
      final messageRect = tester.getRect(message);
      final retryRect = tester.getRect(retry);
      expect(messageRect.top,
          greaterThan(tester.getRect(find.text('Runtime status')).bottom));
      expect(messageRect.bottom,
          lessThan(tester.getRect(find.text('Core version')).top));
      expect(messageRect.height, greaterThan(40));
      expect(retryRect.left - messageRect.right, closeTo(8, .01));
      expect(retryRect.center.dy, closeTo(messageRect.center.dy, .01));
      expect(retryRect.height, greaterThanOrEqualTo(48));
      final buttonMaterial =
          find.descendant(of: retry, matching: find.byType(Material));
      expect(tester.widget<Material>(buttonMaterial).color,
          theme.colorScheme.primary);
      await tester.tap(retry);
      await tester.pump();
    }

    expect(retries, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home status follows the global OpenClash restart',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
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
          home: HomePage(restartCoordinator: coordinator, autoLoad: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('重启中'), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard_activity_indicator')),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is LinearProgressIndicator && widget.value == null),
        findsNothing);

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await restart;
  });

  testWidgets('home scroll padding stays compact on short safe-area screens',
      (tester) async {
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(bottom: 18),
            ),
            child: child!,
          ),
          home: HomePage(restartCoordinator: coordinator, autoLoad: false),
        ),
      ),
    );
    await tester.pump();

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'AdaptivePullRefresh',
      ),
      findsNothing,
    );
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(scrollView.padding, const EdgeInsets.fromLTRB(16, 24, 16, 42));
    expect(scrollView.padding!.resolve(TextDirection.ltr).bottom, lessThan(80));
    expect(scrollView.physics, isA<ClampingScrollPhysics>());

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await restart;
  });

  testWidgets('subscription traffic labels only show values', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();

    const limited = ProviderTraffic(
      name: 'limited',
      used: 2 * 1024,
      total: 5 * 1024,
    );
    const unlimited = ProviderTraffic(
      name: 'unlimited',
      used: 1536,
      total: 0,
      expire: 0,
    );

    expect(formatHomeProviderTrafficLabel(limited), '3.0KB / 5.0KB');
    expect(formatHomeProviderTrafficLabel(unlimited), '1.5KB / 无限制');
  });

  testWidgets('subscription traffic row keeps traffic unconstrained',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: TickerMode(
              enabled: false,
              child: SizedBox(
                width: 240,
                child: HomeSubscriptionTrafficRow(
                  name: 'Very long subscription provider name',
                  trafficLabel: '999.99GB / 1.00TB',
                  textPrimary: Colors.black,
                  textSecondary: Colors.grey,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final trafficText = tester.widget<Text>(find.text('999.99GB / 1.00TB'));
    expect(trafficText.textAlign, TextAlign.right);
    expect(trafficText.maxLines, 1);
    expect(trafficText.softWrap, isFalse);
    expect(trafficText.overflow, TextOverflow.visible);
    expect(find.byType(AdaptiveMarqueeText), findsOneWidget);
    expect(
      tester
          .widget<AdaptiveMarqueeText>(find.byType(AdaptiveMarqueeText))
          .startDelay,
      const Duration(seconds: 3),
    );
    expect(
      find.ancestor(
        of: find.text('999.99GB / 1.00TB'),
        matching: find.byType(Flexible),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
  });
}
