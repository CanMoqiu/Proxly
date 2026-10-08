import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dashboard and file management labels are translated',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    for (final text in [
      'Clash 状态',
      '当前 YAML',
      'Clash 操作',
      '快捷设置',
      '自定义首页',
      '完成',
      '拖动手柄排序，关闭开关隐藏卡片',
      '恢复默认',
      '编辑配置',
      '文件管理',
      '导出当前内容',
      '选择要编辑的文件，不改变当前运行配置。',
      '当前 YAML 配置有未保存修改，继续前要保存吗？',
      '覆盖已有配置？',
      '卡片已隐藏，点击右上角自定义首页以恢复。',
    ]) {
      expect(tr(text), isNot(matches(RegExp(r'[\u4e00-\u9fff]'))),
          reason: text);
    }
  });

  group('system language resolution', () {
    test('maps every Chinese locale to simplified Chinese', () {
      for (final locale in const [
        Locale('zh', 'CN'),
        Locale('zh', 'HK'),
        Locale('zh', 'TW'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ]) {
        expect(
          AppLocaleController.resolveSystemLanguage([locale]),
          AppLanguage.simplifiedChinese,
        );
      }
    });

    test('uses English for English and unsupported locales', () {
      for (final locales in <List<Locale>?>[
        const [Locale('en')],
        const [Locale('ja', 'JP')],
        const [Locale('fr')],
        null,
      ]) {
        expect(
          AppLocaleController.resolveSystemLanguage(locales),
          AppLanguage.english,
        );
      }
    });
  });

  testWidgets('migrates old Traditional Chinese values to simplified Chinese',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_TW'});

    await AppLocaleController.instance.load();

    final prefs = await SharedPreferences.getInstance();
    expect(
      AppLocaleController.instance.language,
      AppLanguage.simplifiedChinese,
    );
    expect(prefs.getString('app_language'), 'zh_CN');
  });

  testWidgets('language picker exposes only simplified Chinese and English',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: AppLanguagePicker())),
        ),
      ),
    );
    expect(find.byType(MenuAnchor), findsOneWidget);
    expect(find.byIcon(Icons.language_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);

    final closedContainer = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AppLanguagePicker),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = closedContainer.decoration as BoxDecoration;
    expect(decoration.border, isA<Border>());
    expect(decoration.borderRadius, BorderRadius.circular(12));

    await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(MenuItemButton), findsNWidgets(2));
    expect(find.text('简体中文'), findsAtLeastNWidgets(1));
    expect(find.text('English'), findsOneWidget);
    expect(find.textContaining('繁體中文'), findsNothing);
    expect(find.text('日本語'), findsNothing);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(AppLocaleController.instance.language, AppLanguage.english);
  });

  testWidgets('compact language picker keeps native dropdown layout tight',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    tester.view.physicalSize = const Size(240, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: AppLanguagePicker(compact: true)),
          ),
        ),
      ),
    );

    expect(find.byType(MenuAnchor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new Clash controls have complete English translations',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();

    expect(tr('Clash 控制中心'), 'Clash Control Center');
    expect(tr('显示控制台按钮'), 'Show Console button');
    expect(tr('清理 DNS 缓存'), 'Clear DNS cache');
    expect(tr('关闭连接'), 'Close connections');
    expect(tr('稍后'), 'Later');
    expect(
      tr('配置已保存，是否立即重启 OpenClash 使修改生效？'),
      'The configuration was saved. Restart OpenClash now to apply the changes?',
    );
    expect(tr('更新检测'), 'Update checks');
    expect(tr('剩余'), 'Remaining');
    expect(tr('总量'), 'Total');
    expect(tr('检测版本'), 'Check version');
    expect(tr('确认 SSH 设备身份'), 'Verify SSH device identity');
    expect(
      tr('配置已导入，但有 2 个页面未能立即刷新'),
      'Settings imported, but 2 pages could not refresh immediately',
    );
  });

  testWidgets('dynamic English translations preserve parameters',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();

    expect(tr('连接成功 · Clash v1.0'), 'Connected · Clash v1.0');
    expect(
      tr('已切换到 config.yaml，OpenClash 正在重启'),
      'Switched to config.yaml; OpenClash is restarting',
    );
  });
}
