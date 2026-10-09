import 'dart:async';

import '../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_route_observer.dart';
import 'home_page.dart';
import 'proxy_page.dart';
import 'settings_page.dart';
import 'connections_page.dart';
import 'native_connections_page.dart';
import '../services/clash_data_hub.dart';
import '../services/update_service.dart';
import '../services/app_platform.dart';
import '../services/web_panel_service.dart';
import '../theme/app_theme.dart';
import '../widgets/update_dialog.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with RouteAware {
  int _currentIndex = 0;
  bool _showConsoleButton = false;
  String _connectionsTabMode = 'webview';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    if (AppPlatform.supportsUpdateChecks) {
      Future.delayed(const Duration(seconds: 3), _autoCheckUpdate);
    }
  }

  Future<void> _autoCheckUpdate() async {
    if (!mounted || !AppPlatform.supportsUpdateChecks) return;
    final info = await UpdateService.instance.checkForUpdate(silent: true);
    if (info != null && mounted) {
      showDialog(
        context: context,
        builder: (_) => UpdateDialog(info: info, autoTriggered: true),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    shellRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    _loadPrefs();
    // Reconcile Web panel visibility after returning from the pushed console route.
    _syncWebPanelTabState();
  }

  @override
  void dispose() {
    shellRouteObserver.unsubscribe(this);
    super.dispose();
  }

  void _syncWebPanelTabState() {
    WebPanelSync.instance.proxyTabActive = _currentIndex == 1;
    WebPanelSync.instance.connectionsTabActive =
        _currentIndex == 2 && _connectionsTabMode == 'webview';
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        final oldMaxIndex = _maxIndex;
        final wasOnLastTab = _currentIndex == oldMaxIndex;
        _connectionsTabMode =
            prefs.getString('connections_tab_mode') ?? 'webview';
        _showConsoleButton = prefs.getBool('show_console_button') ?? false;
        if (wasOnLastTab) {
          _currentIndex = _maxIndex;
        } else if (_currentIndex > _maxIndex) {
          _currentIndex = _maxIndex;
        }
      });
      _syncWebPanelTabState();
    }
  }

  Future<void> _syncAfterTabChange(int previousIndex, int index) async {
    try {
      if (previousIndex == 1 || index == 2) {
        try {
          await WebPanelSync.instance
              .save()
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          // Continue activating the visible page if the hidden page is stalled.
        }
      }
      if (!mounted || _currentIndex != index) return;
      if (index == 1) {
        await WebPanelSync.instance
            .reload()
            .timeout(const Duration(seconds: 3));
      } else if (index == 2) {
        await WebPanelSync.instance
            .reloadConnections()
            .timeout(const Duration(seconds: 3));
        if (_connectionsTabMode == 'native') {
          await ClashDataHub.instance.refresh(force: true);
        }
      }
    } catch (_) {
      // Panel errors/retry are owned by the page; navigation remains usable.
    }
  }

  List<Widget> get _pages {
    return [
      HomePage(
          showConsoleButton: _showConsoleButton, active: _currentIndex == 0),
      const ProxyPage(asTab: true),
      if (_connectionsTabMode == 'native')
        const NativeConnectionsPage()
      else
        const ConnectionsPage(),
      const SettingsPage(),
    ];
  }

  List<BottomNavigationBarItem> get _navItems => [
        BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded), label: tr('首页')),
        BottomNavigationBarItem(
            icon: Icon(Icons.hub_outlined),
            activeIcon: Icon(Icons.hub_rounded),
            label: tr('代理')),
        BottomNavigationBarItem(
            icon: Icon(Icons.lan_outlined),
            activeIcon: Icon(Icons.lan_rounded),
            label: tr('连接')),
        BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded), label: tr('设置')),
      ];

  int get _maxIndex => 3;

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Theme(
        // Match Android's Material 3 ripple on iOS without changing page themes.
        data: AppPlatform.isIOS
            ? theme.copyWith(splashFactory: InkSparkle.splashFactory)
            : theme,
        child: BottomNavigationBar(
          backgroundColor: palette.surface,
          unselectedItemColor: palette.textSecondary,
          currentIndex: _currentIndex,
          onTap: (index) {
            FocusManager.instance.primaryFocus?.unfocus();
            if (index == _currentIndex) return;
            final previousIndex = _currentIndex;
            setState(() => _currentIndex = index);
            _syncWebPanelTabState();
            // A hidden WKWebView can suspend JavaScript. Never lock navigation
            // while waiting for its preferences or controller requests.
            unawaited(_syncAfterTabChange(previousIndex, index));
          },
          selectedItemColor: accentColor,
          items: _navItems,
        ),
      ),
    );
  }
}
