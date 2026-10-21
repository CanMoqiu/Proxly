import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/widgets/app_popup.dart';

void main() {
  Widget options() => const AppOptionsSheet<int>(
        title: 'Choose an action',
        selectedValue: 1,
        options: [
          AppSheetOption(value: 1, label: 'Current'),
          AppSheetOption(value: 2, label: 'Next'),
          AppSheetOption(value: 3, label: 'Unavailable', enabled: false),
        ],
      );

  testWidgets(
      'duplicate opens return cancellation and selection waits for exit',
      (tester) async {
    late BuildContext owner;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      owner = context;
      return const Scaffold();
    })));
    final first =
        AppPopup.sheet<int>(context: owner, builder: (_) => options());
    expect(await AppPopup.sheet<int>(context: owner, builder: (_) => options()),
        isNull);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Current'))
            .selected,
        isTrue);
    await tester.tap(find.text('Unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(AppOptionsSheet<int>), findsOneWidget);
    bool finished = false;
    first.then((_) => finished = true);
    final choose =
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Next')).onTap!;
    choose();
    choose();
    await tester.pump(const Duration(milliseconds: 30));
    expect(finished, isFalse);
    await tester.pumpAndSettle();
    expect(await first, 2);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(
        find.byType(AppOptionsSheet<int>, skipOffstage: false), findsNothing);

    final confirmation = AppPopup.dialog<bool>(
        context: owner,
        builder: (context) => AppDialog(
                title: const Text('Confirm action'),
                content: const Text('Continue?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Continue')),
                ]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(await confirmation, isTrue);
  });

  for (final dismissal in ['barrier', 'back', 'drag']) {
    testWidgets('$dismissal cancels selection without applying a value',
        (tester) async {
      int? result;
      bool finished = false;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await AppPopup.sheet<int>(
                            context: context, builder: (_) => options());
                        finished = true;
                      },
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      switch (dismissal) {
        case 'barrier':
          await tester.tapAt(const Offset(10, 10));
        case 'back':
          await tester.binding.handlePopRoute();
        case 'drag':
          await tester.fling(
              find.text('Choose an action'), const Offset(0, 500), 1500);
      }
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(result, isNull);
    });
  }

  testWidgets('root security prompt is not blocked by an owning page popup',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext owner;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: Builder(builder: (context) {
          owner = context;
          return const Scaffold();
        })));
    final outer = AppPopup.dialog<void>(
        context: owner,
        builder: (_) => const AppDialog(
            title: Text('Operation'), content: Text('Waiting'), actions: []));
    await tester.pumpAndSettle();
    final security = AppPopup.dialog<bool>(
        context: navigator.currentContext!,
        barrierDismissible: false,
        builder: (context) => AppDialog(
                title: const Text('Identity'),
                content: const Text('Fingerprint'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Trust'))
                ]));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Identity'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await security, isNull);
    expect(find.text('Operation'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await outer;
  });

  testWidgets(
      'long content and three actions fit a small screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => AppPopup.dialog<void>(
                        context: context,
                        builder: (context) => AppDialog(
                                title: const Text('Save changes?'),
                                content: Text(List.filled(
                                        30, 'Unsaved configuration content.')
                                    .join('\n')),
                                actions: [
                                  for (final label in [
                                    'Keep editing',
                                    'Discard changes',
                                    'Save and continue'
                                  ])
                                    TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(label))
                                ])),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Save changes?'), findsNothing);
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
}
