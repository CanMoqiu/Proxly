import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/app_bottom_navigation_bar.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      testWidgets(
          '$platform dark=$dark keeps tap regions aligned during transitions',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        var selected = 0;
        final taps = <int>[];
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                    bottomNavigationBar: AppBottomNavigationBar(
                      currentIndex: selected,
                      onTap: (value) => setState(() {
                        selected = value;
                        taps.add(value);
                      }),
                    ),
                  )),
        ));
        final regions = find.descendant(
            of: find.byType(BottomNavigationBar),
            matching: find.byType(InkResponse));
        expect(regions, findsNWidgets(4));
        for (final index in [1, 2]) {
          expect(
            find.descendant(
                of: regions.at(index), matching: find.byType(SvgPicture)),
            findsOneWidget,
          );
        }
        final initial =
            List.generate(4, (index) => tester.getRect(regions.at(index)));
        for (final rect in initial) {
          expect(rect.width, closeTo(initial.first.width, 0.01));
        }
        final materialTheme = Theme.of(tester.element(regions.first));
        expect(materialTheme.splashFactory, InkSparkle.splashFactory);
        expect(materialTheme.highlightColor, Colors.transparent);
        expect(materialTheme.splashColor, theme.splashColor);
        expect(
            tester
                .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                .selectedItemColor,
            theme.colorScheme.primary);

        // Retap before the previous ink and selection animations have finished.
        for (final index in [1, 3, 0, 2, 2]) {
          await tester.tapAt(initial[index].center);
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump(const Duration(milliseconds: 30));
            for (var item = 0; item < 4; item++) {
              expect(tester.getRect(regions.at(item)), initial[item]);
              final icons = find.descendant(
                  of: regions.at(item),
                  matching: find.byWidgetPredicate(
                      (widget) => widget is Icon || widget is SvgPicture));
              for (final icon in icons.evaluate()) {
                expect(tester.getCenter(find.byWidget(icon.widget)).dx,
                    closeTo(initial[item].center.dx, 0.01));
              }
            }
          }
        }
        expect(taps, [1, 3, 0, 2, 2]);
        expect(selected, 2);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets('the shared bar keeps the iOS home indicator area clear',
      (tester) async {
    const safeArea = 34.0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(bottom: safeArea);
    tester.view.viewPadding = const FakeViewPadding(bottom: safeArea);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          bottomNavigationBar: AppBottomNavigationBar(
            currentIndex: selected,
            onTap: (index) => setState(() => selected = index),
          ),
        ),
      ),
    ));

    final bar = find.byType(BottomNavigationBar);
    expect(bar, findsOneWidget);
    final settings = find.byIcon(Icons.settings_rounded);
    expect(tester.getRect(settings).bottom,
        lessThan(tester.getRect(bar).bottom - safeArea));
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(tester.widget<BottomNavigationBar>(bar).currentIndex, 3);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
