import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/app_route_observer.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/home_page.dart';
import 'package:proxly/services/dashboard_layout_store.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/dashboard/dashboard_card_list.dart';
import 'package:proxly/widgets/dashboard/dashboard_card_titles.dart';
import 'package:proxly/widgets/dashboard/clash_overview_card.dart';
import 'package:proxly/widgets/dashboard/quick_settings_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester,
      {String language = 'zh_CN', double scale = 1, bool active = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', language);
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            theme: AppTheme.light(),
            navigatorObservers: [shellRouteObserver],
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: HomePage(autoLoad: false, active: active))));
    await tester.pump();
  }

  Future<void> toggleEditing(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('home_customize_button'));
    await tester.scrollUntilVisible(button, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
  }

  Future<void> scrollToTop(WidgetTester tester) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
  }

  testWidgets('home aligns default cards and persists a drag and visibility',
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
    expect(list.layout.order, [
      DashboardCardId.status,
      DashboardCardId.traffic,
      DashboardCardId.overview,
      DashboardCardId.currentYaml,
      DashboardCardId.operations,
      DashboardCardId.quickSettings
    ]);
    Rect? previousCard;
    double? titleLeft;
    for (final id in list.layout.order) {
      final card = tester.getRect(find
          .descendant(
              of: find.byKey(ValueKey('dashboard_${id.name}')),
              matching: find.byWidgetPredicate((widget) =>
                  widget is Container && widget.decoration is BoxDecoration))
          .first);
      final title = tester.getRect(find.text(dashboardCardTitle(id)));
      titleLeft ??= title.left;
      expect(title.left, titleLeft);
      expect(title.top - card.top, closeTo(16.5, 0.1));
      expect(card.left, 16);
      expect(card.right, 384);
      if (previousCard != null) {
        expect(card.top - previousCard.bottom, 12);
      }
      previousCard = card;
    }
    await toggleEditing(tester);
    await scrollToTop(tester);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
    final start =
        tester.getCenter(find.byKey(const ValueKey('dashboard_status')));
    final end =
        tester.getBottomLeft(find.byKey(const ValueKey('dashboard_traffic')));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 650));
    expect(haptics, contains('HapticFeedbackType.mediumImpact'));
    expect(
        find.byKey(const ValueKey('dashboard_drag_feedback')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    final proxy = tester.widget<Transform>(
        find.byKey(const ValueKey('dashboard_drag_feedback')));
    expect(proxy.transform.entry(0, 0), lessThan(1));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    for (var y = start.dy + 60; y <= end.dy; y += 25) {
      await gesture.moveTo(Offset(start.dx, y));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(list.layout.order.first, DashboardCardId.traffic);
    await tester.tap(find.byKey(const ValueKey('visible_status')));
    await tester.pump();
    await toggleEditing(tester);
    expect(find.byKey(const ValueKey('dashboard_status')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpHome(tester);
    final restored =
        tester.widget<DashboardCardList>(find.byType(DashboardCardList)).layout;
    expect(restored.order.first, DashboardCardId.traffic);
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
    await toggleEditing(tester);
    await tester.pumpAndSettle();
    await scrollToTop(tester);
    expect(find.byKey(const ValueKey('visible_status')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Reset layout'), 350,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Reset layout'));
    await tester.pumpAndSettle();
    expect(find.text('Done').hitTestable(), findsOneWidget);
    await toggleEditing(tester);
    await scrollToTop(tester);
    for (final id in DashboardCardId.values) {
      await tester.scrollUntilVisible(
          find.byKey(ValueKey('dashboard_${id.name}')), 180,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving home cancels layout editing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHome(tester);
    await toggleEditing(tester);
    expect(find.byKey(const ValueKey('visible_quickSettings')), findsOneWidget);

    await pumpHome(tester, active: false);
    await pumpHome(tester);
    expect(find.byKey(const ValueKey('visible_quickSettings')), findsNothing);
    expect(find.text('自定义首页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening another route cancels layout editing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHome(tester);
    await toggleEditing(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page'))));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('visible_quickSettings')), findsNothing);
    expect(find.text('自定义首页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('short screens keep edit tools below cards and shrink tall drags',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpHome(tester, language: 'en', scale: 1.3);
    final quickSettings = find.byType(OpenClashQuickSettingsCard);
    await tester.scrollUntilVisible(quickSettings, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final normalHeight = tester.getSize(quickSettings).height;
    await toggleEditing(tester);
    final footer = find.byKey(const ValueKey('home_customize_button'));
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.extentAfter, closeTo(0, 0.5));
    final instructions = find.text(tr('长按卡片拖动排序，关闭开关隐藏卡片'));
    expect(
        tester.getTopLeft(instructions).dy,
        greaterThan(tester
            .getBottomLeft(
                find.byKey(const ValueKey('dashboard_quickSettings')))
            .dy));
    expect(tester.getBottomLeft(find.text('Reset layout')).dy,
        lessThan(tester.getTopLeft(footer).dy));
    final card = find.byKey(const ValueKey('dashboard_quickSettings'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(tester.getSize(quickSettings).height, closeTo(normalHeight, 1));
    expect(find.byType(Scrollable), findsOneWidget);
    final height = tester.getSize(card).height;
    expect(height, greaterThan(680));
    final gesture = await tester
        .startGesture(tester.getTopLeft(card) + const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 300));
    final proxy = tester.widget<Transform>(
        find.byKey(const ValueKey('dashboard_drag_feedback')));
    expect(
        height * proxy.transform.entry(0, 0), lessThanOrEqualTo(680 * 0.6 + 1));
    expect(
        tester.getSize(find.byKey(const ValueKey('dashboard_drag_gap'))).height,
        12);
    final offsetBeforeDrag = position.pixels;
    await tester.pump(const Duration(milliseconds: 400));
    expect(position.pixels, offsetBeforeDrag);
    await gesture.moveTo(const Offset(120, 300));
    await tester.pump(const Duration(milliseconds: 100));
    final feedback = find.byKey(const ValueKey('dashboard_drag_feedback'));
    final beforeMove = tester.getTopLeft(feedback);
    await gesture.moveBy(const Offset(20, 35));
    await tester.pump();
    expect(tester.getTopLeft(feedback) - beforeMove, const Offset(20, 35));
    await tester.pump(const Duration(milliseconds: 500));
    expect(position.pixels, offsetBeforeDrag);
    final viewport = tester.getRect(find.byType(Scrollable));
    await gesture.moveTo(Offset(140, viewport.top + 5));
    for (var tick = 0; tick < 20; tick++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, lessThan(offsetBeforeDrag));
    await gesture.moveTo(Offset(140, viewport.center.dy));
    await tester.pump();
    final stoppedOffset = position.pixels;
    await tester.pump(const Duration(milliseconds: 300));
    expect(position.pixels, stoppedOffset);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await toggleEditing(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tall cards reorder at both edges and expand only after release',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpHome(tester);
    await toggleEditing(tester);
    final list =
        tester.widget<DashboardCardList>(find.byType(DashboardCardList));
    final card = find.byKey(const ValueKey('dashboard_quickSettings'));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));

    for (final toTop in [true, false]) {
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      final gesture = await tester
          .startGesture(tester.getTopLeft(card) + const Offset(40, 20));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump(const Duration(milliseconds: 250));
      final viewport = tester.getRect(find.byType(Scrollable));
      await gesture
          .moveTo(Offset(140, toTop ? viewport.top + 1 : viewport.bottom - 1));
      for (var tick = 0; tick < 500; tick++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (toTop
            ? scroll.position.extentBefore < 0.5
            : scroll.position.extentAfter < 0.5) {
          break;
        }
      }
      expect(toTop ? scroll.position.extentBefore : scroll.position.extentAfter,
          lessThan(0.5));
      expect(
          tester
              .getSize(find.byKey(const ValueKey('dashboard_drag_gap')))
              .height,
          12);
      await gesture.up();
      await tester.pump();
      expect(toTop ? list.layout.order.first : list.layout.order.last,
          DashboardCardId.quickSettings);
      final slot =
          find.ancestor(of: card, matching: find.byType(GestureDetector)).first;
      final initialHeight = tester.getSize(slot).height;
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getSize(slot).height, greaterThan(initialHeight));
      await tester.pumpAndSettle();
      expect(tester.getSize(slot).height,
          closeTo(tester.getSize(card).height, 0.5));
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('canceling a drag preserves order and releases the feedback',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHome(tester);
    await toggleEditing(tester);
    await scrollToTop(tester);
    final list =
        tester.widget<DashboardCardList>(find.byType(DashboardCardList));
    final before = List.of(list.layout.order);
    final gesture = await tester.startGesture(
        tester.getTopLeft(find.byKey(const ValueKey('dashboard_status'))) +
            const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.moveTo(const Offset(120, 350));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(list.layout.order, before);
    expect(find.byKey(const ValueKey('dashboard_drag_feedback')), findsNothing);
    expect(find.byKey(const ValueKey('dashboard_drag_gap')), findsNothing);
    expect(tester.takeException(), isNull);
    final interrupted = await tester.startGesture(
        tester.getTopLeft(find.byKey(const ValueKey('dashboard_status'))) +
            const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 650));
    await pumpHome(tester, active: false);
    await interrupted.up();
    await tester.pumpAndSettle();
    expect(list.layout.order, before);
    expect(find.byKey(const ValueKey('dashboard_drag_feedback')), findsNothing);
    expect(tester.takeException(), isNull);
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
