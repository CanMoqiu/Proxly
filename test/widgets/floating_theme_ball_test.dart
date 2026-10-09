import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'theme ball gives feedback for theme changes and long-press dragging',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'show_floating_ball': true, 'theme_mode': 'light'});
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const ProxlyApp(showSetupWizard: true));
    await tester.pumpAndSettle();
    final ball = find.byKey(const ValueKey('floating_theme_ball'));
    await tester.tap(ball);
    await tester.pumpAndSettle();
    expect(ProxlyApp.activeThemeMode, ThemeMode.dark);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    final start = tester.getCenter(ball);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    expect(haptics.last, 'HapticFeedbackType.mediumImpact');
    final decoration = tester
        .widget<AnimatedContainer>(
            find.descendant(of: ball, matching: find.byType(AnimatedContainer)))
        .decoration! as BoxDecoration;
    expect(decoration.boxShadow!.single.blurRadius, 16);
    await gesture.moveBy(const Offset(-100, 40));
    await tester.pump();
    expect(tester.getCenter(ball).dx, lessThan(start.dx));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(haptics.length, 2);
    await tester.pumpWidget(const SizedBox());
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
}
