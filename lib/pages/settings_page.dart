import 'dart:async';

import '../l10n/app_locale.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_secure_storage.dart';
import '../services/clash_data_hub.dart';
import '../services/connection_settings_store.dart';
import '../services/clash_host_validator.dart';
import '../services/clash_service.dart';
import '../services/connection_feedback.dart';
import '../services/controller_connection_state.dart';
import '../services/router_tool.dart';
import '../services/router_detection_service.dart';
import '../services/router_detection_session.dart';
import '../services/web_panel_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup.dart';
import '../widgets/controller_form_fields.dart';
import '../widgets/dashboard/dashboard_button_style.dart';
import 'about_page.dart';
import 'developer_options_page.dart';
import 'device_management_page.dart';
import '../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.detectionService, this.active = true});
  final RouterDetectionService? detectionService;
  final bool active;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TransientFeedbackStateMixin<SettingsPage> {
  final _deviceNameController = TextEditingController();
  final _hostController = TextEditingController();
  final _controllerPort = TextEditingController();
  final _tokenController = TextEditingController();
  final _sshPasswordController = TextEditingController();
  final _sshPortController = TextEditingController(text: '22');
  late final _fields = [
    _deviceNameController,
    _hostController,
    _controllerPort,
    _tokenController,
    _sshPasswordController,
    _sshPortController,
  ];
  late Map<TextEditingController, String> _savedFields = {
    for (final field in _fields) field: field.text,
  };
  RouterTool _savedRouterTool = RouterTool.generic;
  ProxyCore _savedCore = ProxyCore.unknown;
  RouterTool? _backendChoice;
  bool _testing = false;
  int _testRevision = 0;
  int _settingsRevision = 0;
  RouterTool _routerTool = RouterTool.generic;
  ProxyCore _core = ProxyCore.unknown;
  String? _detectedInput;

  String get _detectionInput => [
        _hostController.text,
        _controllerPort.text,
        _tokenController.text,
        _sshPortController.text,
        _sshPasswordController.text,
      ].join("\u0000");
  bool _saving = false;
  bool _switchingDevice = false;
  String? _deviceSwitchMessage;
  bool _deviceSwitchFailed = false;
  Future<void>? _settingsReload;
  bool _updatingControllerValues = false;
  bool _settingsLoadFailed = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    ConnectionSettingsStore.instance.addListener(_handleSettingsChanged);
    _hostController.addListener(_clearTestResultOnInput);
    _controllerPort.addListener(_clearTestResultOnInput);
    _tokenController.addListener(_clearTestResultOnInput);
    _sshPortController.addListener(_clearTestResultOnInput);
    _sshPasswordController.addListener(_clearTestResultOnInput);
    _loadSettings();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _testRevision++;
      _testing = false;
      _restoreSavedController();
    }
  }

  void _handleSettingsChanged() {
    if (ConnectionSettingsStore.instance.lastChange ==
        ConnectionSettingsChange.routerIdentity) {
      unawaited(_syncRouterIdentity());
    } else {
      final reload = _loadSettings();
      _settingsReload = reload;
      unawaited(reload);
    }
  }

  Future<void> _syncRouterIdentity() async {
    final store = ConnectionSettingsStore.instance;
    final revision = store.revision;
    try {
      final settings = await store.load();
      if (!mounted || store.revision != revision) return;
      setState(() {
        _savedRouterTool = settings.routerTool;
        _savedCore = settings.core;
        if (_detectedInput == _detectionInput) {
          _routerTool = _savedRouterTool;
          _core = _savedCore;
        }
      });
    } catch (_) {
      // Keep the current form if credentials are temporarily unavailable.
    }
  }

  void _clearTestResultOnInput() {
    if (_updatingControllerValues) return;
    if (_detectedInput != null && _detectedInput != _detectionInput) {
      setState(() {
        _detectedInput = null;
        _routerTool = RouterTool.generic;
        _core = ProxyCore.unknown;
      });
    }
    if (_testResult == null) return;
    cancelFeedbackClear('connection_test');
    setState(() => _testResult = null);
  }

  void _setTestResult(String message, {required bool success}) {
    if (!mounted) return;
    setState(() {
      _testSuccess = success;
      _testResult = message;
    });
    scheduleFeedbackClear(
      'connection_test',
      isError: !success,
      clear: () => setState(() => _testResult = null),
    );
  }

  void _restoreSavedController() {
    cancelFeedbackClear('connection_test');
    _updatingControllerValues = true;
    for (final entry in _savedFields.entries) {
      if (entry.key.text != entry.value) entry.key.text = entry.value;
    }
    _updatingControllerValues = false;
    _backendChoice = null;
    _routerTool = _savedRouterTool;
    _core = _savedCore;
    _detectedInput = _detectionInput;
    _testResult = null;
  }

  Future<void> _loadSettings() async {
    final revision = ++_settingsRevision;
    final store = ConnectionSettingsStore.instance;
    try {
      final settings = await store.load();
      if (!mounted || revision != _settingsRevision) return;
      final endpoint = ClashHostValidator.parseEndpoint(settings.host);
      setState(() {
        _settingsLoadFailed = false;
        _savedRouterTool = settings.routerTool;
        _savedCore = settings.core;
        _savedFields = {
          _deviceNameController: store.activeDevice?.name ?? '',
          _hostController: endpoint?.hostname ?? '',
          _controllerPort: endpoint?.portText ?? '',
          _tokenController: settings.token,
          _sshPasswordController: settings.sshPassword,
          _sshPortController: settings.sshPort.toString(),
        };
        _restoreSavedController();
      });
    } catch (_) {
      if (mounted && revision == _settingsRevision) {
        setState(() => _settingsLoadFailed = true);
      }
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    ProxlyApp.setThemeModeOf(context, mode);
    // Refresh local controls after changing the shared theme.
    if (mounted) setState(() {});
    final prefs = await SharedPreferences.getInstance();
    final str = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';
    await prefs.setString('theme_mode', str);
  }

  Future<void> _saveSettings() async {
    if (_testing || _saving || _switchingDevice) return;
    if (_settingsLoadFailed) {
      await _loadSettings();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final endpoint = ClashHostValidator.fromFields(
        _hostController.text, _controllerPort.text);
    if (endpoint.error case final error?) {
      AppFeedback.showSnackBar(context, error, tone: AppFeedbackTone.error);
      return;
    }
    final sshPort = ConnectionSettings.parseSshPort(_sshPortController.text);
    if (sshPort == null) {
      AppFeedback.showSnackBar(
        context,
        tr('SSH 端口必须为 1–65535 之间的整数'),
        tone: AppFeedbackTone.error,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ConnectionSettingsStore.instance.saveController(
        host: endpoint.address,
        deviceName: ConnectionSettingsStore.instance.activeDevice != null ||
                _deviceNameController.text.trim().isNotEmpty
            ? _deviceNameController.text
            : null,
        token: _tokenController.text.trim(),
        sshPassword: _sshPasswordController.text,
        sshPort: sshPort,
        routerTool: _backendChoice ?? _routerTool,
        core: _core,
        routerToolConfirmed: _backendChoice != null,
        routerSelectionPending:
            _backendChoice == null && _routerTool == RouterTool.generic,
      );
      await _settingsReload;
      await ClashService.instance.loadConfig();
      unawaited(RouterDetectionSession.instance.refresh());
      ClashDataHub.instance.resetBaseline(clearSnapshot: true);
      await Future.wait([
        WebPanelSync.instance.reload(),
        WebPanelSync.instance.reloadConnections(force: true),
      ]);
      if (mounted) {
        AppFeedback.showSnackBar(
          context,
          tr('设置已保存'),
          tone: AppFeedbackTone.success,
        );
      }
    } on ArgumentError {
      if (mounted) {
        AppFeedback.showSnackBar(context, tr('设备名称已使用'),
            tone: AppFeedbackTone.error);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showSnackBar(
          context,
          tr('保存失败：$e'),
          tone: AppFeedbackTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    if (_testing || _saving || _switchingDevice) return;
    if (ConnectionSettings.parseSshPort(_sshPortController.text) == null) {
      _setTestResult('SSH 端口必须为 1–65535 之间的整数', success: false);
      return;
    }
    final endpoint = ClashHostValidator.fromFields(
        _hostController.text, _controllerPort.text);
    if (endpoint.error case final error?) {
      _setTestResult(error, success: false);
      return;
    }
    cancelFeedbackClear('connection_test');
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final input = _detectionInput;
    final revision = ++_testRevision;
    try {
      await (widget.detectionService ?? RouterDetectionService()).detect(
        host: endpoint.address,
        token: _tokenController.text.trim(),
        sshPassword: '',
        sshPort: ConnectionSettings.parseSshPort(_sshPortController.text) ?? 22,
      );
      if (!mounted || revision != _testRevision || input != _detectionInput) {
        return;
      }
      _setTestResult('连接正常', success: true);
    } catch (_) {
      if (mounted && revision == _testRevision && input == _detectionInput) {
        _setTestResult(ConnectionFeedback.unavailable, success: false);
      }
    } finally {
      if (mounted && revision == _testRevision) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _chooseBackend() async {
    final store = ConnectionSettingsStore.instance;
    final generation = store.deviceGeneration;
    final selected = await showControllerBackendPicker(
        context, _backendChoice ?? _routerTool);
    if (!mounted ||
        !widget.active ||
        selected == null ||
        store.deviceGeneration != generation) {
      return;
    }
    setState(() => _backendChoice = selected);
  }

  Future<void> _openDeviceSwitcher() async {
    if (_saving || _testing || _switchingDevice) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final store = ConnectionSettingsStore.instance;
    cancelFeedbackClear('device_switch');
    setState(() {
      _switchingDevice = true;
      _deviceSwitchMessage = null;
    });
    try {
      final selected = await AppPopup.sheet<DeviceProfile>(
        context: context,
        builder: (_) => const DeviceManagementSheet(),
      );
      if (!mounted ||
          selected == null ||
          selected.id == store.activeDevice?.id) {
        return;
      }

      if (!store.canSwitchDevice) {
        _setDeviceSwitchFeedback('远端操作完成后可切换设备。', failed: true);
        return;
      }
      await store.switchDevice(selected.id);
      await _settingsReload;
      _setDeviceSwitchFeedback('已切换到 ${selected.name}');
    } on SecureStorageUnavailableException {
      _setDeviceSwitchFeedback('无法读取目标设备的凭据，请解锁后重试。', failed: true);
    } catch (_) {
      _setDeviceSwitchFeedback('无法切换设备，请稍后重试。', failed: true);
    } finally {
      if (mounted) setState(() => _switchingDevice = false);
    }
  }

  void _setDeviceSwitchFeedback(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _deviceSwitchMessage = message;
      _deviceSwitchFailed = failed;
    });
    scheduleFeedbackClear(
      'device_switch',
      isError: failed,
      clear: () => setState(() => _deviceSwitchMessage = null),
    );
  }

  Widget _controllerStatus(AppPalette palette) {
    final connection = ControllerConnectionState.instance;
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final phase = connection.phase;
        final message = switch (phase) {
          ControllerConnectionPhase.unknown => '检查中…',
          ControllerConnectionPhase.online => '已连接',
          ControllerConnectionPhase.offline => '设备离线',
          ControllerConnectionPhase.unauthorized => '请检查控制器密钥。',
          ControllerConnectionPhase.restarting => '重启中',
        };
        final failed = phase == ControllerConnectionPhase.offline ||
            phase == ControllerConnectionPhase.unauthorized;
        return Semantics(
          liveRegion: true,
          child: Text(
            tr(message),
            style: TextStyle(
              fontSize: 12,
              color: failed ? palette.error : palette.textSecondary,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    ConnectionSettingsStore.instance.removeListener(_handleSettingsChanged);
    _hostController.removeListener(_clearTestResultOnInput);
    _controllerPort.removeListener(_clearTestResultOnInput);
    _tokenController.removeListener(_clearTestResultOnInput);
    _sshPortController.removeListener(_clearTestResultOnInput);
    _sshPasswordController.removeListener(_clearTestResultOnInput);
    disposeTransientFeedback();
    _deviceNameController.dispose();
    _hostController.dispose();
    _controllerPort.dispose();
    _tokenController.dispose();
    _sshPasswordController.dispose();
    _sshPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final cardBg = palette.surface;
    final cardBorder = palette.border;
    final textColor = palette.textPrimary;
    final hintColor = palette.textSecondary;
    final bgColor = palette.pageBackground;
    final dividerColor = palette.border;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          tr('设置'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: dividerColor),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: AdaptiveContent(
          child: SingleChildScrollView(
            padding: AdaptiveScrollPadding.page(context, top: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const ValueKey('settings_connection_card'),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cardBorder, width: 0.5),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('控制器设置'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                                if (ConnectionSettingsStore
                                        .instance.activeDevice !=
                                    null)
                                  _controllerStatus(palette),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            key: const ValueKey('settings_switch_device'),
                            style: ButtonStyle(
                              splashFactory: NoSplash.splashFactory,
                              overlayColor: WidgetStateProperty.resolveWith(
                                (states) => states.contains(WidgetState.pressed)
                                    ? Colors.transparent
                                    : null,
                              ),
                            ),
                            onPressed: _saving || _testing || _switchingDevice
                                ? null
                                : _openDeviceSwitcher,
                            child: Text(tr('切换')),
                          ),
                        ],
                      ),
                      if (_deviceSwitchMessage case final message?) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            tr(message),
                            style: TextStyle(
                              fontSize: 12,
                              color: _deviceSwitchFailed
                                  ? palette.error
                                  : palette.success,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_settingsLoadFailed) ...[
                        Text(tr('凭据暂时不可用，请解锁设备后重试。已保存的配置未被删除。')),
                        TextButton(
                          onPressed: _loadSettings,
                          child: Text(tr('重试')),
                        ),
                      ],
                      ControllerFormFields(
                        name: _deviceNameController,
                        address: _hostController,
                        port: _controllerPort,
                        secret: _tokenController,
                        sshPort: _sshPortController,
                        sshSecret: _sshPasswordController,
                        backend: _backendChoice ?? _routerTool,
                        backendEdited: _backendChoice != null &&
                            _backendChoice != _savedRouterTool,
                        onChooseBackend: _chooseBackend,
                        enabled: !_saving && !_switchingDevice,
                        editedFields: {
                          for (final entry in _savedFields.entries)
                            if (entry.key.text != entry.value) entry.key,
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _testing || _saving || _switchingDevice
                                  ? null
                                  : _testConnection,
                              style: DashboardButtonStyle.action,
                              child: _testing
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : AdaptiveSingleLineText(tr('测试连接')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _testing || _saving || _switchingDevice
                                  ? null
                                  : _saveSettings,
                              style: DashboardButtonStyle.action,
                              child: _saving
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : AdaptiveSingleLineText(tr('保存')),
                            ),
                          ),
                        ],
                      ),
                      if (_testResult case final result?)
                        ControllerTestFeedback(
                          message: result,
                          success: _testSuccess,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  key: const ValueKey('settings_theme_card'),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cardBorder, width: 0.5),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('外观主题'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ThemeModeSelector(
                        mode: ProxlyApp.activeThemeMode,
                        isDark: isDark,
                        lightLabel: tr('浅色'),
                        darkLabel: tr('深色'),
                        followSystemLabel: tr('跟随系统'),
                        onChanged: _setTheme,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _NavRow(
                  icon: Icons.code_rounded,
                  title: tr('高级选项'),
                  cardBg: cardBg,
                  cardBorder: cardBorder,
                  textColor: textColor,
                  hintColor: hintColor,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DeveloperOptionsPage()),
                  ),
                ),
                const SizedBox(height: 12),
                _NavRow(
                  icon: Icons.info_outline_rounded,
                  title: tr('关于 Proxly'),
                  cardBg: cardBg,
                  cardBorder: cardBorder,
                  textColor: textColor,
                  hintColor: hintColor,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color cardBg;
  final Color cardBorder;
  final Color textColor;
  final Color hintColor;
  final VoidCallback onTap;

  const _NavRow({
    required this.icon,
    required this.title,
    required this.cardBg,
    required this.cardBorder,
    required this.textColor,
    required this.hintColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cardBorder, width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr(title),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: hintColor),
          ],
        ),
      ),
    );
  }
}
