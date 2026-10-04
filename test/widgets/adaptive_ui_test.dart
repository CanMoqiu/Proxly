import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/widgets/adaptive_ui.dart';

Widget _option(Key key, String label) {
  return Container(
    key: key,
    height: 40,
    alignment: Alignment.center,
    child: AdaptiveSingleLineText(label),
  );
}

Widget _testApp(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  testWidgets('option group stacks labels when horizontal space is too small',
      (tester) async {
    const firstKey = Key('first-option');
    const secondKey = Key('second-option');

    await tester.pumpWidget(
      _testApp(
        SizedBox(
          width: 220,
          child: AdaptiveOptionGroup(
            labels: const ['Follow system', 'Zashboard panel'],
            children: [
              _option(firstKey, 'Follow system'),
              _option(secondKey, 'Zashboard panel'),
            ],
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(secondKey)).dy,
        greaterThan(tester.getTopLeft(find.byKey(firstKey)).dy));
  });

  testWidgets('option group remains horizontal when translated labels fit',
      (tester) async {
    const firstKey = Key('first-option');
    const secondKey = Key('second-option');

    await tester.pumpWidget(
      _testApp(
        SizedBox(
          width: 520,
          child: AdaptiveOptionGroup(
            labels: const ['Follow system', 'Zashboard panel'],
            children: [
              _option(firstKey, 'Follow system'),
              _option(secondKey, 'Zashboard panel'),
            ],
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(secondKey)).dy,
        tester.getTopLeft(find.byKey(firstKey)).dy);
  });

  testWidgets('labeled input keeps title and description above the field',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const SizedBox(
          width: 280,
          child: LabeledInputField(
            title: 'Controller address',
            description: 'Enter the address in IP:port format',
            titleColor: Colors.black,
            descriptionColor: Colors.grey,
            child: TextField(
              decoration: InputDecoration(hintText: 'IP:port'),
            ),
          ),
        ),
      ),
    );

    final titleY = tester.getTopLeft(find.text('Controller address')).dy;
    final descriptionY =
        tester.getTopLeft(find.text('Enter the address in IP:port format')).dy;
    final fieldY = tester.getTopLeft(find.byType(TextField)).dy;
    expect(titleY, lessThan(descriptionY));
    expect(descriptionY, lessThan(fieldY));

    expect(find.text('IP:port'), findsOneWidget);
  });

  testWidgets('adaptive labels remain complete single-line text',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const SizedBox(
          width: 90,
          child: AdaptiveSingleLineText('Zashboard panel'),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('Zashboard panel'));
    expect(label.maxLines, 1);
    expect(label.softWrap, isFalse);
    expect(label.overflow, TextOverflow.visible);
  });

  testWidgets('marquee text stays plain when the label fits', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const SizedBox(
          width: 240,
          child: AdaptiveMarqueeText('Provider A'),
        ),
      ),
    );

    expect(find.text('Provider A'), findsOneWidget);
    expect(find.byType(ClipRect), findsNothing);
  });

  testWidgets('marquee text scrolls only after the label overflows',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const TickerMode(
          enabled: false,
          child: SizedBox(
            width: 40,
            child: AdaptiveMarqueeText(
              'Very long subscription provider name',
              gap: 16,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ClipRect), findsOneWidget);
    expect(find.text('Very long subscription provider name'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('marquee keeps the leading text visible during start delay',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        const SizedBox(
          width: 40,
          child: AdaptiveMarqueeText(
            'Very long subscription provider name',
            startDelay: Duration(seconds: 3),
          ),
        ),
      ),
    );
    await tester.pump();

    Finder marqueePosition() => find.descendant(
          of: find.byType(AdaptiveMarqueeText),
          matching: find.byType(Positioned),
        );

    expect(tester.widget<Positioned>(marqueePosition()).left, 0);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(tester.widget<Positioned>(marqueePosition()).left, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<Positioned>(marqueePosition()).left, lessThan(0));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('theme selector matches settings switch behavior',
      (tester) async {
    var selectedMode = ThemeMode.system;

    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 300,
            child: ThemeModeSelector(
              mode: selectedMode,
              isDark: false,
              lightLabel: 'Light',
              darkLabel: 'Dark',
              followSystemLabel: 'Follow system',
              onChanged: (mode) => setState(() => selectedMode = mode),
            ),
          ),
        ),
      ),
    );

    final systemSwitch = find.byKey(const ValueKey('theme_mode_system_switch'));
    expect(tester.widget<Switch>(systemSwitch).value, isTrue);

    await tester.tap(find.byKey(const ValueKey('theme_mode_dark')));
    await tester.pumpAndSettle();
    expect(selectedMode, ThemeMode.system);

    await tester.tap(systemSwitch);
    await tester.pumpAndSettle();
    expect(selectedMode, ThemeMode.light);
    expect(tester.widget<Switch>(systemSwitch).value, isFalse);

    await tester.tap(find.byKey(const ValueKey('theme_mode_dark')));
    await tester.pumpAndSettle();
    expect(selectedMode, ThemeMode.dark);
  });
}
