import '../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/connection_settings_store.dart';
import '../services/clash_host_validator.dart';
import '../services/clash_service.dart';
import '../services/connection_feedback.dart';
import '../services/router_detection_service.dart';
import '../services/router_tool.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup.dart';
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
  final _tokenController = TextEditingController();
  final _sshPasswordController = TextEditingController();
  final _sshPortController = TextEditingController(text: '22');
  final _hostFocusNode = FocusNode();
  bool _obscureToken = true;
  bool _obscureSshPassword = true;
  bool _testing = false;
  bool _recognizing = false;
  RouterTool _routerTool = RouterTool.generic;
  ProxyCore _core = ProxyCore.unknown;
  String? _routerToolInput;
  bool _manualRouterTool = false;

  String get _detectionInput => [
        _hostController.text,
        _tokenController.text,
        _sshPortController.text,
        _sshPasswordController.text
      ].join("\u0000");
  bool _saving = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _hostRequiredError = false;
  String _connectionsTabMode = 'webview';
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _hostController.addListener(_clearHostErrorOnInput);
    _tokenController.addListener(_clearTestResultOnInput);
    _sshPortController.addListener(_clearTestResultOnInput);
    _sshPasswordController.addListener(_clearTestResultOnInput);
  }

  @override
  void dispose() {
    _hostController.removeListener(_clearHostErrorOnInput);
    _tokenController.removeListener(_clearTestResultOnInput);
    _sshPortController.removeListener(_clearTestResultOnInput);
    _sshPasswordController.removeListener(_clearTestResultOnInput);
    disposeTransientFeedback();
    _hostFocusNode.dispose();
    _pageController.dispose();
    _hostController.dispose();
    _tokenController.dispose();
    _sshPasswordController.dispose();
    _sshPortController.dispose();
    super.dispose();
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

  Future<void> _chooseRouterTool() async {
    FocusScope.of(context).unfocus();
    final selected = await AppPopup.sheet<RouterTool>(
        context: context,
        builder: (_) => AppOptionsSheet<RouterTool>(
              title: tr('选择代理软件'),
              selectedValue: _routerTool,
              options: [
                for (final tool in RouterTool.values)
                  AppSheetOption(
                      value: tool,
                      label: tr(tool.label),
                      icon: Icons.hub_outlined,
                      subtitle:
                          tool == RouterTool.generic ? tr('仅使用通用控制器功能') : null)
              ],
            ));
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
    final hostError = ClashHostValidator.validationError(_hostController.text);
    if (hostError != null) {
      _setTestResult(hostError, success: false);
      return;
    }
    FocusScope.of(context).unfocus();
    final input = _detectionInput;
    final keepManualChoice = _manualRouterTool && input == _routerToolInput;
    setState(() => _recognizing = true);
    RouterDetectionResult? result;
    try {
      result = await (widget.detectionService ?? RouterDetectionService())
          .detect(
              host: ClashHostValidator.normalizeAddress(_hostController.text),
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
      if (!keepManualChoice) {
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
    final host = ClashHostValidator.normalizeAddress(_hostController.text);
    if (host.isEmpty) {
      _setTestResult('请先填写控制器地址', success: false);
      return;
    }
    final hostError = ClashHostValidator.validationError(host);
    if (hostError != null) {
      _setTestResult(hostError, success: false);
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
          host: host,
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
    final host = ClashHostValidator.normalizeAddress(_hostController.text);
    if (host.isEmpty) {
      setState(() => _hostRequiredError = true);
      _goToStep(1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hostFocusNode.requestFocus();
      });
      return;
    }
    final hostError = ClashHostValidator.validationError(host);
    if (hostError != null) {
      setState(() => _hostRequiredError = true);
      _setTestResult(hostError, success: false);
      _goToStep(1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hostFocusNode.requestFocus();
      });
      return;
    }
    final sshPort = ConnectionSettings.parseSshPort(_sshPortController.text);
    if (sshPort == null) {
      _setTestResult('SSH 端口必须为 1–65535 之间的整数', success: false);
      _goToStep(1);
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('connections_tab_mode', _connectionsTabMode);
      await prefs.setString('theme_mode', _themeModeString(_themeMode));
      await ConnectionSettingsStore.instance.saveController(
        host: host,
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
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _WelcomePage(onNext: _nextStep),
            _ConfigPage(
              hostController: _hostController,
              hostFocusNode: _hostFocusNode,
              tokenController: _tokenController,
              sshPasswordController: _sshPasswordController,
              sshPortController: _sshPortController,
              showHostRequiredError: _hostRequiredError,
              obscureToken: _obscureToken,
              onToggleObscure: () =>
                  setState(() => _obscureToken = !_obscureToken),
              obscureSshPassword: _obscureSshPassword,
              onToggleSshObscure: () =>
                  setState(() => _obscureSshPassword = !_obscureSshPassword),
              testing: _testing,
              recognizing: _recognizing,
              testResult: _testResult,
              testSuccess: _testSuccess,
              onTest: _testConnection,
              onBack: _recognizing ? null : _previousStep,
              onNext: _testing || _recognizing ? null : _handleConfigNext,
            ),
            _PreferencesPage(
              routerTool: _routerTool,
              onChooseRouterTool: _chooseRouterTool,
              saving: _saving,
              themeMode: _themeMode,
              onThemeModeChanged: _setThemeMode,
              onBack: _previousStep,
              onFinish: _finish,
              connectionsTabMode: _connectionsTabMode,
              onSetConnectionsMode: (m) =>
                  setState(() => _connectionsTabMode = m),
            ),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerRight,
                child: AppLanguagePicker(compact: true),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('setup_welcome_scroll'),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            'assets/app_icon.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          tr('欢迎使用 Proxly'),
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr(
                            'Proxly 帮你管理软路由代理工具，查看运行状态、流量、连接和 YAML 配置。',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: hintColor,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 22),
                        ..._highlights.map(
                          (h) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Icon(h.icon, size: 19, color: primary),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tr(h.title),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: textColor,
                                        ),
                                      ),
                                      Text(
                                        tr(h.desc),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: hintColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: onNext,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: AdaptiveSingleLineText(
                        tr('开始设置'),
                        style: TextStyle(
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
        },
      ),
    );
  }

  static const _highlights = [
    _Highlight(
      icon: Icons.bar_chart_rounded,
      title: '实时流量',
      desc: '查看速率曲线与上传、下载用量',
    ),
    _Highlight(icon: Icons.lan_outlined, title: '连接详情', desc: '查看活跃连接和完整代理链路'),
    _Highlight(
      icon: Icons.hub_outlined,
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
  final IconData icon;
  final String title;
  final String desc;
  const _Highlight({
    required this.icon,
    required this.title,
    required this.desc,
  });
}

class _ConfigPage extends StatelessWidget {
  final TextEditingController hostController;
  final FocusNode hostFocusNode;
  final TextEditingController tokenController;
  final TextEditingController sshPasswordController;
  final TextEditingController sshPortController;
  final bool showHostRequiredError;
  final bool obscureToken;
  final VoidCallback onToggleObscure;
  final bool obscureSshPassword;
  final VoidCallback onToggleSshObscure;
  final bool testing;
  final bool recognizing;
  final String? testResult;
  final bool testSuccess;
  final VoidCallback onTest;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  const _ConfigPage({
    required this.hostController,
    required this.hostFocusNode,
    required this.tokenController,
    required this.sshPasswordController,
    required this.sshPortController,
    required this.showHostRequiredError,
    required this.obscureToken,
    required this.onToggleObscure,
    required this.obscureSshPassword,
    required this.onToggleSshObscure,
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
    final inputBg = palette.inputBackground;
    final labelColor = palette.textSecondary;
    final textColor = palette.textPrimary;
    final hintColor = palette.textSecondary;
    final primary = Theme.of(context).colorScheme.primary;

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cardBorder, width: 0.5),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: primary, width: 1),
    );
    final hostErrorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: palette.error, width: 1.2),
    );
    final hostEnabledBorder =
        showHostRequiredError ? hostErrorBorder : inputBorder;
    final hostFocusedBorder =
        showHostRequiredError ? hostErrorBorder : focusedBorder;

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
                          const SizedBox(height: 6),
                          Text(
                            tr('填写控制器地址；密钥和 SSH 密码可按需填写，之后可在设置页修改'),
                            style: TextStyle(
                              fontSize: 13,
                              color: hintColor,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: cardBorder, width: 0.5),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LabeledInputField(
                                  title: tr('控制器地址'),
                                  description: tr(
                                    '填写 Clash API 地址，格式为 IP:端口',
                                  ),
                                  titleColor: textColor,
                                  descriptionColor: labelColor,
                                  child: TextField(
                                    controller: hostController,
                                    focusNode: hostFocusNode,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: textColor,
                                    ),
                                    keyboardType: TextInputType.url,
                                    textInputAction: TextInputAction.next,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    decoration: InputDecoration(
                                      hintText: tr('IP:端口'),
                                      hintStyle: TextStyle(color: hintColor),
                                      filled: true,
                                      fillColor: inputBg,
                                      border: inputBorder,
                                      enabledBorder: hostEnabledBorder,
                                      focusedBorder: hostFocusedBorder,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                LabeledInputField(
                                  title: tr('控制器密钥'),
                                  description: tr('用于访问已设置密钥的控制器，未设置可留空'),
                                  titleColor: textColor,
                                  descriptionColor: labelColor,
                                  child: TextField(
                                    controller: tokenController,
                                    obscureText: obscureToken,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: textColor,
                                    ),
                                    textInputAction: TextInputAction.next,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    decoration: InputDecoration(
                                      hintText: tr('请输入密钥'),
                                      hintStyle: TextStyle(color: hintColor),
                                      filled: true,
                                      fillColor: inputBg,
                                      border: inputBorder,
                                      enabledBorder: inputBorder,
                                      focusedBorder: focusedBorder,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          obscureToken
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: hintColor,
                                          size: 20,
                                        ),
                                        onPressed: onToggleObscure,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                LabeledInputField(
                                  title: tr('SSH 端口'),
                                  description: tr('留空使用默认端口 22'),
                                  titleColor: textColor,
                                  descriptionColor: labelColor,
                                  child: TextField(
                                    key: const ValueKey('ssh_port_field'),
                                    controller: sshPortController,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: textColor,
                                    ),
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.next,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    decoration: InputDecoration(
                                      hintText: '22',
                                      hintStyle: TextStyle(color: hintColor),
                                      filled: true,
                                      fillColor: inputBg,
                                      border: inputBorder,
                                      enabledBorder: inputBorder,
                                      focusedBorder: focusedBorder,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                LabeledInputField(
                                  title: tr('SSH 密码（可选）'),
                                  description: tr(
                                    '用于识别代理软件、管理 YAML 和重启服务，未使用 SSH 可留空',
                                  ),
                                  titleColor: textColor,
                                  descriptionColor: labelColor,
                                  child: TextField(
                                    controller: sshPasswordController,
                                    obscureText: obscureSshPassword,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: textColor,
                                    ),
                                    textInputAction: TextInputAction.done,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    decoration: InputDecoration(
                                      hintText: tr('请输入密码'),
                                      hintStyle: TextStyle(color: hintColor),
                                      filled: true,
                                      fillColor: inputBg,
                                      border: inputBorder,
                                      enabledBorder: inputBorder,
                                      focusedBorder: focusedBorder,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          obscureSshPassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: hintColor,
                                          size: 20,
                                        ),
                                        onPressed: onToggleSshObscure,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: testing || recognizing ? null : onTest,
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: cardBorder, width: 0.5),
                              ),
                              padding: const EdgeInsets.all(14),
                              child: Center(
                                child: testing
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: primary,
                                        ),
                                      )
                                    : AdaptiveSingleLineText(
                                        tr('检查连接'),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: primary,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          if (testResult != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: (testSuccess
                                        ? palette.success
                                        : palette.error)
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: testSuccess
                                      ? palette.success
                                      : palette.error,
                                  width: 0.5,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: testSuccess
                                          ? palette.success
                                          : palette.error,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      tr(testResult!),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: testSuccess
                                            ? palette.success
                                            : palette.error,
                                      ),
                                    ),
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
  final RouterTool routerTool;
  final VoidCallback onChooseRouterTool;
  final bool saving;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final String connectionsTabMode;
  final ValueChanged<String> onSetConnectionsMode;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  const _PreferencesPage({
    required this.routerTool,
    required this.onChooseRouterTool,
    required this.saving,
    required this.themeMode,
    required this.onThemeModeChanged,
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
    final hintColor = palette.textSecondary;

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
                      const SizedBox(height: 6),
                      Text(
                        tr('设置外观模式和连接页默认显示方式'),
                        style: TextStyle(
                          fontSize: 13,
                          color: hintColor,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PreferenceSection(
                        title: tr('外观模式'),
                        description: tr('默认跟随系统，也可以固定为浅色或深色。'),
                        child: ThemeModeSelector(
                          mode: themeMode,
                          isDark: isDark,
                          lightLabel: tr('浅色'),
                          darkLabel: tr('深色'),
                          followSystemLabel: tr('跟随系统'),
                          onChanged: onThemeModeChanged,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: palette.border, width: 0.5),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: AppSettingPickerRow(
                          title: tr('代理软件'),
                          description: tr('已根据连接自动选择，也可手动修改'),
                          picker: AppSelectionPicker(
                            key: const ValueKey('setup_router_tool'),
                            label: tr(routerTool.label),
                            tooltip: tr('选择代理软件'),
                            icon: Icons.hub_outlined,
                            compact: true,
                            onTap: saving ? null : onChooseRouterTool,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _PreferenceSection(
                        title: tr('连接页显示'),
                        description: tr('原生列表响应更快；Zashboard 面板会以移动端模式打开。'),
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
  final String description;
  final Widget child;

  const _PreferenceSection({
    required this.title,
    required this.description,
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
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(fontSize: 12, color: hintColor, height: 1.45),
          ),
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
