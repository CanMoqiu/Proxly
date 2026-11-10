import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/home_page.dart';
import 'package:proxly/services/dashboard_layout_store.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/widgets/app_popup.dart';
import 'package:proxly/services/router_quick_settings.dart';
import 'package:proxly/services/router_tool.dart';
import 'package:proxly/services/controller_connection_state.dart';
import 'package:proxly/services/router_detection_session.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/adaptive_ui.dart';
import 'package:proxly/widgets/dashboard/dashboard_card_list.dart';
import 'package:proxly/widgets/dashboard/dashboard_reorderable_list.dart';
import 'package:proxly/widgets/dashboard/quick_settings_card.dart';
import 'package:proxly/widgets/dashboard/dashboard_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => ControllerConnectionState.instance.reset());
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
    final session = _SelectionSession();
    addTearDown(session.dispose);
    ControllerConnectionState.instance
        .reportStatus(ControllerConnectionState.instance.observe(), 200);
    await pump(tester, HomePage(autoLoad: false, detectionSession: session));
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
    final session = _SelectionSession();
    addTearDown(session.dispose);
    ControllerConnectionState.instance
        .reportStatus(ControllerConnectionState.instance.observe(), 200);
    await pump(tester,
        HomePage(autoLoad: false, active: false, detectionSession: session));
    expect(find.text('Select proxy software'), findsNothing);
    await pump(tester,
        HomePage(autoLoad: false, active: true, detectionSession: session));
    expect(find.byType(AppOptionsSheet<RouterTool>), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AppOptionsSheet<RouterTool>),
        matching: find.text('Mihomo generic configuration')));
    await tester.pumpAndSettle();
    expect(await ConnectionSettingsStore.instance.pendingRouterToolSelection(),
        isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed or unverified connections never open software selection',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'clash_host': 'router.local:9090',
      'router_tool': 'generic',
      'router_tool_selection_pending': true,
    });
    final session = _SelectionSession();
    addTearDown(session.dispose);
    final connection = ControllerConnectionState.instance;
    for (final phase in [
      ControllerConnectionPhase.unknown,
      ControllerConnectionPhase.offline,
      ControllerConnectionPhase.unauthorized,
      ControllerConnectionPhase.restarting
    ]) {
      connection.reset();
      connection.report(connection.observe(), phase);
      await pump(tester, HomePage(autoLoad: false, detectionSession: session));
      expect(find.byType(AppOptionsSheet<RouterTool>), findsNothing);
    }
    connection.reset();
    connection.reportStatus(connection.observe(), 200);
    session.eligible = false;
    await pump(tester, HomePage(autoLoad: false, detectionSession: session));
    expect(find.byType(AppOptionsSheet<RouterTool>), findsNothing);
    session.eligible = true;
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(AppOptionsSheet<RouterTool>), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AppOptionsSheet<RouterTool>),
        matching: find.text('Mihomo generic configuration')));
    await tester.pumpAndSettle();
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
      'filtered reorder preserves slots and appends never arranged cards in the UI',
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
      DashboardCardId.operations,
      DashboardCardId.currentYaml,
      DashboardCardId.quickSettings,
      DashboardCardId.overview
    ]);
    await show({});
    expect(find.byKey(const ValueKey('visible_currentYaml')), findsOneWidget);
    expect(layout.isVisible(DashboardCardId.currentYaml), isTrue);
    expect(
        tester
            .widget<DashboardReorderableList>(
                find.byType(DashboardReorderableList))
            .children
            .map((child) => child.key),
        const [
          ValueKey('dashboard_status'),
          ValueKey('dashboard_operations'),
          ValueKey('dashboard_quickSettings'),
          ValueKey('dashboard_overview'),
          ValueKey('dashboard_traffic'),
          ValueKey('dashboard_currentYaml'),
        ]);
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
        unsupported: {OpenClashQuickSettingKey.streamUnlock});
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
    expect(
        find.byKey(const ValueKey('quick_setting_area_group')), findsOneWidget);
    expect(find.text('Area bypass'), findsOneWidget);
    expect(
        find.byKey(
            const ValueKey('quick_setting_area_OpenClashAreaBypass.overseas')),
        findsNothing);
    expect(
        find.byKey(
            const ValueKey('quick_setting_area_OpenClashAreaBypass.mainland')),
        findsOneWidget);
    expect(
        find.byKey(
            const ValueKey('quick_setting_area_OpenClashAreaBypass.disabled')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('quick_setting_sniffer')), findsOneWidget);
    expect(find.text('DNS respect rules'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(4));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('split Nikki bypass has no false selection and accepts Off',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    const settings = OpenClashQuickSettings(
        routerTool: RouterTool.nikki,
        baseMode: OpenClashBaseMode.fakeIp,
        runVariant: OpenClashRunVariant.mix,
        proxyMode: OpenClashProxyMode.rule,
        areaBypass: null,
        snifferEnabled: false,
        dnsProxyEnabled: false,
        streamUnlockEnabled: false,
        routerSelfProxyEnabled: true,
        streamUnlockSupported: false,
        rawRunMode: '',
        unsupported: {
          OpenClashQuickSettingKey.baseMode,
          OpenClashQuickSettingKey.runVariant,
          OpenClashQuickSettingKey.proxyMode,
          OpenClashQuickSettingKey.sniffer,
          OpenClashQuickSettingKey.dnsProxy,
          OpenClashQuickSettingKey.streamUnlock,
        });
    OpenClashAreaBypass? selected;
    await pump(
        tester,
        Scaffold(
            body: OpenClashQuickSettingsCard(
          settings: settings,
          busy: false,
          cardBg: Colors.white,
          cardBorder: Colors.grey,
          textColor: Colors.black,
          hintColor: Colors.grey,
          onBaseModeChanged: (_) {},
          onRunVariantChanged: (_) {},
          onProxyModeChanged: (_) {},
          onAreaBypassChanged: (value) => selected = value,
          onSnifferChanged: (_) {},
          onDnsProxyChanged: (_) {},
          onStreamUnlockChanged: (_) {},
        )));
    final choices = find.descendant(
        of: find.byKey(const ValueKey('quick_setting_area_group')),
        matching: find.byType(AdaptiveSelectionButton));
    expect(
        tester
            .widgetList<AdaptiveSelectionButton>(choices)
            .where((button) => button.selected),
        isEmpty);
    expect(
        find.text(
            'IPv4/IPv6 bypass settings differ. Selecting an option will set both.'),
        findsOneWidget);
    expect(find.byType(Divider), findsNothing);
    await tester.tap(find.text('Off'));
    expect(selected, OpenClashAreaBypass.disabled);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('API-only quick settings have no empty sections or separators',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await pump(
        tester,
        Scaffold(
            body: OpenClashQuickSettingsCard(
          routerTool: RouterTool.generic,
          settings: null,
          busy: false,
          cardBg: Colors.white,
          cardBorder: Colors.grey,
          textColor: Colors.black,
          hintColor: Colors.grey,
          onBaseModeChanged: (_) {},
          onRunVariantChanged: (_) {},
          onProxyModeChanged: (_) {},
          onAreaBypassChanged: (_) {},
          onSnifferChanged: (_) {},
          onDnsProxyChanged: (_) {},
          onStreamUnlockChanged: (_) {},
        )));
    expect(find.text('Proxy mode'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
    expect(find.text('Fake-IP'), findsNothing);
    expect(find.text('TUN'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('every software starts with the shared default dashboard order',
      (tester) async {
    for (final tool in RouterTool.values) {
      SharedPreferences.setMockInitialValues({
        'app_language': 'en',
        'router_tool': tool.name,
      });
      await pump(tester, const HomePage(autoLoad: false));
      final list =
          tester.widget<DashboardCardList>(find.byType(DashboardCardList));
      expect(list.layout.order, DashboardCardId.values);
      expect(list.layout.availableOrder(unavailable: list.unavailable),
          DashboardCardId.values.where((id) => !list.unavailable.contains(id)));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('software identity updates above the core version while inactive',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'clash_host': 'router.local:9090',
      'router_tool': 'openClash',
    });
    await pump(
        tester,
        DashboardStatus(
            active: false,
            builder: (_, cards) => Scaffold(body: cards.status)));
    expect(find.text('OpenClash'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Proxy software')).dy,
        lessThan(tester.getTopLeft(find.text('Core version')).dy));
    final store = ConnectionSettingsStore.instance;
    expect(
        await store.applyRouterDetection(
            expectedHost: 'router.local:9090',
            expectedRevision: store.revision,
            tool: RouterTool.nikki,
            core: ProxyCore.mihomo),
        isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Nikki'), findsOneWidget);
    expect(find.text('OpenClash'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _SelectionSession extends RouterDetectionSession {
  bool eligible = true;
  @override
  bool canSelectFor(String host, int revision) => eligible;
}
