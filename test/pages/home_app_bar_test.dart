import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/home_page.dart';
import 'package:proxly/widgets/dashboard/home_app_bar.dart';
import 'package:proxly/widgets/dashboard/clash_traffic_card.dart';
import 'package:proxly/services/clash_service.dart';
import 'package:proxly/services/openclash_restart_coordinator.dart';
import 'package:proxly/widgets/adaptive_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpHeader(
    WidgetTester tester, {
    required bool showConsoleButton,
  }) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: Scaffold(
            appBar: HomeAppBar(
              showConsoleButton: showConsoleButton,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              dividerColor: Colors.black12,
              onConsolePressed: () {},
              onCustomizePressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'console is hidden by default and dashboard customization stays visible',
      (tester) async {
    await pumpHeader(tester, showConsoleButton: false);

    expect(find.byKey(const ValueKey('home_console_button')), findsNothing);
    expect(
      find.byKey(const ValueKey('home_customize_button')),
      findsOneWidget,
    );

    final controlCenterButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('home_customize_button')),
    );
    expect(
      controlCenterButton.style?.overlayColor
          ?.resolve(<WidgetState>{WidgetState.pressed}),
      Colors.transparent,
    );
  });

  testWidgets('console appears in the top-left when enabled', (tester) async {
    await pumpHeader(tester, showConsoleButton: true);

    final consoleButton = find.byKey(const ValueKey('home_console_button'));
    expect(consoleButton, findsOneWidget);
    expect(
      find.byKey(const ValueKey('home_customize_button')),
      findsOneWidget,
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

    final scrollView = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'AdaptivePullRefresh',
      ),
      findsNothing,
    );
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(scrollView.padding, const EdgeInsets.fromLTRB(16, 16, 16, 42));
    expect(scrollView.padding!.bottom, lessThan(80));
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
