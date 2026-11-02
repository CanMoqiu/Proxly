import '../widgets/app_popup.dart';
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
import '../services/update_service.dart';
import '../services/app_platform.dart';
import '../services/web_panel_service.dart';
import '../widgets/app_bottom_navigation_bar.dart';
import '../widgets/update_dialog.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with RouteAware {
  int _currentIndex = 0;
  final Set<int> _visitedTabs = {0};
  int _tabRevision = 0;
  bool _routeVisible = true;
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
      AppPopup.dialog(
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
    setState(() => _routeVisible = true);
    _loadPrefs();
    // Reconcile Web panel visibility after returning from the pushed console route.
    _syncWebPanelTabState();
  }

  @override
  void didPushNext() {
    setState(() => _routeVisible = false);
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

  Future<void> _syncAfterTabChange(
      int previousIndex, int index, int revision) async {
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
      // First visits mount the page lazily; wait for its callbacks to register.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _tabRevision != revision || _currentIndex != index) {
        return;
      }
      if (index == 1) {
        await WebPanelSync.instance
            .reload()
            .timeout(const Duration(seconds: 3));
      } else if (index == 2 && _connectionsTabMode == 'webview') {
        await WebPanelSync.instance
            .reloadConnections()
            .timeout(const Duration(seconds: 3));
      }
    } catch (_) {
      // Panel errors/retry are owned by the page; navigation remains usable.
    }
  }

  List<Widget> get _pages {
    return [
      HomePage(
          showConsoleButton: _showConsoleButton, active: _currentIndex == 0),
      if (!_visitedTabs.contains(1))
        const SizedBox.shrink()
      else
        const ProxyPage(asTab: true),
      if (!_visitedTabs.contains(2))
        const SizedBox.shrink()
      else if (_connectionsTabMode == 'native')
        NativeConnectionsPage(active: _currentIndex == 2 && _routeVisible)
      else
        const ConnectionsPage(),
      if (_visitedTabs.contains(3))
        const SettingsPage()
      else
        const SizedBox.shrink(),
    ];
  }

  int get _maxIndex => 3;

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (final (index, page) in _pages.indexed)
            TickerMode(enabled: index == _currentIndex, child: page),
        ],
      ),
      bottomNavigationBar: AppBottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          FocusManager.instance.primaryFocus?.unfocus();
          if (index == _currentIndex) return;
          final previousIndex = _currentIndex;
          final revision = ++_tabRevision;
          setState(() {
            _currentIndex = index;
            _visitedTabs.add(index);
          });
          _syncWebPanelTabState();
          // A hidden WKWebView can suspend JavaScript. Never lock navigation
          // while waiting for its preferences or controller requests.
          unawaited(_syncAfterTabChange(previousIndex, index, revision));
        },
      ),
    );
  }
}
