import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_navigator.dart';
import 'app_route_observer.dart';
import 'l10n/app_locale.dart';
import 'theme/app_theme.dart';
import 'widgets/app_startup.dart';
import 'services/web_panel_service.dart';
import 'pages/main_shell.dart' show MainShell;
import 'pages/setup_wizard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  runApp(const AppStartup());
}

class ProxlyApp extends StatefulWidget {
  final bool showSetupWizard;
  const ProxlyApp({super.key, this.showSetupWizard = false});

  // Keep the theme mode in shared state so child pages can read it without
  // maintaining local copies.
  static ThemeMode activeThemeMode = ThemeMode.system;

  static void toggleThemeOf(BuildContext context) {
    context.findAncestorStateOfType<_ProxlyAppState>()?.toggleTheme();
  }

  static void setBallVisibilityOf(BuildContext context, bool value) {
    context.findAncestorStateOfType<_ProxlyAppState>()?.setBallVisibility(
          value,
        );
  }

  static void setThemeModeOf(BuildContext context, ThemeMode mode) {
    context.findAncestorStateOfType<_ProxlyAppState>()?.setThemeMode(mode);
  }

  static bool resolvedThemeIsDark(BuildContext context) {
    return switch (activeThemeMode) {
      ThemeMode.light => false,
      ThemeMode.dark => true,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
  }

  @override
  State<ProxlyApp> createState() => _ProxlyAppState();
}

class _ProxlyAppState extends State<ProxlyApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;
  bool _showBall = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLocaleController.instance.addListener(_handleLanguageChanged);
    _loadPrefs();
  }

  void _handleLanguageChanged() {
    if (mounted) setState(() {});
    unawaited(WebPanelSync.instance.syncAppearance());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppLocaleController.instance.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeMode != ThemeMode.system) return;
    if (mounted) setState(() {});
    unawaited(WebPanelSync.instance.syncAppearance());
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final modeStr = prefs.getString('theme_mode') ?? 'system';
    final mode = modeStr == 'light'
        ? ThemeMode.light
        : modeStr == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;
    ProxlyApp.activeThemeMode = mode;
    setState(() {
      _showBall = prefs.getBool('show_floating_ball') ?? false;
      _themeMode = mode;
    });
  }

  void toggleTheme() {
    final currentIsDark = _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final next = currentIsDark ? ThemeMode.light : ThemeMode.dark;
    ProxlyApp.activeThemeMode = next;
    setState(() => _themeMode = next);
    unawaited(WebPanelSync.instance.syncAppearance());
  }

  void setThemeMode(ThemeMode mode) {
    ProxlyApp.activeThemeMode = mode;
    setState(() => _themeMode = mode);
    unawaited(WebPanelSync.instance.syncAppearance());
  }

  void setBallVisibility(bool value) => setState(() => _showBall = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Proxly',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [shellRouteObserver],
      locale: AppLocaleController.instance.locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: _themeMode,
      themeAnimationDuration: Duration.zero,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AppLocaleScope(
          controller: AppLocaleController.instance,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
            ),
            child: Stack(
              children: [child!, if (_showBall) const _FloatingThemeBall()],
            ),
          ),
        );
      },
      // Show the setup wizard on first launch when no controller address is configured.
      home:
          widget.showSetupWizard ? const SetupWizardPage() : const MainShell(),
    );
  }
}

// Theme toggle bubble

class _FloatingThemeBall extends StatefulWidget {
  const _FloatingThemeBall();

  @override
  State<_FloatingThemeBall> createState() => _FloatingThemeBallState();
}

class _FloatingThemeBallState extends State<_FloatingThemeBall> {
  Offset? _pos;
  bool _isDragging = false;
  Offset _posAtDragStart = Offset.zero;
  Offset _dragOrigin = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pos == null) {
      final size = MediaQuery.sizeOf(context);
      _pos = Offset(size.width - 64, size.height * 0.38);
    }
  }

  void _snapToEdge(Size size) {
    final p = _pos!;
    setState(() {
      _pos = Offset(
        p.dx + 24 < size.width / 2 ? 8.0 : size.width - 56.0,
        p.dy.clamp(8.0, size.height - 56.0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pos = _pos ?? Offset(size.width - 64, size.height * 0.38);

    return AnimatedPositioned(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onTap: () => ProxlyApp.toggleThemeOf(context),
        onLongPressStart: (d) {
          setState(() {
            _isDragging = true;
            _posAtDragStart = _pos!;
            _dragOrigin = d.globalPosition;
          });
        },
        onLongPressMoveUpdate: (d) {
          final delta = d.globalPosition - _dragOrigin;
          setState(() {
            _pos = Offset(
              (_posAtDragStart.dx + delta.dx).clamp(0, size.width - 48),
              (_posAtDragStart.dy + delta.dy).clamp(0, size.height - 48),
            );
          });
        },
        onLongPressEnd: (_) {
          _snapToEdge(size);
          setState(() => _isDragging = false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: _isDragging ? 1.0 : 0.82),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: _isDragging ? 0.28 : 0.14,
                ),
                blurRadius: _isDragging ? 16 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}
