import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/developer_options_page.dart';
import 'package:proxly/services/optional_settings_visibility.dart';
import 'package:proxly/services/web_panel_service.dart';
import 'package:proxly/services/web_panel_update_session.dart';
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

  testWidgets(
      'language precedes connection display and proxy software is absent',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'zh_CN',
      'webpanel_last_builtin_version': 'v3.5.1',
      OptionalSettingsVisibility.preferenceKey: true,
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

    expect(consoleY, lessThan(languageY));
    expect(languageY, lessThan(connectionsY));
    expect(find.text('代理软件'), findsNothing);
  });

  testWidgets('phone language picker aligns beside its title', (tester) async {
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
    expect(title.right, lessThan(picker.left));
    expect(title.center.dy, closeTo(picker.center.dy, 0.01));
    expect(find.text('语言切换会立即应用，并同步内置 Zashboard 面板。'), findsNothing);
    final languageRow = find.ancestor(
        of: find.byType(AppLanguagePicker),
        matching: find.byType(AppSettingPickerRow));
    expect(picker.right, closeTo(tester.getRect(languageRow).right, 0.01));
    expect(
        find.descendant(
            of: find.byType(AppLanguagePicker),
            matching: find.byType(AppSelectionPicker)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the two trailing switches toggle their preferences',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'zh_CN',
      'webpanel_last_builtin_version': 'v3.5.1',
      OptionalSettingsVisibility.preferenceKey: true,
    });
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(home: DeveloperOptionsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    for (final (title, preference) in [
      ('显示主题悬浮球', 'show_floating_ball'),
      ('显示控制台按钮', 'show_console_button'),
    ]) {
      final label = find.text(title);
      final row = find.ancestor(of: label, matching: find.byType(ListTile));
      final control = find.descendant(of: row, matching: find.byType(Switch));
      expect(tester.widget<ListTile>(row).onTap, isNull);
      expect(tester.widget<Switch>(control).value, isFalse);

      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(prefs.getBool(preference), isNull);
      expect(tester.widget<Switch>(control).value, isFalse);

      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(prefs.getBool(preference), isTrue);
      expect(tester.widget<Switch>(control).value, isTrue);
    }
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
    expect(
      find.byWidgetPredicate((widget) =>
          widget is SvgPicture &&
          widget.bytesLoader is SvgAssetLoader &&
          (widget.bytesLoader as SvgAssetLoader).assetName ==
              'assets/icons/panel-update.svg'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpPage();
    expect(find.text('更新'), findsOneWidget);
  });
}
