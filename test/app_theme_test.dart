import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/adaptive_ui.dart';

void _expectPrimaryComponents(ThemeData theme, Color primary) {
  const enabled = <WidgetState>{};

  expect(theme.colorScheme.primary, primary);
  expect(
    theme.filledButtonTheme.style!.backgroundColor!.resolve(enabled),
    primary,
  );
  expect(
    theme.textButtonTheme.style!.foregroundColor!.resolve(enabled),
    primary,
  );
  expect(
    theme.outlinedButtonTheme.style!.foregroundColor!.resolve(enabled),
    primary,
  );
  expect(
    (theme.outlinedButtonTheme.style!.side!.resolve(enabled) as BorderSide)
        .color,
    primary,
  );
  expect(
    theme.switchTheme.thumbColor!.resolve({WidgetState.selected}),
    theme.colorScheme.onPrimary,
  );
  expect(
    theme.switchTheme.trackColor!.resolve({WidgetState.selected}),
    primary.withValues(alpha: 0.32),
  );
  expect(
    theme.switchTheme.trackOutlineColor!.resolve({WidgetState.selected}),
    primary,
  );
  expect(
    theme.switchTheme.trackOutlineWidth!.resolve({WidgetState.selected}),
    1.2,
  );
  expect(
    theme.switchTheme.trackOutlineColor!.resolve(const <WidgetState>{}),
    isNot(equals(Colors.transparent)),
  );
  expect(
    theme.switchTheme.trackOutlineWidth!.resolve(const <WidgetState>{}),
    0.9,
  );
  expect(
    theme.switchTheme.trackOutlineColor!.resolve({WidgetState.disabled}),
    isNot(equals(Colors.transparent)),
  );
  expect(theme.progressIndicatorTheme.color, primary);
  expect(
    theme.navigationBarTheme.indicatorColor,
    primary.withValues(alpha: 0.12),
  );

  final focusedBorder =
      theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
  expect(focusedBorder.borderSide.color, primary);

  final palette = theme.extension<AppPalette>()!;
  expect(theme.scaffoldBackgroundColor, palette.pageBackground);
  expect(theme.cardColor, palette.surface);
  expect(theme.inputDecorationTheme.fillColor, palette.inputBackground);
  expect(theme.dividerColor, palette.border);
}

void main() {
  test('light theme shares one primary color across Material components', () {
    _expectPrimaryComponents(AppTheme.light(), AppTheme.lightPrimary);
  });

  test('dark theme shares one primary color across Material components', () {
    _expectPrimaryComponents(AppTheme.dark(), AppTheme.darkPrimary);
  });

  test('filled actions use the shared app button geometry', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final style = theme.filledButtonTheme.style!;
      final shape = style.shape!.resolve({})! as RoundedRectangleBorder;

      expect(style.backgroundColor!.resolve({}), theme.colorScheme.primary);
      expect(style.elevation!.resolve({}), 0);
      expect(
        style.padding!.resolve({}),
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );
      expect(shape.borderRadius, BorderRadius.circular(12));
      expect(style.textStyle!.resolve({})?.fontSize, 14);
      expect(style.textStyle!.resolve({})?.fontWeight, FontWeight.w500);
    }
  });

  test('native UI no longer contains alternate hard-coded primary blues', () {
    const legacyActionColors = [
      'Color(0xFF1A73E8)',
      'Color(0xFF378ADD)',
      'Color(0xFF4DA3F5)',
    ];
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => !file.path.endsWith(
            'theme${Platform.pathSeparator}app_theme.dart',
          ),
        );

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      for (final color in legacyActionColors) {
        expect(source, isNot(contains(color)), reason: file.path);
      }
    }
  });

  testWidgets('theme selector uses the active color scheme primary', (
    tester,
  ) async {
    Future<void> pump(ThemeData theme, bool isDark) {
      return tester.pumpWidget(
        MaterialApp(
          theme: isDark ? AppTheme.light() : theme,
          darkTheme: isDark ? theme : AppTheme.dark(),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          home: Scaffold(
            body: ThemeModeSelector(
              mode: ThemeMode.light,
              isDark: isDark,
              lightLabel: 'Light',
              darkLabel: 'Dark',
              followSystemLabel: 'Follow system',
              onChanged: (_) {},
            ),
          ),
        ),
      );
    }

    for (final entry in [
      (theme: AppTheme.light(), isDark: false),
      (theme: AppTheme.dark(), isDark: true),
    ]) {
      await pump(entry.theme, entry.isDark);
      await tester.pumpAndSettle();

      final selectedButton = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const ValueKey('theme_mode_light')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final border =
          (selectedButton.decoration! as BoxDecoration).border! as Border;
      expect(border.top.color, entry.theme.colorScheme.primary);
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('theme_mode_system_switch')),
            )
            .activeThumbColor,
        isNull,
      );
    }
  });
}
