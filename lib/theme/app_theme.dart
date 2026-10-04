import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color pageBackground;
  final Color surface;
  final Color inputBackground;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color border;
  final Color success;
  final Color warning;
  final Color error;

  const AppPalette({
    required this.pageBackground,
    required this.surface,
    required this.inputBackground,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.border,
    required this.success,
    required this.warning,
    required this.error,
  });

  static const light = AppPalette(
    pageBackground: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    inputBackground: Color(0xFFEEEEEE),
    textPrimary: Color(0xFF1C1B1F),
    textSecondary: Color(0xFF6E6E6E),
    textDisabled: Color(0xFFBDBDBD),
    border: Color(0xFFE0E0E0),
    success: Color(0xFF1D9E75),
    warning: Color(0xFFD88400),
    error: Color(0xFFE24B4A),
  );

  static const dark = AppPalette(
    pageBackground: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    inputBackground: Color(0xFF121212),
    textPrimary: Color(0xFFE1E1E1),
    textSecondary: Color(0xFF9E9E9E),
    textDisabled: Color(0xFF555555),
    border: Color(0xFF2C2C2C),
    success: Color(0xFF4BB890),
    warning: Color(0xFFF6B94B),
    error: Color(0xFFFF6B68),
  );

  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppPalette copyWith({
    Color? pageBackground,
    Color? surface,
    Color? inputBackground,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? border,
    Color? success,
    Color? warning,
    Color? error,
  }) {
    return AppPalette(
      pageBackground: pageBackground ?? this.pageBackground,
      surface: surface ?? this.surface,
      inputBackground: inputBackground ?? this.inputBackground,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      border: border ?? this.border,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

/// Centralizes the native app's semantic colors and component behavior.
abstract final class AppTheme {
  static const Color lightPrimary = Color(0xFF1A73E8);
  static const Color darkPrimary = Color(0xFF438FD1);

  static ThemeData light() => _build(
        brightness: Brightness.light,
        primary: lightPrimary,
        palette: AppPalette.light,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        primary: darkPrimary,
        palette: AppPalette.dark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required AppPalette palette,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      outline: palette.border,
      error: palette.error,
      onPrimary: Colors.white,
    );
    final base = ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
    );
    final roundedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: palette.border),
    );

    return base.copyWith(
      splashColor: primary.withValues(
        alpha: brightness == Brightness.dark ? 0.08 : 0.12,
      ),
      highlightColor: primary.withValues(
        alpha: brightness == Brightness.dark ? 0.045 : 0.08,
      ),
      hoverColor: primary.withValues(
        alpha: brightness == Brightness.dark ? 0.055 : 0.08,
      ),
      focusColor: primary.withValues(
        alpha: brightness == Brightness.dark ? 0.08 : 0.12,
      ),
      scaffoldBackgroundColor: palette.pageBackground,
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: base.textTheme.apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      iconTheme: IconThemeData(color: palette.textSecondary),
      dividerColor: palette.border,
      cardColor: palette.surface,
      canvasColor: palette.surface,
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: palette.textSecondary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.pageBackground,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: palette.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: palette.textPrimary,
        iconColor: palette.textSecondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return primary.withValues(alpha: 0.42);
            }
            return primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onPrimary.withValues(alpha: 0.68);
            }
            return colorScheme.onPrimary;
          }),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          disabledForegroundColor: palette.textDisabled,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? palette.textDisabled
                  : primary),
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? palette.textDisabled
                    : primary,
              )),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final disabled = states.contains(WidgetState.disabled);
          final selected = states.contains(WidgetState.selected);
          if (selected) {
            return disabled
                ? colorScheme.onPrimary.withValues(alpha: 0.55)
                : colorScheme.onPrimary;
          }
          return disabled
              ? palette.textDisabled.withValues(alpha: 0.7)
              : palette.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          final disabled = states.contains(WidgetState.disabled);
          final selected = states.contains(WidgetState.selected);
          if (selected) {
            return primary.withValues(alpha: disabled ? 0.15 : 0.32);
          }
          return palette.inputBackground.withValues(alpha: disabled ? 0.55 : 1);
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          final disabled = states.contains(WidgetState.disabled);
          final selected = states.contains(WidgetState.selected);
          if (selected) {
            return primary.withValues(alpha: disabled ? 0.42 : 1);
          }
          return (disabled ? palette.textDisabled : palette.textSecondary)
              .withValues(alpha: disabled ? 0.55 : 0.75);
        }),
        trackOutlineWidth: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? 1.2 : 0.9),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.inputBackground,
        hintStyle: TextStyle(color: palette.textSecondary),
        labelStyle: TextStyle(color: palette.textSecondary),
        border: roundedBorder,
        enabledBorder: roundedBorder,
        disabledBorder: roundedBorder.copyWith(
          borderSide: BorderSide(color: palette.textDisabled),
        ),
        focusedBorder: roundedBorder.copyWith(
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: roundedBorder.copyWith(
          borderSide: BorderSide(color: palette.error),
        ),
        focusedErrorBorder: roundedBorder.copyWith(
          borderSide: BorderSide(color: palette.error, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surface,
        contentTextStyle: TextStyle(color: palette.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: palette.border),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        indicatorColor: primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? primary
                : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}
