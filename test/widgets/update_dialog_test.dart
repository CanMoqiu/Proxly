import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/services/update_service.dart';
import 'package:proxly/widgets/update_dialog.dart';
import 'package:proxly/widgets/app_popup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'iOS repeated update taps and late browser completion keep the owning page',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    final opened = Completer<bool>();
    int launches = 0;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (_) {
      launches++;
      return opened.future;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
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
                        const UpdateDialog(info: UpdateInfo(tag: 'v26.7.0'))),
                child: const Text('Open'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final press = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Open release page'))
        .onPressed!;
    press();
    press();
    await tester.pump();
    expect(launches, 1);
    await tester.tap(find.text('Cancel'));
    opened.complete(true);
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

  for (final opens in [true, false]) {
    testWidgets(
        'iOS update opens GitHub externally and handles browser success=$opens',
        (tester) async {
      SharedPreferences.setMockInitialValues({'app_language': 'en'});
      await AppLocaleController.instance.load();
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        calls.add(call);
        return opens;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                        body: TextButton(
                      onPressed: () => AppPopup.dialog<void>(
                          context: context,
                          builder: (_) => const UpdateDialog(
                                info: UpdateInfo(tag: 'v27.4.0'),
                              )),
                      child: const Text('Open'),
                    )))),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('27.4.0'), findsNothing);
      await tester.tap(find.text('Open release page'));
      await tester.pumpAndSettle();
      expect(calls.length, 1);
      expect(calls.single.method, 'launch');
      expect(calls.single.arguments['url'],
          'https://github.com/CanMoqiu/proxly/releases/tag/v27.4.0');
      expect(calls.single.arguments['useSafariVC'], isFalse);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(UpdateDialog), opens ? findsNothing : findsOneWidget);
      if (!opens) {
        expect(
            find.text('Could not open the link. Check your browser settings'),
            findsOneWidget);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}
