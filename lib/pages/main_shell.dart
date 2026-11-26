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
import '../services/connection_settings_store.dart';
import '../services/clash_data_hub.dart';
import '../services/router_detection_session.dart';
import '../services/web_panel_resume_state.dart';
import '../services/web_panel_service.dart';
import '../widgets/app_bottom_navigation_bar.dart';
import '../widgets/update_dialog.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.detectionSession, this.backgroundClock});
  final RouterDetectionSession? detectionSession;
  final DateTime Function()? backgroundClock;

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
  bool _proxySettled = false;
  late final _resumeState = WebPanelResumeState(now: widget.backgroundClock);
  int _deviceViewEpoch = 0;
  RouterDetectionSession get _detection =>
      widget.detectionSession ?? RouterDetectionSession.instance;

  bool get _canWarm =>
      mounted &&
      _resumeState.foreground &&
      _routeVisible &&
      (_currentIndex == 0 || _currentIndex == 1) &&
      ControllerConnectionState.instance.phase ==
          ControllerConnectionPhase.online;

  void _scheduleWarmup() {
    _warmupTimer?.cancel();
    if (!_canWarm) return;
    final next = !_visitedTabs.contains(1)
        ? 1
        : _proxySettled &&
                _connectionsTabMode == 'webview' &&
                !_visitedTabs.contains(2)
            ? 2
            : null;
    if (next == null) return;
    // Defer to the next event so a child load callback can finish building.
    final delay = next == 1 ? const Duration(milliseconds: 800) : Duration.zero;
    _warmupTimer = Timer(delay, () {
      if (!_canWarm || _visitedTabs.contains(next)) return;
      setState(() => _visitedTabs.add(next));
    });
  }

  void _proxyPanelSettled(int epoch) {
    if (!mounted || epoch != _deviceViewEpoch || _proxySettled) return;
    _proxySettled = true;
    _scheduleWarmup();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumeState.didChangeState(state);
    final elapsed = state == AppLifecycleState.resumed
        ? _resumeState.consumeBackgroundDuration()
        : null;
    if (elapsed != null) {
      if (elapsed >= WebPanelResumeState.longBackgroundThreshold) {
        _refreshBackendOnLaunch();
      } else {
        unawaited(_detection.refresh());
      }
    }
    _scheduleWarmup();
  }

  void _refreshBackendOnLaunch() {
    ConnectionSettingsStore.instance.expireTemporaryBackendSelections();
    unawaited(_detection.refresh());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ControllerConnectionState.instance.addListener(_scheduleWarmup);
    ConnectionSettingsStore.instance.addListener(_handleDeviceSettings);
    _loadPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshBackendOnLaunch();
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
    ConnectionSettingsStore.instance.removeListener(_handleDeviceSettings);
    super.dispose();
  }

  void _syncWebPanelTabState() {
    WebPanelSync.instance.proxyTabActive = _currentIndex == 1;
    WebPanelSync.instance.connectionsTabActive =
        _currentIndex == 2 && _connectionsTabMode == 'webview';
  }

  void _handleDeviceSettings() {
    final change = ConnectionSettingsStore.instance.lastChange;
    if (change != ConnectionSettingsChange.device &&
        change != ConnectionSettingsChange.controller) {
      return;
    }
    _warmupTimer?.cancel();
    _tabRevision++;
    ClashDataHub.instance.resetBaseline(clearSnapshot: true);
    setState(() {
      _deviceViewEpoch++;
      _proxySettled = false;
      _visitedTabs
        ..clear()
        ..addAll([0, _currentIndex]);
    });
    _syncWebPanelTabState();
    unawaited(_detection.refresh());
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
    final epoch = _deviceViewEpoch;
    return [
      HomePage(
          key: ValueKey(('home', _deviceViewEpoch)),
          showConsoleButton: _showConsoleButton,
          active: _currentIndex == 0,
          detectionSession: _detection),
      if (!_visitedTabs.contains(1))
        const SizedBox.shrink()
      else
        ProxyPage(
          key: ValueKey(('proxy', _deviceViewEpoch)),
          asTab: true,
          onSettled: () => _proxyPanelSettled(epoch),
        ),
      if (!_visitedTabs.contains(2))
        const SizedBox.shrink()
      else if (_connectionsTabMode == 'native')
        NativeConnectionsPage(
          key: ValueKey(('native-connections', _deviceViewEpoch)),
          active: _currentIndex == 2 && _routeVisible,
        )
      else
        ConnectionsPage(
          key: ValueKey(('connections', _deviceViewEpoch)),
        ),
      if (_visitedTabs.contains(3))
        SettingsPage(active: _currentIndex == 3)
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
