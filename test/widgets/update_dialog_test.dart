import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/services/update_service.dart';
import 'package:proxly/widgets/update_dialog.dart';
import 'package:proxly/widgets/app_popup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Android install permission opens system settings directly',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return call.method == 'requestPermissions' ? <int, int>{24: 0} : 0;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(
            home: Scaffold(
                body: UpdateDialog(info: UpdateInfo(tag: 'v26.9.0'))))));
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(calls, ['checkPermissionStatus', 'requestPermissions']);
    expect(find.text('Open settings'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  for (final automatic in [false, true]) {
    testWidgets('release notes follow app language for automatic=$automatic',
        (tester) async {
      SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
      final controller = AppLocaleController.instance;
      await controller.load();
      const chinese = '## 更新内容\n\n- 优化性能。';
      const english = '## Updates\n\n- Improve performance.';
      const info = UpdateInfo(
          tag: 'v26.9.0',
          body: '$chinese\n\n<details>\n<summary>English</summary>\n\n'
              '$english\n\n</details>');
      await tester.pumpWidget(AppLocaleScope(
          controller: controller,
          child: MaterialApp(
              home: Scaffold(
                  body: UpdateDialog(info: info, autoTriggered: automatic)))));
      expect(
          tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data, chinese);
      await controller.setLanguage(AppLanguage.english);
      await tester.pumpAndSettle();
      expect(
          tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data, english);
      await controller.setLanguage(AppLanguage.simplifiedChinese);
      await tester.pumpAndSettle();
      expect(
          tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data, chinese);
      expect(tester.takeException(), isNull);
    },
        variant: TargetPlatformVariant(
            {TargetPlatform.android, TargetPlatform.iOS}));
  }

  testWidgets(
      'iOS repeated taps start one download and cancellation keeps the owning page',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final service = _IpaUpdateService();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Root')))));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => AppPopup.dialog<void>(
                    context: context,
                    builder: (_) =>
                        UpdateDialog(info: _ipaUpdate, updateService: service)),
                child: const Text('Open'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final press = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Download IPA'))
        .onPressed!;
    press();
    press();
    await tester.pump();
    expect(service.requests, 1);
    await tester.tap(find.text('Cancel download'));
    expect(service.cancelled!.value, isTrue);
    service.result.complete(File('Proxly-iOS-27.4.ipa'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Root'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('long release notes remain scrollable on a narrow screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => AppPopup.dialog<void>(
                            context: context,
                            builder: (_) => UpdateDialog(
                                autoTriggered: true,
                                info: UpdateInfo(
                                    tag: 'v26.7.0',
                                    body: List.filled(
                                            30, '- Changes to the application.')
                                        .join('\n')))),
                        child: const Text('Open')))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Skip this version').hitTestable(), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('automatic update dialog can disable future checks',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'automatic_update_check_enabled': true,
    });
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AppPopup.dialog<void>(
                  context: context,
                  builder: (_) => const UpdateDialog(
                    info: UpdateInfo(
                      tag: 'v26.4',
                      apkUrl: 'https://github.com/CanMoqiu/proxly/test.apk',
                    ),
                    autoTriggered: true,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Disable update checks'), findsOneWidget);
    expect(find.text('Remind me in one week'), findsNothing);

    await tester.tap(find.text('Disable update checks'));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateDialog), findsNothing);
    expect(await UpdateService.instance.isAutomaticCheckEnabled(), isFalse);
    expect(
      find.text(
        'Update checks disabled. You can re-enable them on the About page.',
      ),
      findsOneWidget,
    );
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  for (final succeeds in [true, false]) {
    testWidgets('iOS download shows its progress and handles success=$succeeds',
        (tester) async {
      SharedPreferences.setMockInitialValues({'app_language': 'en'});
      await AppLocaleController.instance.load();
      final service = _IpaUpdateService();
      await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                        body: TextButton(
                      onPressed: () => AppPopup.dialog<void>(
                          context: context,
                          builder: (_) => UpdateDialog(
                                info: _ipaUpdate,
                                updateService: service,
                              )),
                      child: const Text('Open'),
                    )))),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('27.4.0'), findsNothing);
      await tester.tap(find.text('Download IPA'));
      await tester.pump();
      expect(service.requests, 1);
      expect(find.text('40%'), findsOneWidget);
      if (succeeds) {
        service.result.complete(File('Proxly-iOS-27.4.ipa'));
      } else {
        service.result.completeError(Exception('Connection lost'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(UpdateDialog), findsOneWidget);
      if (succeeds) {
        expect(
          find.textContaining('Proxly/Downloads in Files'),
          findsOneWidget,
        );
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(UpdateDialog), findsNothing);
      } else {
        expect(find.textContaining('Connection lost'), findsOneWidget);
        expect(find.text('Download IPA').hitTestable(), findsOneWidget);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}

const _ipaUpdate = UpdateInfo(
  tag: 'v27.4.0',
  ipaUrl: 'https://example.com/Proxly-iOS-27.4.ipa',
  sha256: 'expected-sha256',
);

class _IpaUpdateService extends UpdateService {
  _IpaUpdateService()
      : super.forTesting(temporaryDirectory: () async => Directory.systemTemp);

  final result = Completer<File>();
  ValueNotifier<bool>? cancelled;
  int requests = 0;

  @override
  Future<File> downloadIpa(
    String url,
    String tag,
    String? expectedSha256,
    void Function(double) onProgress,
    ValueNotifier<bool> cancelled,
  ) {
    expect(url, _ipaUpdate.ipaUrl);
    expect(tag, _ipaUpdate.tag);
    expect(expectedSha256, _ipaUpdate.sha256);
    requests++;
    this.cancelled = cancelled;
    onProgress(0.4);
    return result.future;
  }
}
