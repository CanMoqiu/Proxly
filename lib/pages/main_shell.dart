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
import '../services/controller_connection_state.dart';
import '../services/router_detection_session.dart';
import '../services/web_panel_service.dart';
import '../widgets/app_bottom_navigation_bar.dart';
import '../widgets/update_dialog.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.detectionSession});
  final RouterDetectionSession? detectionSession;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with RouteAware, WidgetsBindingObserver {
  int _currentIndex = 0;
  final Set<int> _visitedTabs = {0};
  int _tabRevision = 0;
  bool _routeVisible = true;
  bool _showConsoleButton = false;
  String _connectionsTabMode = 'webview';
  Timer? _warmupTimer;
  int? _warmingTab;
  bool _foreground = true;
  bool _wasInBackground = false;
  RouterDetectionSession get _detection =>
      widget.detectionSession ?? RouterDetectionSession.instance;

  bool get _canWarm =>
      mounted &&
      _foreground &&
      _routeVisible &&
      _currentIndex == 0 &&
      ControllerConnectionState.instance.phase ==
          ControllerConnectionPhase.online;

  void _scheduleWarmup() {
    _warmupTimer?.cancel();
    if (!_canWarm || _warmingTab != null) return;
    _warmupTimer = Timer(const Duration(milliseconds: 800), () {
      if (!_canWarm || _warmingTab != null) return;
      final next = !_visitedTabs.contains(1)
          ? 1
          : _connectionsTabMode == 'webview' && !_visitedTabs.contains(2)
              ? 2
              : null;
      if (next == null) return;
      setState(() {
        _warmingTab = next;
        _visitedTabs.add(next);
      });
    });
  }

  void _panelSettled(int index) {
    if (_warmingTab != index) return;
    _warmingTab = null;
    _scheduleWarmup();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      unawaited(_detection.refresh());
    }
    _scheduleWarmup();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ControllerConnectionState.instance.addListener(_scheduleWarmup);
    _loadPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_detection.refresh());
    });
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
    _scheduleWarmup();
  }

  @override
  void didPushNext() {
    setState(() => _routeVisible = false);
    _scheduleWarmup();
  }

  @override
  void dispose() {
    shellRouteObserver.unsubscribe(this);
    _warmupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ControllerConnectionState.instance.removeListener(_scheduleWarmup);
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
      _scheduleWarmup();
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
          showConsoleButton: _showConsoleButton,
          active: _currentIndex == 0,
          detectionSession: _detection),
      if (!_visitedTabs.contains(1))
        const SizedBox.shrink()
      else
        ProxyPage(asTab: true, onSettled: () => _panelSettled(1)),
      if (!_visitedTabs.contains(2))
        const SizedBox.shrink()
      else if (_connectionsTabMode == 'native')
        NativeConnectionsPage(active: _currentIndex == 2 && _routeVisible)
      else
        ConnectionsPage(onSettled: () => _panelSettled(2)),
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
      // The visible page owns keyboard insets; do not consume them twice.
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (final (index, page) in _pages.indexed)
            TickerMode(enabled: index == _currentIndex, child: page),
        ],
      ),
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : AppBottomNavigationBar(
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
                _scheduleWarmup();
                // A hidden WKWebView can suspend JavaScript. Never lock navigation
                // while waiting for its preferences or controller requests.
                unawaited(_syncAfterTabChange(previousIndex, index, revision));
              },
            ),
    );
  }
}
