import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/services/update_service.dart';
import 'package:proxly/widgets/update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
                onPressed: () => showDialog<void>(
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
                      onPressed: () => showDialog<void>(
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
      await tester.tap(find.text('Update now'));
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
