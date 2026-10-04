import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/about_page.dart';
import 'package:proxly/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Proxly',
      packageName: 'top.canmoqiu.proxly',
      version: '26.3.9',
      buildNumber: '29',
      buildSignature: '',
      installerStore: null,
    );
  });

  tearDown(() {
    UpdateService.instance.availableUpdate.value = null;
  });

  testWidgets('iOS shows update controls and manual installation guidance',
      (tester) async {
    UpdateService.instance.availableUpdate.value = const UpdateInfo(
      tag: 'v26.6',
      apkUrl: 'https://example.invalid/app.apk',
    );
    await _pumpAboutPage(tester, 'zh_CN');
    expect(find.text('前往 GitHub 发布页下载 IPA，自签后手动安装。'), findsOneWidget);
    expect(find.text('检测版本'), findsNothing);
    expect(find.text('更新'), findsOneWidget);
    expect(find.byKey(const ValueKey('about_automatic_update_switch')),
        findsOneWidget);
    expect(find.textContaining('26.3.9'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Chinese about page shows MIT original followed by translation',
      (tester) async {
    await _pumpAboutPage(tester, 'zh_CN');
    expect(find.textContaining('Permission is hereby granted'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('about_mit_license')));
    await tester.pumpAndSettle();

    expect(find.text('MIT License'), findsOneWidget);
    expect(find.text('中文译文'), findsOneWidget);
    expect(find.textContaining('Permission is hereby granted'), findsOneWidget);
    expect(find.textContaining('任何获得本软件及相关文档文件'), findsOneWidget);
    expect(find.textContaining('英文原文具有法律效力'), findsNothing);
    expect(
      tester.getTopLeft(find.textContaining('Permission is hereby granted')).dy,
      lessThan(tester.getTopLeft(find.textContaining('任何获得本软件及相关文档文件')).dy),
    );
  });

  testWidgets('English about page shows only the official MIT text',
      (tester) async {
    await _pumpAboutPage(tester, 'en');
    await tester.tap(find.byKey(const ValueKey('about_mit_license')));
    await tester.pumpAndSettle();

    expect(find.text('MIT License'), findsOneWidget);
    expect(find.textContaining('Permission is hereby granted'), findsOneWidget);
    expect(find.text('中文译文'), findsNothing);
    expect(find.textContaining('任何获得本软件及相关文档文件'), findsNothing);
    expect(find.textContaining('英文原文具有法律效力'), findsNothing);
  });

  testWidgets('available update stays in memory across page recreation',
      (tester) async {
    const update = UpdateInfo(
      tag: 'v26.4',
      apkUrl:
          'https://github.com/CanMoqiu/proxly/releases/download/v26.4/app.apk',
    );
    UpdateService.instance.availableUpdate.value = update;

    await _pumpAboutPage(tester, 'zh_CN');
    expect(find.text('更新'), findsOneWidget);
    expect(find.text('检测版本'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pumpAboutPage(tester, 'zh_CN');
    expect(find.text('更新'), findsOneWidget);
  });

  testWidgets(
      'test version shows three parts without a build counter or copy action',
      (tester) async {
    await _pumpAboutPage(tester, 'en');
    expect(find.text('Version 26.3.9'), findsOneWidget);
    expect(find.textContaining('+29'), findsNothing);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.text('iOS installation and updates'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('formal version hides the zero test part and build counter',
      (tester) async {
    PackageInfo.setMockInitialValues(
        appName: 'Proxly',
        packageName: 'top.canmoqiu.proxly',
        version: '27.3.0',
        buildNumber: '99',
        buildSignature: '');
    await _pumpAboutPage(tester, 'en');
    expect(find.text('Version 27.3'), findsOneWidget);
    expect(find.text('iOS · Release'), findsOneWidget);
    expect(find.textContaining('+99'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('disabled update checks never render as initially enabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'automatic_update_check_enabled': false,
    });
    await AppLocaleController.instance.load();
    tester.view.physicalSize = const Size(500, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(home: AboutPage()),
      ),
    );
    expect(
      find.byKey(const ValueKey('about_automatic_update_loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('about_automatic_update_switch')),
      findsNothing,
    );

    await tester.pumpAndSettle();
    final toggle = tester.widget<Switch>(
      find.byKey(const ValueKey('about_automatic_update_switch')),
    );
    expect(toggle.value, isFalse);
  });

  testWidgets('changing update checks succeeds without a feedback banner',
      (tester) async {
    await _pumpAboutPage(tester, 'zh_CN');

    await tester.tap(
      find.byKey(const ValueKey('about_automatic_update_switch')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('about_automatic_update_switch')),
          )
          .value,
      isFalse,
    );
    expect(
      find.byKey(const ValueKey('app_feedback_banner')),
      findsNothing,
    );
    expect(find.text('更新检测已关闭'), findsNothing);
  });
}

Future<void> _pumpAboutPage(WidgetTester tester, String language) async {
  SharedPreferences.setMockInitialValues({
    'app_language': language,
    'automatic_update_check_enabled': true,
  });
  await AppLocaleController.instance.load();
  tester.view.physicalSize = const Size(500, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    AppLocaleScope(
      controller: AppLocaleController.instance,
      child: const MaterialApp(home: AboutPage()),
    ),
  );
  await tester.pumpAndSettle();
}
