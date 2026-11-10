import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/developer_options_page.dart';
import 'package:proxly/services/web_panel_service.dart';
import 'package:proxly/services/web_panel_update_session.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/controller_connection_state.dart';
import 'package:proxly/services/router_tool.dart';
import 'package:proxly/widgets/app_popup.dart';
import 'package:proxly/widgets/adaptive_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    final session = WebPanelUpdateSession.instance;
    session.availableInfo = null;
    session.phase = WebPanelUpdatePhase.idle;
    session.progress = 0;
    session.message = null;
    session.notifyListeners();
  });

  testWidgets('software picker sits between language and connections options',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'zh_CN',
      'webpanel_last_builtin_version': 'v3.5.1',
    });
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(home: DeveloperOptionsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('高级选项'), findsOneWidget);
    expect(find.text('开发者选项'), findsNothing);
    expect(find.byType(AppLanguagePicker), findsOneWidget);

    final consoleY = tester.getTopLeft(find.text('显示控制台按钮')).dy;
    final languageY = tester.getTopLeft(find.text('应用语言')).dy;
    final connectionsY = tester.getTopLeft(find.text('连接 Tab 内容')).dy;
    final softwareY = tester.getTopLeft(find.text('代理软件')).dy;

    expect(consoleY, lessThan(languageY));
    expect(languageY, lessThan(softwareY));
    expect(softwareY, lessThan(connectionsY));
  });

  testWidgets(
      'software choice saves offline and follows identity notifications',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'clash_host': 'router.local:9090',
      'router_tool': 'openClash',
      'proxy_core': 'mihomo',
    });
    final connection = ControllerConnectionState.instance;
    connection.reset();
    connection.reportOffline(connection.observe());
    await AppLocaleController.instance.load();
    Future<void> show() async {
      await tester.pumpWidget(AppLocaleScope(
          controller: AppLocaleController.instance,
          child: const MaterialApp(home: DeveloperOptionsPage())));
      await tester.pumpAndSettle();
    }

    await show();
    final tile = find.byKey(const ValueKey('advanced_router_tool'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<AppOptionsSheet<RouterTool>>(
                find.byType(AppOptionsSheet<RouterTool>))
            .selectedValue,
        RouterTool.openClash);
    await tester.tap(find.text('Mihomo generic configuration'));
    await tester.pumpAndSettle();
    final store = ConnectionSettingsStore.instance;
    final prefs = await SharedPreferences.getInstance();
    expect(await store.loadRouterTool(), RouterTool.generic);
    expect(prefs.getBool('router_tool_confirmed'), isTrue);
    expect(prefs.getString('proxy_core'), 'mihomo');
    expect(connection.phase, ControllerConnectionPhase.offline);
    expect(find.text('Mihomo generic configuration'), findsOneWidget);
    final row =
        find.ancestor(of: tile, matching: find.byType(AppSettingPickerRow));
    expect(
        tester.getRect(tile).right, closeTo(tester.getRect(row).right, 0.01));
    await tester.pumpWidget(const SizedBox());
    await show();
    expect(find.text('Mihomo generic configuration'), findsOneWidget);
    await store.applyRouterDetection(
        expectedHost: 'router.local:9090',
        expectedRevision: store.revision,
        tool: RouterTool.nikki,
        core: ProxyCore.mihomo);
    await tester.pumpAndSettle();
    expect(find.text('Nikki'), findsOneWidget);
    expect(find.text('Mihomo generic configuration'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    connection.reset();
  });

  testWidgets('phone language description wraps beside the language picker',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: const MaterialApp(home: DeveloperOptionsPage()),
    ));
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('应用语言'));
    final picker = tester.getRect(find.byType(AppLanguagePicker));
    final description =
        tester.getRect(find.text('语言切换会立即应用，并同步内置 Zashboard 面板。'));
    expect(title.right, lessThan(picker.left));
    expect(description.right, lessThan(picker.left));
    expect(description.top, greaterThan(title.bottom));
    expect(description.height, greaterThan(20));
    expect(picker.center.dy, inInclusiveRange(title.top, description.bottom));
    final languageRow = find.ancestor(
        of: find.byType(AppLanguagePicker),
        matching: find.byType(AppSettingPickerRow));
    expect(picker.right, closeTo(tester.getRect(languageRow).right, 0.01));
    final softwarePicker = find.byKey(const ValueKey('advanced_router_tool'));
    final software = tester.getRect(softwarePicker);
    final softwareTitle = tester.getRect(find.text('代理软件'));
    final softwareDescription =
        tester.getRect(find.text('自动识别不准确时，可手动选择当前使用的软件。'));
    expect(softwareTitle.right, lessThan(software.left));
    expect(softwareDescription.right, lessThan(software.left));
    expect(software.center.dy,
        inInclusiveRange(softwareTitle.top, softwareDescription.bottom));
    final softwareRow = find.ancestor(
        of: softwarePicker, matching: find.byType(AppSettingPickerRow));
    expect(software.right, closeTo(tester.getRect(softwareRow).right, 0.01));
    expect(software.right, closeTo(picker.right, 0.01));
    expect(
        find.descendant(
            of: softwarePicker,
            matching: find.byIcon(Icons.play_arrow_rounded)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AppLanguagePicker),
            matching: find.byType(AppSelectionPicker)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('console preference defaults to hidden and persists changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'zh_CN',
      'webpanel_last_builtin_version': 'v3.5.1',
    });
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(home: DeveloperOptionsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(SwitchListTile, '显示控制台按钮');
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    await tester.tap(tile);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('show_console_button'), isTrue);
  });

  testWidgets('detected Zashboard update survives page recreation',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'zh_CN',
      'webpanel_last_builtin_version': 'v3.15.0',
    });
    await AppLocaleController.instance.load();
    final session = WebPanelUpdateSession.instance;
    session.availableInfo = const WebPanelVersionInfo(
      tag: 'v3.16.0',
      downloadUrl:
          'https://github.com/Zephyruso/zashboard/releases/download/v3.16.0/dist.zip',
      sha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );
    session.phase = WebPanelUpdatePhase.available;
    session.message = '发现新版本 v3.16.0';

    Future<void> pumpPage() async {
      await tester.pumpWidget(
        AppLocaleScope(
          controller: AppLocaleController.instance,
          child: const MaterialApp(home: DeveloperOptionsPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpPage();
    expect(find.text('更新'), findsOneWidget);
    expect(find.text('发现新版本 v3.16.0'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpPage();
    expect(find.text('更新'), findsOneWidget);
  });
}
