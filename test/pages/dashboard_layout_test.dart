import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/home_page.dart';
import 'package:proxly/services/dashboard_layout_store.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/dashboard/dashboard_card_list.dart';
import 'package:proxly/widgets/dashboard/clash_overview_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester,
      {String language = 'zh_CN', double scale = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', language);
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const HomePage(autoLoad: false))));
    await tester.pump();
  }

  testWidgets(
      'home defaults to the requested cards and persists a drag and visibility',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpHome(tester);
    final list =
        tester.widget<DashboardCardList>(find.byType(DashboardCardList));
    expect(list.layout.order.take(4), [
      DashboardCardId.status,
      DashboardCardId.currentYaml,
      DashboardCardId.operations,
      DashboardCardId.quickSettings
    ]);
    await tester.tap(find.byKey(const ValueKey('home_customize_button')));
    await tester.pump();
    final start = tester.getCenter(find.byKey(const ValueKey('drag_status')));
    final end = tester
        .getBottomLeft(find.byKey(const ValueKey('dashboard_currentYaml')));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    for (var y = start.dy + 60; y <= end.dy; y += 25) {
      await gesture.moveTo(Offset(start.dx, y));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(list.layout.order.first, DashboardCardId.currentYaml);
    await tester.tap(find.byKey(const ValueKey('visible_status')));
    await tester.pump();
    await tester.tap(find.byTooltip('完成'));
    await tester.pump();
    expect(find.byKey(const ValueKey('dashboard_status')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpHome(tester);
    final restored =
        tester.widget<DashboardCardList>(find.byType(DashboardCardList)).layout;
    expect(restored.order.first, DashboardCardId.currentYaml);
    expect(restored.isVisible(DashboardCardId.status), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'all hidden cards can be restored and English controls fit a narrow screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final layout = DashboardLayoutStore();
    for (final id in DashboardCardId.values) {
      await layout.setVisible(id, false);
    }
    layout.dispose();
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpHome(tester, language: 'en', scale: 1.3);
    expect(find.textContaining('Cards are hidden'), findsOneWidget);
    await tester.tap(find.byTooltip('Customize dashboard'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visible_status')), findsOneWidget);
    await tester.tap(find.text('Reset layout'));
    await tester.pump();
    await tester.tap(find.byTooltip('Done'));
    await tester.pump();
    for (final id in DashboardCardId.values) {
      await tester.scrollUntilVisible(
          find.byKey(ValueKey('dashboard_${id.name}')), 180,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'overview retains the three statistics, chart geometry and timeline',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
                body: ClashOverviewCard(
                    activeConnections: 8,
                    totalDownload: 1024,
                    totalUpload: 2048,
                    downloadSpeeds: List.filled(60, 1024),
                    uploadSpeeds: List.filled(60, 512),
                    currentDownSpeed: 1024,
                    currentUpSpeed: 512)))));
    final y = tester.getTopLeft(find.text('活跃连接')).dy;
    expect(tester.getTopLeft(find.text('累计下载')).dy, y);
    expect(tester.getTopLeft(find.text('累计上传')).dy, y);
    final chart = find.byWidgetPredicate((w) =>
        w is CustomPaint &&
        w.painter.runtimeType.toString() == '_SpeedChartPainter');
    expect(tester.getSize(chart).height, 100);
    for (final label in ['60s', '30s', '0s', '↓ 1.0KB/s', '↑ 512B/s']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
