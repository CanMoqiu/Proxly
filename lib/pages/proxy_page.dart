import '../l10n/app_locale.dart';
import '../widgets/app_feedback.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show ProxlyApp;
import '../services/clash_host_validator.dart';
import '../services/connection_settings_store.dart';
import '../services/web_panel_service.dart';
import '../services/web_panel_scroll.dart';
import '../services/web_panel_flag_font.dart';
import '../services/app_platform.dart';
import '../services/panel_load_monitor.dart';
import '../services/web_panel_page_probe.dart';
import '../widgets/panel_error_view.dart';
import '../services/web_panel_update_session.dart';
import '../services/zashboard_config_validator.dart';
import '../services/zashboard_settings_import_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';

class ProxyPage extends StatefulWidget {
  final bool asTab;
  const ProxyPage({super.key, this.asTab = false});

  @override
  State<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends State<ProxyPage> with WidgetsBindingObserver {
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
  String _clashQuery = '';
  InAppWebViewController? _webViewController;

  // Plugin callbacks can wrap the same native controller in different Dart
  // objects. Compare their shared platform controller to reject stale views.
  bool _isCurrentController(InAppWebViewController controller) =>
      identical(controller.platform, _webViewController?.platform);
  bool _isDark = false;
  String _panelLanguage = '';
  bool _webViewReady = false;
  bool _coreSettingsImportInProgress = false;

  // 代理页内视图切换：proxies ↔ rules
  bool _showingRules = false;

  bool _updating = false;
  double _updateProgress = 0;
  String _updateMessage = '';
  bool _updateFailed = false;

  static const _prefLocalStorage = ZashboardSettingsImportService.preferenceKey;

  // 在 Vue 初始化前注入 localStorage 的 UserScript
  UserScript? _restoreUserScript;
  UserScript? _connectionUserScript;
  UserScript? _themeUserScript;

  @override
  void initState() {
    super.initState();
    _panelLoad.addListener(_handlePanelLoad);
    WidgetsBinding.instance.addObserver(this);
    if (widget.asTab) {
      WebPanelSync.instance.register(
        save: _saveLocalStorage,
        reload: _reloadFromPrefs,
        syncAppearance: _syncAppearanceFromApp,
      );
    }
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
    final themeChanged = _isDark != currentIsDark;
    final currentLanguage = AppLocaleController.instance.zashboardLanguage;
    final languageChanged = _panelLanguage != currentLanguage;
    _themeUserScript = _buildThemeUserScript(currentIsDark);
    if (themeChanged || languageChanged) {
      unawaited(_syncAppearanceFromApp(rebuild: false));
    }
  }

  /// 在 AT_DOCUMENT_START 屏蔽 navigator.serviceWorker，
  /// 防止 Service Worker 在隐藏的 WebView（Virtual Display 0×0）中安装时挂起页面加载。
  static final UserScript _noSwScript = UserScript(
    source: WebPanelPageProbe.disableServiceWorker,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  static final UserScript _coreSettingsSyncScript = UserScript(
    source: WebPanelCoreSettingsSyncScript.build(),
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

  static final UserScript _docklessLayoutScript = UserScript(
    source: WebPanelLayoutScript.buildDockless(proxyTab: true),
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  static final UserScript _flagFontScript = UserScript(
    source: WebPanelFlagFont.buildScript(),
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
    }
  }

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

  /// 移除所有 UserScript 后重新注入：SW 屏蔽脚本 + localStorage 恢复脚本。
  Future<void> _reapplyUserScripts() async {
    if (_webViewController == null) return;
    await _webViewController!.removeAllUserScripts();
    await _webViewController!.addUserScript(userScript: _noSwScript);
    await _webViewController!.addUserScript(
      userScript: _coreSettingsSyncScript,
    );
    await _webViewController!.addUserScript(
      userScript: _authStateCleanupScript,
    );
    if (_restoreUserScript != null) {
      await _webViewController!.addUserScript(userScript: _restoreUserScript!);
    }
    await _webViewController!.addUserScript(userScript: _nativeScrollScript);
    if (_connectionUserScript != null) {
      await _webViewController!.addUserScript(
        userScript: _connectionUserScript!,
      );
    }
    if (_themeUserScript != null) {
      await _webViewController!.addUserScript(userScript: _themeUserScript!);
    }
    if (Platform.isIOS) {
      await _webViewController!.addUserScript(userScript: _flagFontScript);
    }
    if (widget.asTab) {
      await _webViewController!.addUserScript(
        userScript: _docklessLayoutScript,
      );
    }
  }

  UnmodifiableListView<UserScript> get _initialUserScripts {
    final scripts = <UserScript>[
      _noSwScript,
      _coreSettingsSyncScript,
      _authStateCleanupScript,
      if (_restoreUserScript != null) _restoreUserScript!,
      _nativeScrollScript,
      if (_connectionUserScript != null) _connectionUserScript!,
      if (_themeUserScript != null) _themeUserScript!,
      if (Platform.isIOS) _flagFontScript,
      if (widget.asTab) _docklessLayoutScript,
    ];
    return UnmodifiableListView(scripts);
  }

  static final UserScript _nativeScrollScript = UserScript(
    source: WebPanelScroll.buildScript(),
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  /// 从 SharedPreferences 读取已保存的 localStorage，
  /// 构建一个在 Vue 初始化之前（AT_DOCUMENT_START）注入数据的 UserScript。
  /// 使用 base64 编码规避 JSON 中特殊字符对 JS 字符串的干扰。
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
    // 先构建恢复脚本，确保 WebView 创建时可立即注入
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

    _clashQuery = Uri(
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

    if (mounted) {
      setState(() {
        _targetUrl = 'http://127.0.0.1:$_serverPort/?$_clashQuery#/proxies';
        _serverStarted = true;
      });
    }
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
    if (widget.asTab) WebPanelSync.instance.unregister();
    WebPanelSync.instance.unregisterWebView(this);
    ConnectionSettingsStore.instance
        .removeListener(_handleConnectionSettingsChanged);
    _saveLocalStorage(); // 关闭页面时保存
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
    await _saveLocalStorage()
        .timeout(const Duration(seconds: 2), onTimeout: () {});
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

      ZashboardSettingsImportResult? imported;
      try {
        imported =
            await ZashboardSettingsImportService.instance.importSnapshot(raw);
      } catch (error) {
        debugPrint('[ProxyPage] 核心设置导入失败: $error');
      }

      if (mounted && imported != null && imported.acceptedCount > 0) {
        _showImportSnack(
          '已从核心导入 ${imported.acceptedCount} 项配置，跳过 ${imported.skippedCount} 项冲突数据',
          success: true,
        );
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
        unawaited(_saveLocalStorage());
      }
      if (state == AppLifecycleState.resumed &&
          _needsRecovery &&
          (!widget.asTab || WebPanelSync.instance.proxyTabActive)) {
        unawaited(_recoverPanel());
      }
      return;
    }
    if (state == AppLifecycleState.resumed &&
        _webViewReady &&
        _webViewController != null) {
      // Bug 2：asTab 模式下只有用户正在看代理标签时才重载，
      // 停留在其他标签时前台化不应触发 WebView 重载，避免产生无效 API 请求消耗订阅流量。
      if (!widget.asTab || WebPanelSync.instance.proxyTabActive) {
        setState(() => _webViewReady = false);
        _webViewController!.reload();
      }
    }
  }

  /// 把当前 WebView 的 localStorage 全部导出并存入 SharedPreferences
  Future<void> _saveLocalStorage() async {
    if (_webViewController == null) return;
    try {
      final result = await _webViewController!.evaluateJavascript(
        source: r"""
        (function() {
          const obj = {};
          for (let i = 0; i < localStorage.length; i++) {
            const k = localStorage.key(i);
            obj[k] = localStorage.getItem(k);
          }
          return JSON.stringify(obj);
        })()
      """,
      );
      if (result == null) return;
      // JS 返回值已是 Dart 原生字符串类型，直接转换
      final raw = result is String ? result : result.toString();
      if (raw.isEmpty || raw == 'null') return;
      final sanitized =
          await ZashboardSettingsImportService.instance.sanitizeSnapshot(raw);
      if (sanitized == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLocalStorage, sanitized);
    } catch (e) {
      debugPrint('[ProxyPage] 保存 localStorage 失败: $e');
    }
  }

  /// 控制台关闭后，把最新的 SharedPreferences 数据注入到代理页已有的 WebView，
  /// 无需整页重载，用户不会看到加载动画。
  Future<void> _reloadFromPrefs() async {
    if (_needsRecovery || _panelLoad.error != null) {
      await _recoverPanel();
      return;
    }
    if (_webViewController == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefLocalStorage);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final b64 = base64Encode(utf8.encode(raw));
      await _webViewController!.evaluateJavascript(
        source: """
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
        const d=JSON.parse(base64ToUtf8('$b64'));
        for(const [k,v] of Object.entries(d)){
          const value = typeof v === 'string' ? v : JSON.stringify(v);
          localStorage.setItem(k,value);
          window.dispatchEvent(new StorageEvent('storage', {
            key: k,
            newValue: value,
            storageArea: window.localStorage
          }));
        }
      }catch(e){}})();
      """,
      );
      // 同步更新 UserScript，下次重载时依然生效
      await _restoreConnectionStateInPage();
      await _buildRestoreScript();
      await _reapplyUserScripts();
      await _syncTheme(_isDark);
    } catch (e) {
      debugPrint('[ProxyPage] _reloadFromPrefs 失败: $e');
    }
  }

  Future<void> _syncTheme(bool isDark) async {
    if (_webViewController == null) return;
    await _webViewController!.evaluateJavascript(
      source: WebPanelScroll.buildScript(),
    );
    final language = AppLocaleController.instance.zashboardLanguage;
    await _webViewController!.evaluateJavascript(
      source: WebPanelAppearanceScript.build(
        isDark: isDark,
        language: language,
        dispatchEvents: true,
      ),
    );
  }

  /// 在代理页内切换 proxies / rules 视图（SPA 哈希路由，不触发页面重载）
  void _toggleView() {
    setState(() => _showingRules = !_showingRules);
    final hash = _showingRules ? '#/rules' : '#/proxies';
    _webViewController?.evaluateJavascript(
      source: "window.location.hash = '$hash';",
    );
  }

  /// 注入 JS，拦截 POST /upgrade/ui 并转给 Flutter 处理
  void _injectInterceptor() {
    _webViewController?.evaluateJavascript(
      source: r"""
      (function() {
        if (window.__proxlyIntercepted) return;
        window.__proxlyIntercepted = true;
        const _orig = window.fetch;
        window.fetch = function(input, init) {
          const url = (typeof input === 'string' ? input : (input && input.url)) || '';
          const method = ((init && init.method) || 'GET').toUpperCase();
          if (method === 'POST' && url.includes('/upgrade/ui')) {
            return window.flutter_inappwebview.callHandler('nativeUpdatePanel')
              .then(function(result) {
                const status = result && result.ok === false ? 409 : 200;
                return new Response(JSON.stringify(result || {}), { status: status,
                  headers: { 'Content-Type': 'application/json' } });
              })
              .catch(function(error) {
                return new Response(JSON.stringify({ ok: false, error: String(error) }), {
                  status: 500,
                  headers: { 'Content-Type': 'application/json' }
                });
              });
          }
          return _orig.apply(this, arguments);
        };
      })();
    """,
    );
  }

  /// 从本地 JSON 文件导入 Zashboard 配置。
  /// 只合并非冲突偏好，Proxly 管理的后端、主题和连接页布局保持不变。
  Future<void> _importZashboardConfig() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return;

    String raw;
    Map<dynamic, dynamic> decoded;
    try {
      final bytes = await _readBoundedConfigFile(result.files.first);
      raw = const Utf8Codec().decode(bytes);
      final value = jsonDecode(raw);
      if (value is! Map) {
        _showImportSnack('格式错误：不是有效的配置文件', success: false);
        return;
      }
      decoded = value;
      ZashboardConfigValidator.validateStructure(decoded);
    } on FormatException catch (error) {
      _showImportSnack(error.message, success: false);
      return;
    } catch (_) {
      _showImportSnack('解析失败：文件内容不是合法 JSON', success: false);
      return;
    }

    if (_webViewController == null) {
      _showImportSnack('面板尚未加载，请稍后再试', success: false);
      return;
    }

    // 1. 只合并不会和 Proxly 管理项冲突的 Zashboard 偏好。
    final sanitized =
        await ZashboardSettingsImportService.instance.importSnapshot(raw);
    if (sanitized == null) {
      _showImportSnack('格式错误：不是有效的配置文件', success: false);
      return;
    }
    if (sanitized.acceptedCount == 0) {
      _showImportSnack('没有可导入的非冲突配置', success: false);
      return;
    }
    // 2. 重建 UserScript，确保刷新后在 Vue 初始化前恢复导入的配置。
    await _buildRestoreScript();
    await _reapplyUserScripts();

    if (!mounted) return;
    _showImportSnack(
      '已导入 ${sanitized.acceptedCount} 项配置，跳过 ${sanitized.skippedCount} 项冲突数据',
      success: true,
    );

    // 3. 广播刷新全部存活的代理、连接和独立控制台 WebView。
    final reloadResult = await WebPanelSync.instance.reloadAllWebViews();
    if (mounted && !reloadResult.succeeded) {
      _showImportSnack(
        '配置已导入，但有 ${reloadResult.failed} 个页面未能立即刷新',
        success: false,
      );
    }
  }

  Future<Uint8List> _readBoundedConfigFile(PlatformFile file) async {
    Stream<List<int>>? stream = file.readStream;
    if (stream == null && file.path != null) {
      stream = File(file.path!).openRead();
    }
    if (stream == null && file.bytes != null) {
      stream = Stream.value(file.bytes!);
    }
    if (stream == null) {
      throw const FormatException('读取文件失败');
    }
    return ZashboardConfigValidator.readBounded(
      stream,
      reportedSize: file.size,
    );
  }

  void _showImportSnack(String msg, {required bool success}) {
    if (!mounted) return;
    AppFeedback.showSnackBar(
      context,
      tr(msg),
      tone: success ? AppFeedbackTone.success : AppFeedbackTone.error,
    );
  }

  Future<bool> _confirmNativeUpdate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('确认更新 Zashboard？')),
        content: Text(
          tr(
            AppPlatform.isIOS
                ? 'Zashboard 是内置 Web 控制面板。新版可能影响页面适配，更新后将重新加载面板。'
                : 'Zashboard 是内置 Web 控制面板。新版可能调整页面结构，影响代理页和连接页的适配效果。更新完成后 Proxly 会自动重启以加载新面板。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: AdaptiveSingleLineText(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: AdaptiveSingleLineText(tr('继续更新')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<Map<String, Object?>> _performNativeUpdate() async {
    if (_updating) return {'ok': false, 'reason': 'busy'};
    final session = WebPanelUpdateSession.instance;
    setState(() {
      _updating = true;
      _updateProgress = 0;
      _updateMessage = '正在检查最新版本…';
      _updateFailed = false;
    });

    try {
      final info = session.availableInfo ?? await session.check();
      if (!mounted) return {'ok': false, 'cancelled': true};
      if (info == null) {
        final currentVersion = await WebPanelService.getActiveVersion();
        setState(() {
          _updateMessage = '当前已是最新版本 $currentVersion';
        });
        _showImportSnack('当前已是最新版本 $currentVersion', success: true);
        return {'ok': true, 'upToDate': true, 'version': currentVersion};
      }
      setState(() => _updating = false);
      final confirmed =
          session.activationPending || await _confirmNativeUpdate();
      if (!confirmed || !mounted) return {'ok': false, 'cancelled': true};
      await _saveLocalStorage();

      void syncProgress() {
        if (!mounted) return;
        setState(() {
          _updating = session.busy;
          _updateProgress = session.progress;
          _updateMessage = session.message ?? '';
          _updateFailed = session.phase == WebPanelUpdatePhase.failed;
        });
      }

      session.addListener(syncProgress);
      try {
        await session.install();
      } finally {
        session.removeListener(syncProgress);
      }
      return {
        'ok': true,
        'restarting': AppPlatform.supportsApkUpdates,
        'version': info.tag
      };
    } catch (e) {
      if (!mounted) return {'ok': false, 'error': e.toString()};
      setState(() {
        _updating = false;
        _updateFailed = true;
        _updateMessage = '更新失败：$e';
      });
      // 4 秒后自动清除错误提示
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _updateFailed = false);
      });
      return {'ok': false, 'error': e.toString()};
    } finally {
      if (mounted && !WebPanelUpdateSession.instance.busy) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final bgColor = palette.pageBackground;
    final textColor = palette.textPrimary;
    final dividerColor = palette.border;

    final scaffold = Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.asTab
            ? IconButton(
                tooltip: tr(_showingRules ? '代理' : '规则'),
                onPressed: _toggleView,
                icon: SvgPicture.asset(
                  _showingRules
                      ? 'assets/icons/globe-alt.svg'
                      : 'assets/icons/swatch.svg',
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
                ),
              )
            : IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textColor),
                onPressed: () async {
                  await _saveLocalStorage();
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
              ),
        title: Text(
          tr(widget.asTab ? (_showingRules ? '规则' : '代理') : '控制台'),
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          // 导入 Zashboard 配置文件
          IconButton(
            icon: Icon(
              Icons.file_download_outlined,
              color: textColor,
              size: 22,
            ),
            tooltip: tr('导入配置'),
            onPressed: _importZashboardConfig,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: dividerColor),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: !widget.asTab,
        child: Stack(
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
                  disableHorizontalScroll: true,
                  overScrollMode: OverScrollMode.NEVER,
                  disallowOverScroll: true,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                  useShouldOverrideUrlLoading: true,
                  // 切换为 Virtual Display 渲染，减少 GPU 合成层，解决掉帧问题
                  useHybridComposition: false,
                  // 确保硬件加速渲染
                  hardwareAcceleration: true,
                  // 关闭不需要的功能，降低后台开销
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
                  c.addJavaScriptHandler(
                    handlerName: 'nativeUpdatePanel',
                    callback: (_) => _performNativeUpdate(),
                  );
                },
                onWebContentProcessDidTerminate: (controller) {
                  if (!_isCurrentController(controller)) return;
                  _needsRecovery = true;
                  _panelLoad.fail('面板进程已停止，请重试');
                  if ((!widget.asTab || WebPanelSync.instance.proxyTabActive)) {
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
                    await _syncTheme(_isDark);
                    _injectInterceptor();
                    if (await _consumeCoreSettingsImport()) return;
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
                onJsAlert: (_, __) async =>
                    JsAlertResponse(handledByClient: true),
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
                          key: ValueKey('proxy_panel_ready'))
                      : _panelLoad.error != null
                          ? PanelErrorView(
                              message: _panelLoad.error!,
                              onRetry: () => unawaited(_recoverPanel()))
                          : _LoadingOverlay(isDark: _isDark, bgColor: bgColor),
                ),
              ),
            ),

            // 下载更新进度条
            if (_updating)
              Positioned(
                bottom: 24,
                left: 20,
                right: 20,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(14),
                  color: palette.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(_updateMessage),
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _updateProgress,
                            backgroundColor: palette.inputBackground,
                            valueColor: AlwaysStoppedAnimation(
                              Theme.of(context).colorScheme.primary,
                            ),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 更新失败提示条
            if (_updateFailed)
              Positioned(
                bottom: 24,
                left: 20,
                right: 20,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  color: palette.error,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      tr(_updateMessage),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // 控制台（asTab:false）用 PopScope 拦截系统返回，确保 localStorage
    // 保存完成后再 pop，避免 HomePage 调用 reload() 时读到旧数据
    if (!widget.asTab) {
      return PopScope(
        canPop: AppPlatform.isIOS,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) return;
          _saveLocalStorage().then((_) {
            if (!context.mounted) return;
            Navigator.of(context).pop();
          });
        },
        child: scaffold,
      );
    }
    return scaffold;
  }
}

// ─── 加载动画遮罩 ──────────────────────────────────────────────────────────────

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
