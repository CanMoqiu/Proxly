import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/home_page.dart';
import 'package:proxly/services/dashboard_layout_store.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/widgets/app_popup.dart';
import 'package:proxly/services/router_quick_settings.dart';
import 'package:proxly/services/router_tool.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/dashboard/dashboard_card_list.dart';
import 'package:proxly/widgets/dashboard/dashboard_reorderable_list.dart';
import 'package:proxly/widgets/dashboard/quick_settings_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(theme: AppTheme.light(), home: child)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'unidentified software is selected with the standard home options sheet and saved',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'clash_host': 'router.local:9090',
      'router_tool': 'generic',
      'router_tool_selection_pending': true
    });
    await pump(tester, const HomePage(autoLoad: false));
    expect(find.byType(AppOptionsSheet<RouterTool>), findsOneWidget);
    expect(find.text('Select proxy software'), findsOneWidget);
    await tester.tap(find.text('Nikki'));
    await tester.pumpAndSettle();
    expect(await ConnectionSettingsStore.instance.loadRouterTool(),
        RouterTool.nikki);
    expect(await ConnectionSettingsStore.instance.pendingRouterToolSelection(),
        isNull);
    expect(find.byType(AppOptionsSheet<RouterTool>), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('hidden home defers the software selection panel until shown',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'clash_host': 'router.local:9090',
      'router_tool': 'generic',
      'router_tool_selection_pending': true
    });
    await pump(tester, const HomePage(autoLoad: false, active: false));
    expect(find.text('Select proxy software'), findsNothing);
    await pump(tester, const HomePage(autoLoad: false, active: true));
    expect(find.byType(AppOptionsSheet<RouterTool>), findsOneWidget);
    await tester.tap(find.text('Clash API'));
    await tester.pumpAndSettle();
    expect(await ConnectionSettingsStore.instance.pendingRouterToolSelection(),
        isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('API-only YAML is absent on home and in customization',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'router_tool': 'generic', 'app_language': 'en'});
    await pump(tester, const HomePage(autoLoad: false));
    final list =
        tester.widget<DashboardCardList>(find.byType(DashboardCardList));
    expect(list.unavailable, contains(DashboardCardId.currentYaml));
    expect(find.byKey(const ValueKey('dashboard_currentYaml')), findsNothing);
    final button = find.byKey(const ValueKey('home_customize_button'));
    await tester.scrollUntilVisible(button, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visible_currentYaml')), findsNothing);
    expect(find.byKey(const ValueKey('dashboard_currentYaml')), findsNothing);
    expect(list.layout.isVisible(DashboardCardId.currentYaml), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'filtered reorder maps to full layout and capability restoration preserves it',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    final layout = DashboardLayoutStore();
    addTearDown(layout.dispose);
    Future<void> show(Set<DashboardCardId> unavailable) => pump(
        tester,
        Scaffold(
            body: DashboardCardList(
                layout: layout,
                editing: true,
                unavailable: unavailable,
                onEditPressed: () {},
                onSave: (future) {},
                cards: {
              for (final id in DashboardCardId.values)
                id: Text('card_${id.name}')
            })));
    await show({DashboardCardId.traffic, DashboardCardId.currentYaml});
    tester
        .widget<DashboardReorderableList>(find.byType(DashboardReorderableList))
        .onReorder(1, 3);
    await tester.pumpAndSettle();
    expect(layout.order, [
      DashboardCardId.status,
      DashboardCardId.traffic,
      DashboardCardId.currentYaml,
      DashboardCardId.operations,
      DashboardCardId.quickSettings,
      DashboardCardId.overview
    ]);
    await show({});
    expect(find.byKey(const ValueKey('visible_currentYaml')), findsOneWidget);
    expect(layout.isVisible(DashboardCardId.currentYaml), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'Nikki omits unsupported sections instead of displaying disabled controls',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    const settings = OpenClashQuickSettings(
        routerTool: RouterTool.nikki,
        baseMode: OpenClashBaseMode.fakeIp,
        runVariant: OpenClashRunVariant.mix,
        proxyMode: OpenClashProxyMode.rule,
        areaBypass: OpenClashAreaBypass.disabled,
        snifferEnabled: false,
        dnsProxyEnabled: false,
        streamUnlockEnabled: false,
        routerSelfProxyEnabled: true,
        streamUnlockSupported: false,
        rawRunMode: '',
        unsupported: {
          OpenClashQuickSettingKey.areaBypass,
          OpenClashQuickSettingKey.streamUnlock
        });
    await pump(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: OpenClashQuickSettingsCard(
          settings: settings,
          busy: false,
          cardBg: Colors.white,
          cardBorder: Colors.grey,
          textColor: Colors.black,
          hintColor: Colors.grey,
          onBaseModeChanged: (value) {},
          onRunVariantChanged: (value) {},
          onProxyModeChanged: (value) {},
          onAreaBypassChanged: (value) {},
          onSnifferChanged: (value) {},
          onDnsProxyChanged: (value) {},
          onStreamUnlockChanged: (value) {},
        ))));
    expect(find.byKey(const ValueKey('quick_setting_stream_unlock')),
        findsNothing);
    expect(find.byKey(const ValueKey('quick_setting_area_mainland')),
        findsNothing);
    expect(find.text('区域绕过'), findsNothing);
    expect(find.text('Area bypass'), findsNothing);
    expect(find.byKey(const ValueKey('quick_setting_sniffer')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
