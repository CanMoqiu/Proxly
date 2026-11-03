import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/widgets/keyboard_focus_reveal.dart';

void main() {
  testWidgets('focused input stays above a newly opened keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => KeyboardFocusReveal(child: child!),
      home: Scaffold(
          body: ListView(children: const [
        SizedBox(height: 540),
        TextField(),
        SizedBox(height: 300),
      ])),
    ));
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'router.local');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(tester.getBottomLeft(find.byType(TextField)).dy,
        lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
