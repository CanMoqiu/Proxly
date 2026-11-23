import '../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/connection_settings_store.dart';
import '../services/clash_host_validator.dart';
import '../services/clash_service.dart';
import '../services/connection_feedback.dart';
import '../services/optional_settings_visibility.dart';
import '../services/router_detection_service.dart';
import '../services/router_tool.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/app_feedback.dart';
import '../widgets/controller_form_fields.dart';
import 'main_shell.dart';

/// Guides initial Clash connection setup.
/// Shown by AppStartup when no controller address is configured.
class SetupWizardPage extends StatefulWidget {
  const SetupWizardPage({super.key, this.detectionService});
  final RouterDetectionService? detectionService;

  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage>
    with TransientFeedbackStateMixin<SetupWizardPage> {
  static const int _setupPageCount = 3;

  final PageController _pageController = PageController();
  int _currentStep = 0;

  final _hostController = TextEditingController();
  final _controllerPort = TextEditingController();
  final _deviceNameController = TextEditingController();
  final _tokenController = TextEditingController();
  final _sshPasswordController = TextEditingController();
  final _sshPortController = TextEditingController();
  final _hostFocusNode = FocusNode();
  bool _testing = false;
  bool _recognizing = false;
  RouterTool _routerTool = RouterTool.generic;
  ProxyCore _core = ProxyCore.unknown;
  String? _routerToolInput;
  bool _manualRouterTool = false;

  String get _detectionInput => [
        _hostController.text,
        _controllerPort.text,
        _tokenController.text,
        _sshPortController.text,
        _sshPasswordController.text
      ].join("\u0000");
  bool _saving = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _hostRequiredError = false;
  bool _showOptionalSettings = false;
  String _connectionsTabMode = 'webview';
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadOptionalSettings();
    _hostController.addListener(_clearHostErrorOnInput);
    _controllerPort.addListener(_clearTestResultOnInput);
    _tokenController.addListener(_clearTestResultOnInput);
    _sshPortController.addListener(_clearTestResultOnInput);
    _sshPasswordController.addListener(_clearTestResultOnInput);
  }

  @override
  void dispose() {
    _hostController.removeListener(_clearHostErrorOnInput);
    _controllerPort.removeListener(_clearTestResultOnInput);
    _tokenController.removeListener(_clearTestResultOnInput);
    _sshPortController.removeListener(_clearTestResultOnInput);
    _sshPasswordController.removeListener(_clearTestResultOnInput);
    disposeTransientFeedback();
    _hostFocusNode.dispose();
    _pageController.dispose();
    _hostController.dispose();
    _controllerPort.dispose();
    _deviceNameController.dispose();
    _tokenController.dispose();
    _sshPasswordController.dispose();
    _sshPortController.dispose();
    super.dispose();
  }

  Future<void> _loadOptionalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || !OptionalSettingsVisibility.read(prefs)) return;
    setState(() {
      _showOptionalSettings = true;
      _connectionsTabMode =
          prefs.getString('connections_tab_mode') ?? 'webview';
    });
  }

  void _goToStep(int step) {
    final next =
        step < 0 ? 0 : (step >= _setupPageCount ? _setupPageCount - 1 : step);
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep = next);
  }

  void _nextStep() => _goToStep(_currentStep + 1);

  void _previousStep() => _goToStep(_currentStep - 1);

  RouterTool? get _visibleBackend =>
      _manualRouterTool || _routerToolInput == _detectionInput
          ? _routerTool
          : null;

  Future<void> _chooseRouterTool() async {
    final selected =
        await showControllerBackendPicker(context, _visibleBackend);
    if (!mounted || selected == null) return;
    setState(() {
      _routerTool = selected;
      _manualRouterTool = true;
    });
  }

  void _clearHostErrorOnInput() {
    _clearTestResultOnInput();
    final clearRequired =
        _hostRequiredError && _hostController.text.trim().isNotEmpty;
    if (clearRequired || _testResult != null) {
      cancelFeedbackClear('connection_test');
      setState(() {
        if (clearRequired) _hostRequiredError = false;
        _testResult = null;
      });
    }
  }

  void _clearTestResultOnInput() {
    final staleBackend = !_manualRouterTool &&
        _routerToolInput != null &&
        _routerToolInput != _detectionInput;
    if (_testResult == null && !staleBackend) return;
    cancelFeedbackClear('connection_test');
    setState(() {
      if (staleBackend) _routerToolInput = null;
      _testResult = null;
    });
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

  Future<void> _handleConfigNext() async {
    if (_testing || _recognizing) return;
    if (_hostController.text.trim().isEmpty) {
      setState(() => _hostRequiredError = true);
      _hostFocusNode.requestFocus();
      return;
    }
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
    FocusScope.of(context).unfocus();
    final input = _detectionInput;
    setState(() => _recognizing = true);
    RouterDetectionResult? result;
    try {
      result = await (widget.detectionService ?? RouterDetectionService())
          .detect(
              host: endpoint.address,
              token: _tokenController.text.trim(),
              sshPassword: _sshPasswordController.text,
              sshPort:
                  ConnectionSettings.parseSshPort(_sshPortController.text) ??
                      22);
    } catch (_) {
      // Unidentified or unreachable controllers use the generic adapter.
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
    if (!mounted || input != _detectionInput || _currentStep != 1) return;
    setState(() {
      if (!_manualRouterTool) {
        _routerTool = result?.tool ?? RouterTool.generic;
        _manualRouterTool = false;
      }
      _core = result?.core ?? ProxyCore.unknown;
      _routerToolInput = input;
    });
    _nextStep();
  }

  Future<void> _testConnection() async {
    if (_testing || _recognizing) return;
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
    try {
      await (widget.detectionService ?? RouterDetectionService()).detect(
          host: endpoint.address,
          token: _tokenController.text.trim(),
          sshPassword: '',
          sshPort:
              ConnectionSettings.parseSshPort(_sshPortController.text) ?? 22);
      if (!mounted || input != _detectionInput) return;
      _setTestResult('连接正常', success: true);
    } catch (error) {
      if (!mounted || input != _detectionInput) return;
      _setTestResult(
          error is StateError && error.message == 'unauthorized'
              ? '密钥验证失败，请检查后重试'
              : ConnectionFeedback.unavailable,
          success: false);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _finish() async {
    final endpoint = ClashHostValidator.fromFields(
        _hostController.text, _controllerPort.text);
    if (endpoint.error case final error?) {
      final missingAddress = _hostController.text.trim().isEmpty;
      setState(() => _hostRequiredError = missingAddress);
      _setTestResult(error, success: false);
      _goToStep(1);
      if (missingAddress) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _hostFocusNode.requestFocus();
        });
      }
      return;
    }
    final sshPort = ConnectionSettings.parseSshPort(_sshPortController.text);
    if (sshPort == null) {
      _setTestResult('SSH 端口必须为 1–65535 之间的整数', success: false);
      _goToStep(1);
      return;
    }
    final deviceName = _deviceNameController.text;
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_showOptionalSettings) {
        await prefs.setString('connections_tab_mode', _connectionsTabMode);
      }
      await prefs.setString('theme_mode', _themeModeString(_themeMode));
      await ConnectionSettingsStore.instance.saveController(
        host: endpoint.address,
        deviceName: deviceName,
        token: _tokenController.text.trim(),
        sshPassword: _sshPasswordController.text,
        sshPort: sshPort,
        routerTool: _routerTool,
        routerSelectionPending: false,
        routerToolConfirmed: true,
        core: _core,
      );
      await ClashService.instance.loadConfig();
      if (!mounted) return;
      // Replace the route stack only after settings are persisted.
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
    } catch (e) {
      if (mounted) {
        AppFeedback.showSnackBar(
          context,
          tr('保存设置失败：$e'),
          tone: AppFeedbackTone.error,
        );
        setState(() => _saving = false);
      }
    }
  }

  void _setThemeMode(ThemeMode mode) {
    ProxlyApp.setThemeModeOf(context, mode);
    setState(() => _themeMode = mode);
  }

  static String _themeModeString(ThemeMode mode) {
    return mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final bgColor = palette.pageBackground;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false,
        child: AdaptiveContent(
            child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _WelcomePage(onNext: _nextStep),
            _ConfigPage(
              hostController: _hostController,
              controllerPort: _controllerPort,
              backend: _visibleBackend,
              onChooseBackend: _chooseRouterTool,
              deviceNameController: _deviceNameController,
              hostFocusNode: _hostFocusNode,
              tokenController: _tokenController,
              sshPasswordController: _sshPasswordController,
              sshPortController: _sshPortController,
              showHostRequiredError: _hostRequiredError,
              testing: _testing,
              recognizing: _recognizing,
              testResult: _testResult,
              testSuccess: _testSuccess,
              onTest: _testConnection,
              onBack: _recognizing ? null : _previousStep,
              onNext: _testing || _recognizing ? null : _handleConfigNext,
            ),
            _PreferencesPage(
              saving: _saving,
              themeMode: _themeMode,
              onThemeModeChanged: _setThemeMode,
              onBack: _previousStep,
              onFinish: _finish,
              showOptionalSettings: _showOptionalSettings,
              connectionsTabMode: _connectionsTabMode,
              onSetConnectionsMode: (m) =>
                  setState(() => _connectionsTabMode = m),
            ),
          ],
        )),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: Container(
          height: 36,
          color: bgColor,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_setupPageCount, (i) {
              final active = i == _currentStep;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? primary : palette.textDisabled,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;

  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final textColor = palette.textPrimary;
    final hintColor = palette.textSecondary;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: AppLanguagePicker(compact: true),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final compact = viewport.maxHeight < 490;
                final logoSize = compact ? 64.0 : 88.0;
                return SingleChildScrollView(
                  key: const ValueKey('setup_welcome_scroll'),
                  padding: EdgeInsets.only(
                    top: (viewport.maxHeight * .055).clamp(12.0, 36.0),
                    bottom: 12,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(logoSize * .25),
                            child: Image.asset(
                              'assets/app_icon.png',
                              width: logoSize,
                              height: logoSize,
                              fit: BoxFit.cover,
                            ),
                          ),
                          SizedBox(height: compact ? 10 : 16),
                          Text(
                            tr('欢迎使用 Proxly'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: compact ? 25 : 30,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr('Proxly 帮你管理软路由代理工具，查看运行状态、流量、连接和 YAML 配置。'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: hintColor,
                              height: 1.45,
                            ),
                          ),
                          SizedBox(height: compact ? 16 : 24),
                          for (final highlight in _highlights)
                            Padding(
                              padding: EdgeInsets.symmetric(
                                  vertical: compact ? 4 : 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: primary.withValues(alpha: .10),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Center(
                                      child: highlight.asset != null
                                          ? SvgPicture.asset(
                                              highlight.asset!,
                                              width: 20,
                                              height: 20,
                                              colorFilter: ColorFilter.mode(
                                                  primary, BlendMode.srcIn),
                                              excludeFromSemantics: true,
                                            )
                                          : Icon(highlight.icon,
                                              size: 20, color: primary),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tr(highlight.title),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                          ),
                                        ),
                                        Text(
                                          tr(highlight.desc),
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.4,
                                            color: hintColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                onPressed: onNext,
                child: Text(tr('开始设置'), textAlign: TextAlign.center),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _highlights = [
    _Highlight(
      icon: Icons.bar_chart_rounded,
      title: '实时流量',
      desc: '查看速率曲线与上传、下载用量',
    ),
    _Highlight(
        asset: 'assets/icons/link.svg', title: '连接详情', desc: '查看活跃连接和完整代理链路'),
    _Highlight(
      asset: 'assets/icons/proxy.svg',
      title: '代理控制',
      desc: '通过 Zashboard 管理代理节点',
    ),
    _Highlight(
      icon: Icons.description_outlined,
      title: '配置文件',
      desc: '读取、编辑并上传代理 YAML',
    ),
  ];
}

class _Highlight {
  final IconData? icon;
  final String? asset;
  final String title;
  final String desc;
  const _Highlight({
    this.icon,
    this.asset,
    required this.title,
    required this.desc,
  });
}

class _ConfigPage extends StatelessWidget {
  final TextEditingController hostController;
  final TextEditingController controllerPort;
  final RouterTool? backend;
  final VoidCallback onChooseBackend;
  final TextEditingController deviceNameController;
  final FocusNode hostFocusNode;
  final TextEditingController tokenController;
  final TextEditingController sshPasswordController;
  final TextEditingController sshPortController;
  final bool showHostRequiredError;
  final bool testing;
  final bool recognizing;
  final String? testResult;
  final bool testSuccess;
  final VoidCallback onTest;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  const _ConfigPage({
    required this.hostController,
    required this.controllerPort,
    required this.backend,
    required this.onChooseBackend,
    required this.deviceNameController,
    required this.hostFocusNode,
    required this.tokenController,
    required this.sshPasswordController,
    required this.sshPortController,
    required this.showHostRequiredError,
    required this.testing,
    required this.recognizing,
    required this.testResult,
    required this.testSuccess,
    required this.onTest,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final cardBg = palette.surface;
    final cardBorder = palette.border;
    final textColor = palette.textPrimary;
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  // Only shrink the form viewport; navigation stays behind the
                  // keyboard. Account for the fixed footer outside this area.
                  padding: EdgeInsets.only(
                    bottom: (MediaQuery.viewInsetsOf(context).bottom -
                            MediaQuery.viewPaddingOf(context).bottom -
                            36 -
                            18 -
                            64)
                        .clamp(0.0, double.infinity),
                  ),
                  child: SingleChildScrollView(
                    key: const ValueKey('setup_config_scroll'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('连接设置'),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            key: const ValueKey('setup_connection_card'),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: cardBorder, width: 0.5),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ControllerFormFields(
                                  name: deviceNameController,
                                  address: hostController,
                                  port: controllerPort,
                                  secret: tokenController,
                                  sshPort: sshPortController,
                                  sshSecret: sshPasswordController,
                                  backend: backend,
                                  onChooseBackend:
                                      recognizing ? null : onChooseBackend,
                                  addressFocus: hostFocusNode,
                                  addressError: showHostRequiredError,
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton(
                                  onPressed:
                                      testing || recognizing ? null : onTest,
                                  child: testing
                                      ? SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: primary,
                                          ),
                                        )
                                      : Text(
                                          tr('测试连接'),
                                          textAlign: TextAlign.center,
                                        ),
                                ),
                                if (testResult case final result?)
                                  ControllerTestFeedback(
                                    message: result,
                                    success: testSuccess,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _WizardNavButtons(
                  onBack: onBack, onNext: onNext, busy: recognizing),
            ],
          ),
        ),
      ),
    );
  }
}

class _WizardNavButtons extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final bool busy;

  const _WizardNavButtons({
    required this.onBack,
    required this.onNext,
    this.nextLabel = '继续',
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final borderColor = palette.border;
    final textColor = palette.textPrimary;

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onBack,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Center(
                child: AdaptiveSingleLineText(
                  tr('返回'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: onBack == null ? borderColor : textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: onNext,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : AdaptiveSingleLineText(
                        tr(nextLabel),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreferencesPage extends StatelessWidget {
  final bool saving;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool showOptionalSettings;
  final String connectionsTabMode;
  final ValueChanged<String> onSetConnectionsMode;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  const _PreferencesPage({
    required this.saving,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.showOptionalSettings,
    required this.connectionsTabMode,
    required this.onSetConnectionsMode,
    required this.onBack,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final textColor = palette.textPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('setup_preferences_scroll'),
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('使用偏好'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PreferenceSection(
                        title: tr('外观模式'),
                        child: ThemeModeSelector(
                          mode: themeMode,
                          isDark: isDark,
                          lightLabel: tr('浅色'),
                          darkLabel: tr('深色'),
                          followSystemLabel: tr('跟随系统'),
                          onChanged: onThemeModeChanged,
                        ),
                      ),
                      if (showOptionalSettings) ...[
                        const SizedBox(height: 14),
                        _PreferenceSection(
                          title: tr('连接页显示'),
                          description: tr('原生列表更快，面板采用移动布局。'),
                          child: AdaptiveOptionGroup(
                            labels: [tr('原生列表'), tr('Zashboard 面板')],
                            spacing: 10,
                            children: [
                              _ModeButton(
                                label: tr('原生列表'),
                                icon: Icons.list_alt_rounded,
                                selected: connectionsTabMode == 'native',
                                onTap: () => onSetConnectionsMode('native'),
                              ),
                              _ModeButton(
                                label: tr('Zashboard 面板'),
                                icon: Icons.language_rounded,
                                selected: connectionsTabMode == 'webview',
                                onTap: () => onSetConnectionsMode('webview'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _WizardNavButtons(
              onBack: saving ? null : onBack,
              onNext: saving ? null : onFinish,
              nextLabel: tr('完成设置'),
              busy: saving,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceSection extends StatelessWidget {
  final String title;
  final String? description;
  final Widget child;

  const _PreferenceSection({
    required this.title,
    this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final cardBg = palette.surface;
    final cardBorder = palette.border;
    final textColor = palette.textPrimary;
    final hintColor = palette.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          if (description case final details?) ...[
            const SizedBox(height: 4),
            Text(
              details,
              style: TextStyle(fontSize: 12, color: hintColor, height: 1.45),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveSelectionButton(
      label: label,
      icon: icon,
      selected: selected,
      onTap: onTap,
    );
  }
}
