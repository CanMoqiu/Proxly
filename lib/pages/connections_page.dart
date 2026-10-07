import '../l10n/app_locale.dart';
import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show ProxlyApp;
import '../services/clash_host_validator.dart';
import '../services/connection_settings_store.dart';
import '../services/web_panel_service.dart';
import '../services/web_panel_flag_font.dart';
import '../services/app_platform.dart';
import '../services/panel_load_monitor.dart';
import '../services/web_panel_page_probe.dart';
import '../widgets/panel_error_view.dart';
import '../services/zashboard_settings_import_service.dart';
import '../theme/app_theme.dart';

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key});

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage>
    with WidgetsBindingObserver {
  final _panelLoad = PanelLoadMonitor();
  Future<void>? _restarting;
  bool _needsRecovery = false;

  void _handlePanelLoad() {
    if (mounted) setState(() => _webViewReady = _panelLoad.ready);
  }

  Future<void> _recoverPanel() async {
    try {
      await _restartLocalServer();
    } catch (_) {
      // The load monitor presents the failure and a retry button.
    }
  }

  AssetHttpServer? _assetServer;
  FileHttpServer? _fileServer;
  WebPanelControllerBridge? _controllerBridge;
  int _serverGeneration = 0;
  int _serverPort = 0;
  bool _serverStarted = false;
  String _targetUrl = '';
  InAppWebViewController? _webViewController;

  // Plugin callbacks can wrap the same native controller in different Dart
  // objects. Compare their shared platform controller to reject stale views.
  bool _isCurrentController(InAppWebViewController controller) =>
      identical(controller.platform, _webViewController?.platform);
  UserScript? _connectionUserScript;
  UserScript? _restoreUserScript;
  UserScript? _themeUserScript;
  bool _isDark = false;
  String _panelLanguage = '';
  bool _webViewReady = false;
  bool _coreSettingsImportInProgress = false;

  static const _prefLocalStorage = ZashboardSettingsImportService.preferenceKey;
  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

  // Disable Service Worker installation because a hidden 0x0 Virtual Display
  // can otherwise suspend page loading.
  static final UserScript _noSwScript = UserScript(
    source: WebPanelPageProbe.disableServiceWorker,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  static final UserScript _hideUntilReadyScript = UserScript(
    source: r"""
      (function(){try{
        document.documentElement.classList.add('__proxly_connection_preparing');
        if (!document.getElementById('__proxly_connection_preparing_style')) {
          const style = document.createElement('style');
          style.id = '__proxly_connection_preparing_style';
          style.textContent = 'html.__proxly_connection_preparing body{opacity:0!important;}';
          document.documentElement.appendChild(style);
        }
      }catch(e){}})();
    """,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  static final UserScript _authStateCleanupScript = UserScript(
    source: r"""
      (function(){try{
        const managedKeys = new Set([
          'setup/api-list',
          'setup/active-uuid',
          'config/auto-theme',
          'config/default-theme',
          'config/dark-theme',
          'config/language',
          'config/connection-display-style',
          'config/connection-sort-direction',
          'config/connection-sort-type',
          'config/connection-card-lines',
          'config/use-connecticon-card',
          'config/auto-import-settings',
          'config/import-settings-url',
          'config/auto-upgrade',
          'config/auto-upgrade-core',
          'config/check-upgrade-core',
          'config/is-sidebar-collapsed',
          'config/swipe-in-pages',
          'config/swipe-in-tabs',
          'config/two-columns',
          'config/settings-page-two-columns',
          'config/split-overview-page'
        ]);
        function isManagedKey(key) {
          return managedKeys.has(key) ||
            key.startsWith('cache/') ||
            key.startsWith('config/table-') ||
            key.startsWith('config/connection-') ||
            /secret|token|password|authorization/i.test(key);
        }
        managedKeys.forEach(function(key) {
          localStorage.removeItem(key);
        });
        for (let i = localStorage.length - 1; i >= 0; i--) {
          const key = localStorage.key(i) || '';
          if (isManagedKey(key)) {
            localStorage.removeItem(key);
          }
        }
      }catch(e){}})();
    """,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  static UserScript _buildConnectionUserScript({
    required String hostname,
    required String port,
    required String secondaryPath,
  }) {
    return UserScript(
      source: WebPanelAuthScript.build(
        hostname: hostname,
        port: port,
        secondaryPath: secondaryPath,
      ),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );
  }

  Future<void> _restoreConnectionStateInPage() async {
    final bridge = _controllerBridge;
    if (_webViewController == null || bridge == null || _serverPort == 0) {
      return;
    }

    await _webViewController!.evaluateJavascript(
      source: WebPanelAuthScript.build(
        hostname: '127.0.0.1',
        port: _serverPort.toString(),
        secondaryPath: bridge.secondaryPath,
        dispatchEvents: true,
      ),
    );
  }

  /// Lock the embedded Zashboard panel to mobile signals without changing its
  /// own saved display preferences.
  static final UserScript _mobileModeScript = UserScript(
    source: r"""
(function(){
  try {
    Object.defineProperty(navigator, 'platform', {
      get: function() { return 'Linux armv8l'; },
      configurable: true
    });
    Object.defineProperty(navigator, 'maxTouchPoints', {
      get: function() { return 5; },
      configurable: true
    });
  } catch(e) {}
})();
""",
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  static final UserScript _connectionViewScript = UserScript(
    source: r"""
(function(){
  try {
    localStorage.setItem('config/connection-display-style','card');
    localStorage.setItem('config/use-connecticon-card','true');
    localStorage.setItem('config/connection-card-lines','[["host","close"],["sourceIP","connectTime"],["chains","dlSpeed","ulSpeed"],["rule","dl","ul"]]');
    localStorage.setItem('config/connection-sort-type','connectTime');
    localStorage.setItem('config/connection-sort-direction','desc');
    localStorage.setItem('config/table-sorting','[{"id":"connectTime","desc":true}]');
  } catch(e) {}
})();
""",
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  static final UserScript _docklessLayoutScript = UserScript(
    source: WebPanelLayoutScript.buildDockless(connectionsTab: true),
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  static final UserScript _coreSettingsSyncScript = UserScript(
    source: WebPanelCoreSettingsSyncScript.build(),
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  static UserScript _buildThemeUserScript(bool isDark) {
    final language = AppLocaleController.instance.zashboardLanguage;
    return UserScript(
      source: WebPanelAppearanceScript.build(
        isDark: isDark,
        language: language,
      ),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );
  }

  Future<void> _syncAppearanceFromApp({bool rebuild = true}) async {
    if (!mounted) return;
    final currentIsDark = ProxlyApp.resolvedThemeIsDark(context);
    final currentLanguage = AppLocaleController.instance.zashboardLanguage;
    final languageChanged =
        _panelLanguage.isNotEmpty && _panelLanguage != currentLanguage;
    final changed = _isDark != currentIsDark || languageChanged;

    _isDark = currentIsDark;
    _panelLanguage = currentLanguage;
    _themeUserScript = _buildThemeUserScript(_isDark);
    if (rebuild && changed && mounted) setState(() {});

    if (_webViewController == null) return;
    await _reapplyUserScripts();
    await _syncTheme(_isDark);
    if (languageChanged && _webViewReady) {
      if (mounted) setState(() => _webViewReady = false);
      await _webViewController!.reload();
      return;
    }
    await _ensureConnectionsRoute();
    await _applyConnectionViewPrefs(reveal: false);
  }

  @override
  void initState() {
    super.initState();
    _panelLoad.addListener(_handlePanelLoad);
    WidgetsBinding.instance.addObserver(this);
    WebPanelSync.instance.registerConnections(
      reload: _reloadWebView,
      syncAppearance: _syncAppearanceFromApp,
    );
    WebPanelSync.instance.registerWebView(
      this,
      _reloadAfterImportedSettings,
      restartServer: _restartLocalServer,
    );
    ConnectionSettingsStore.instance
        .addListener(_handleConnectionSettingsChanged);
    _startLocalServer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentIsDark = ProxlyApp.resolvedThemeIsDark(context);
    final currentLanguage = AppLocaleController.instance.zashboardLanguage;
    _themeUserScript = _buildThemeUserScript(currentIsDark);
    if (_isDark != currentIsDark || _panelLanguage != currentLanguage) {
      unawaited(_syncAppearanceFromApp(rebuild: false));
    }
  }

  Future<void> _startLocalServer() async {
    _panelLoad.begin();
    try {
      await _startLocalServerImpl();
    } catch (_) {
      if (mounted) _panelLoad.fail('面板启动失败，请重试');
    }
  }

  Future<void> _startLocalServerImpl() async {
    final generation = ++_serverGeneration;
    await _buildRestoreScript();
    if (!mounted || generation != _serverGeneration) return;
    _isDark = ProxlyApp.resolvedThemeIsDark(context);
    _panelLanguage = AppLocaleController.instance.zashboardLanguage;
    _themeUserScript = _buildThemeUserScript(_isDark);

    final settings = await ConnectionSettingsStore.instance.load();
    final endpoint = ClashHostValidator.parseEndpoint(settings.host);
    if (!mounted || generation != _serverGeneration) return;
    if (endpoint == null) {
      _panelLoad.fail('请先在设置页填写 Clash 地址');
      return;
    }
    final bridge = WebPanelControllerBridge(
      hostname: endpoint.hostname,
      port: endpoint.port,
      token: settings.token,
    );
    AssetHttpServer? assetServer;
    FileHttpServer? fileServer;
    var serverPort = 0;

    try {
      final downloadedPath = await WebPanelService.getInstalledPath();
      if (downloadedPath != null) {
        fileServer = FileHttpServer(
          downloadedPath,
          controllerBridge: bridge,
        );
        await fileServer.start();
        serverPort = fileServer.port;
      } else {
        // Use an isolated origin so this WebView cannot mutate ProxyPage state.
        assetServer = AssetHttpServer(
          'assets/web_panel',
          controllerBridge: bridge,
        );
        await assetServer.start();
        serverPort = assetServer.port;
      }
    } catch (e) {
      await assetServer?.close();
      await fileServer?.close();
      if (assetServer == null && fileServer == null) bridge.close();
      rethrow;
    }

    if (!mounted || generation != _serverGeneration || serverPort == 0) {
      await assetServer?.close();
      await fileServer?.close();
      return;
    }

    _assetServer = assetServer;
    _fileServer = fileServer;
    _controllerBridge = bridge;
    _serverPort = serverPort;

    final clashQuery = Uri(
      queryParameters: {
        'protocol': 'http',
        'hostname': '127.0.0.1',
        'port': _serverPort.toString(),
        'secondaryPath': bridge.secondaryPath,
      },
    ).query;
    _connectionUserScript = _buildConnectionUserScript(
      hostname: '127.0.0.1',
      port: _serverPort.toString(),
      secondaryPath: bridge.secondaryPath,
    );

    if (_serverPort == 0 || !mounted) return;
    setState(() {
      _targetUrl = 'http://127.0.0.1:$_serverPort/?$clashQuery#/connections';
      _serverStarted = true;
    });
  }

  bool _isAllowedPanelNavigation(WebUri? url) {
    if (url == null) return false;
    final scheme = url.scheme.toLowerCase();
    if (scheme == 'about' || scheme == 'data' || scheme == 'blob') return true;
    if (scheme != 'http') return false;
    final host = url.host.toLowerCase();
    return (host == '127.0.0.1' || host == 'localhost') &&
        url.port == _serverPort;
  }

  @override
  void dispose() {
    _serverGeneration++;
    _panelLoad.removeListener(_handlePanelLoad);
    _panelLoad.dispose();
    WidgetsBinding.instance.removeObserver(this);
    WebPanelSync.instance.unregisterConnections();
    WebPanelSync.instance.unregisterWebView(this);
    ConnectionSettingsStore.instance
        .removeListener(_handleConnectionSettingsChanged);
    _assetServer?.close();
    _fileServer?.close();
    super.dispose();
  }

  void _handleConnectionSettingsChanged() {
    final change = ConnectionSettingsStore.instance.lastChange;
    if (change == ConnectionSettingsChange.controller ||
        change == ConnectionSettingsChange.reset) {
      unawaited(_recoverPanel());
    }
  }

  Future<void> _restartLocalServer() {
    return _restarting ??=
        _restartAndWait().whenComplete(() => _restarting = null);
  }

  Future<void> _restartAndWait() async {
    _needsRecovery = false;
    _serverGeneration++;
    _webViewController = null;
    await _assetServer?.close();
    await _fileServer?.close();
    _assetServer = null;
    _fileServer = null;
    _controllerBridge = null;
    _serverPort = 0;
    if (mounted) {
      setState(() {
        _serverStarted = false;
        _webViewReady = false;
        _targetUrl = '';
      });
      await _startLocalServer();
      await _panelLoad.waitUntilReady();
    }
  }

  Future<void> _reloadAfterImportedSettings() async {
    if (!mounted || _webViewController == null) return;
    await _buildRestoreScript();
    await _reapplyUserScripts();
    _panelLoad.begin();
    await _webViewController!.reload();
  }

  Future<bool> _consumeCoreSettingsImport() async {
    final controller = _webViewController;
    if (controller == null || _coreSettingsImportInProgress) return false;
    _coreSettingsImportInProgress = true;
    try {
      final value = await controller.evaluateJavascript(
        source: WebPanelCoreSettingsSyncScript.consumePending(),
      );
      if (value == null) return false;
      final raw = value is String ? value : value.toString();
      if (raw.isEmpty || raw == 'null') return false;

      try {
        await ZashboardSettingsImportService.instance.importSnapshot(raw);
      } catch (error) {
        debugPrint('[ConnectionsPage] 核心设置导入失败: $error');
      }
      await WebPanelSync.instance.reloadAllWebViews();
      return true;
    } finally {
      _coreSettingsImportInProgress = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (AppPlatform.isIOS) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        _needsRecovery = true;
      }
      if (state == AppLifecycleState.resumed &&
          _needsRecovery &&
          WebPanelSync.instance.connectionsTabActive) {
        unawaited(_recoverPanel());
      }
      return;
    }
    if (state == AppLifecycleState.resumed &&
        _webViewReady &&
        _webViewController != null &&
        WebPanelSync.instance.connectionsTabActive) {
      _reloadWebView();
    }
  }

  Future<void> _reloadWebView() async {
    if (_needsRecovery || _panelLoad.error != null) {
      await _recoverPanel();
      return;
    }
    if (_webViewController == null || !mounted) return;
    await _buildRestoreScript();
    await _reapplyUserScripts();
    await _restoreLocalStorageInPage();
    await _restoreConnectionStateInPage();
    await _ensureConnectionsRoute();
    await _syncTheme(_isDark);
    await _applyConnectionViewPrefs(reveal: false);
  }

  Future<void> _buildRestoreScript() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_prefLocalStorage);
    if (raw == null || raw.isEmpty) {
      _restoreUserScript = null;
      return;
    }
    try {
      final sanitized =
          await ZashboardSettingsImportService.instance.sanitizeSnapshot(raw);
      if (sanitized == null) {
        _restoreUserScript = null;
        return;
      }
      if (sanitized != raw) {
        await prefs.setString(_prefLocalStorage, sanitized);
        raw = sanitized;
      }
    } catch (_) {
      _restoreUserScript = null;
      return;
    }

    final b64 = base64Encode(utf8.encode(raw));
    final pendingKey =
        jsonEncode(WebPanelCoreSettingsSyncScript.pendingStorageKey);
    _restoreUserScript = UserScript(
      source: """
      (function(){try{
        if (window.__proxlyCoreImportPending ||
            sessionStorage.getItem($pendingKey) !== null) return;
        function base64ToUtf8(base64) {
          const binary = atob(base64);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
          }
          return new TextDecoder('utf-8').decode(bytes);
        }
        const d=JSON.parse(base64ToUtf8('$b64'));
        for(const [k,v] of Object.entries(d)){
          const value = typeof v === 'string' ? v : JSON.stringify(v);
          localStorage.setItem(k,value);
        }
      }catch(e){}})();
      """,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );
  }

  Future<void> _reapplyUserScripts() async {
    if (_webViewController == null) return;
    await _webViewController!.removeAllUserScripts();
    await _webViewController!.addUserScript(userScript: _noSwScript);
    await _webViewController!.addUserScript(
      userScript: _coreSettingsSyncScript,
    );
    await _webViewController!.addUserScript(userScript: _hideUntilReadyScript);
    await _webViewController!.addUserScript(
      userScript: _authStateCleanupScript,
    );
    if (_restoreUserScript != null) {
      await _webViewController!.addUserScript(userScript: _restoreUserScript!);
    }
    if (_connectionUserScript != null) {
      await _webViewController!.addUserScript(
        userScript: _connectionUserScript!,
      );
    }
    await _webViewController!.addUserScript(userScript: _mobileModeScript);
    await _webViewController!.addUserScript(userScript: _connectionViewScript);
    if (_themeUserScript != null) {
      await _webViewController!.addUserScript(userScript: _themeUserScript!);
    }
    if (Platform.isIOS) {
      await _webViewController!.addUserScript(userScript: _flagFontScript);
    }
    await _webViewController!.addUserScript(
      userScript: _docklessLayoutScript,
    );
  }

  UnmodifiableListView<UserScript> get _initialUserScripts {
    final scripts = <UserScript>[
      _noSwScript,
      _coreSettingsSyncScript,
      _hideUntilReadyScript,
      _authStateCleanupScript,
      if (_restoreUserScript != null) _restoreUserScript!,
      if (_connectionUserScript != null) _connectionUserScript!,
      _mobileModeScript,
      _connectionViewScript,
      if (_themeUserScript != null) _themeUserScript!,
      if (Platform.isIOS) _flagFontScript,
      _docklessLayoutScript,
    ];
    return UnmodifiableListView(scripts);
  }

  static final UserScript _flagFontScript = UserScript(
    source: WebPanelFlagFont.buildScript(),
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  Future<void> _syncTheme(bool isDark) async {
    if (_webViewController == null) return;
    final language = AppLocaleController.instance.zashboardLanguage;
    await _webViewController!.evaluateJavascript(
      source: WebPanelAppearanceScript.build(
        isDark: isDark,
        language: language,
        dispatchEvents: true,
      ),
    );
  }

  Future<void> _ensureConnectionsRoute() async {
    await _webViewController?.evaluateJavascript(
      source: r"""
      (function(){try{
        if (window.location.hash !== '#/connections') {
          window.location.hash = '#/connections';
        }
      }catch(e){}})();
    """,
    );
  }

  Future<void> _restoreLocalStorageInPage() async {
    if (_webViewController == null) return;
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_prefLocalStorage);
    String? encodedPrefs;
    try {
      if (raw != null && raw.isNotEmpty) {
        final sanitized =
            await ZashboardSettingsImportService.instance.sanitizeSnapshot(raw);
        if (sanitized != null) {
          raw = sanitized;
          encodedPrefs = base64Encode(utf8.encode(raw));
        }
      }
      final encodedLiteral =
          encodedPrefs == null ? 'null' : jsonEncode(encodedPrefs);
      await _webViewController!.evaluateJavascript(
        source: """
      (function(){try{
        const encodedPrefs = $encodedLiteral;
        const managedKeys = new Set([
          'setup/api-list',
          'setup/active-uuid',
          'config/auto-theme',
          'config/default-theme',
          'config/dark-theme',
          'config/language',
          'config/connection-display-style',
          'config/connection-sort-direction',
          'config/connection-sort-type',
          'config/connection-card-lines',
          'config/use-connecticon-card',
          'config/auto-import-settings',
          'config/import-settings-url',
          'config/auto-upgrade',
          'config/auto-upgrade-core',
          'config/check-upgrade-core',
          'config/is-sidebar-collapsed',
          'config/swipe-in-pages',
          'config/swipe-in-tabs',
          'config/two-columns',
          'config/settings-page-two-columns',
          'config/split-overview-page'
        ]);
        function isManagedKey(key) {
          return managedKeys.has(key) ||
            key.startsWith('cache/') ||
            key.startsWith('config/table-') ||
            key.startsWith('config/connection-') ||
            /secret|token|password|authorization/i.test(key);
        }
        for (let i = localStorage.length - 1; i >= 0; i--) {
          const key = localStorage.key(i) || '';
          if (isManagedKey(key)) localStorage.removeItem(key);
        }
        function base64ToUtf8(base64) {
          const binary = atob(base64);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
          }
          return new TextDecoder('utf-8').decode(bytes);
        }
        if (encodedPrefs) {
          const d=JSON.parse(base64ToUtf8(encodedPrefs));
          for(const [k,v] of Object.entries(d)){
            if (isManagedKey(k)) {
              continue;
            }
            const value = typeof v === 'string' ? v : JSON.stringify(v);
            localStorage.setItem(k,value);
            window.dispatchEvent(new StorageEvent('storage', {
              key: k,
              newValue: value,
              storageArea: window.localStorage
            }));
          }
        }
      }catch(e){}})();
      """,
      );
    } catch (e) {
      debugPrint('[ConnectionsPage] 恢复 localStorage 失败: $e');
    }
  }

  Future<void> _applyConnectionViewPrefs({bool reveal = true}) async {
    final revealLiteral = reveal ? 'true' : 'false';
    await _webViewController?.evaluateJavascript(
      source: """
      (async function() {
        const sorted = {
          'config/connection-display-style': 'card',
          'config/use-connecticon-card': 'true',
          'config/connection-card-lines': '[["host","close"],["sourceIP","connectTime"],["chains","dlSpeed","ulSpeed"],["rule","dl","ul"]]',
          'config/connection-sort-type': 'connectTime',
          'config/connection-sort-direction': 'desc',
          'config/table-sorting': '[{"id":"connectTime","desc":true}]'
        };
        Object.entries(sorted).forEach(function([k, v]) {
          if (localStorage.getItem(k) === v) return;
          localStorage.setItem(k, v);
          window.dispatchEvent(new StorageEvent('storage', {
            key: k,
            newValue: v,
            storageArea: window.localStorage
          }));
        });
        if ($revealLiteral) {
          await new Promise(function(resolve) {
            requestAnimationFrame(function() {
              requestAnimationFrame(resolve);
            });
          });
          document.documentElement.classList.remove('__proxly_connection_preparing');
        }
      })();
    """,
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final bgColor = palette.pageBackground;
    final textColor = palette.textPrimary;
    final dividerColor = palette.border;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          tr('连接'),
          style: TextStyle(
            color: textColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: dividerColor),
        ),
      ),
      body: Stack(
        children: [
          if (_serverStarted)
            InAppWebView(
              key: ValueKey(_serverGeneration),
              initialUrlRequest: URLRequest(url: WebUri(_targetUrl)),
              initialUserScripts: _initialUserScripts,
              initialSettings: InAppWebViewSettings(
                transparentBackground: false,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                userAgent: _mobileUserAgent,
                disableHorizontalScroll: true,
                overScrollMode: OverScrollMode.NEVER,
                useWideViewPort: false,
                loadWithOverviewMode: false,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                useShouldOverrideUrlLoading: true,
                useHybridComposition: false,
                hardwareAcceleration: true,
                supportZoom: false,
                geolocationEnabled: false,
                safeBrowsingEnabled: true,
              ),
              shouldOverrideUrlLoading: (_, action) async {
                return _isAllowedPanelNavigation(action.request.url)
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL;
              },
              onWebViewCreated: (c) async {
                _webViewController = c;
              },
              onJsAlert: (_, __) async =>
                  JsAlertResponse(handledByClient: true),
              onWebContentProcessDidTerminate: (controller) {
                if (!_isCurrentController(controller)) return;
                _needsRecovery = true;
                _panelLoad.fail('面板进程已停止，请重试');
                if (WebPanelSync.instance.connectionsTabActive) {
                  unawaited(_recoverPanel());
                }
              },
              onReceivedError: (controller, request, error) {
                if (_isCurrentController(controller) &&
                    request.isForMainFrame == true) {
                  _panelLoad.fail('面板加载失败 (${error.type})，请重试');
                }
              },
              onReceivedHttpError: (controller, request, response) {
                if (_isCurrentController(controller) &&
                    request.isForMainFrame == true) {
                  _panelLoad.fail('面板加载失败 (HTTP ${response.statusCode})，请重试');
                }
              },
              onLoadStart: (controller, url) {
                if (_isCurrentController(controller)) {
                  _panelLoad.navigationStarted();
                }
              },
              onLoadStop: (controller, url) async {
                if (!_isCurrentController(controller) ||
                    !mounted ||
                    _panelLoad.error != null) {
                  return;
                }
                try {
                  await _ensureConnectionsRoute();
                  await _syncTheme(_isDark);
                  if (await _consumeCoreSettingsImport()) return;
                  await _applyConnectionViewPrefs();
                  await _ensureConnectionsRoute();
                  if (mounted &&
                      _isCurrentController(controller) &&
                      _panelLoad.error == null) {
                    await WebPanelPageProbe.waitUntilReady(
                      controller,
                      _controllerBridge!.secondaryPath,
                    );
                    if (!mounted ||
                        !_isCurrentController(controller) ||
                        _panelLoad.error != null) {
                      return;
                    }
                    _panelLoad.succeed();
                  }
                } catch (error) {
                  if (mounted && _isCurrentController(controller)) {
                    _panelLoad.fail(error is StateError
                        ? error.message.toString()
                        : '面板初始化失败，请重试');
                  }
                }
              },
            ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _webViewReady,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                child: _webViewReady
                    ? const SizedBox.shrink(
                        key: ValueKey('connections_panel_ready'))
                    : _panelLoad.error != null
                        ? PanelErrorView(
                            message: _panelLoad.error!,
                            onRetry: () => unawaited(_recoverPanel()))
                        : _LoadingOverlay(isDark: _isDark, bgColor: bgColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Loading overlay

class _LoadingOverlay extends StatefulWidget {
  final bool isDark;
  final Color bgColor;
  const _LoadingOverlay({required this.isDark, required this.bgColor});

  @override
  State<_LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<_LoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final hintColor = AppPalette.of(context).textSecondary;
    return Container(
      color: widget.bgColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _spin,
              child: SizedBox(
                width: 40,
                height: 40,
                child: CustomPaint(
                  painter: _ArcPainter(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              tr('正在加载控制台'),
              style: TextStyle(
                fontSize: 13,
                color: hintColor,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color;
  const _ArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      Rect.fromLTWH(0, 0, size.width, size.height),
      -1.5707963,
      4.712389,
      false,
      Paint()
        ..color = color
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}
