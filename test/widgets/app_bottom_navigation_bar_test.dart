import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
        final initial =
            List.generate(4, (index) => tester.getRect(regions.at(index)));
        for (final rect in initial) {
          expect(rect.width, closeTo(initial.first.width, 0.01));
        }
        final materialTheme = Theme.of(tester.element(regions.first));
        expect(materialTheme.splashFactory, InkSparkle.splashFactory);
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
                  of: regions.at(item), matching: find.byType(Icon));
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
}
