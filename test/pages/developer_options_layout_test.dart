import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/developer_options_page.dart';
import 'package:proxly/services/web_panel_service.dart';
import 'package:proxly/services/web_panel_update_session.dart';
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

  testWidgets('language picker sits between console and connections options',
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

    expect(consoleY, lessThan(languageY));
    expect(languageY, lessThan(connectionsY));
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
