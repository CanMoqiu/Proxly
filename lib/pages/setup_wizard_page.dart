import '../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../main.dart';
import '../services/connection_settings_store.dart';
import '../services/clash_host_validator.dart';
import '../services/clash_service.dart';
import '../services/connection_feedback.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/app_feedback.dart';
import 'main_shell.dart';

/// 首次启动引导页：帮助新用户快速完成 Clash 连接配置。
/// 当 SharedPreferences 中 clash_host 为空时，由 main.dart 展示此页。
class SetupWizardPage extends StatefulWidget {
  const SetupWizardPage({super.key});

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
  final _hostFocusNode = FocusNode();
  bool _obscureToken = true;
  bool _obscureSshPassword = true;
  bool _testing = false;
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
  }

  @override
  void dispose() {
    _hostController.removeListener(_clearHostErrorOnInput);
    _tokenController.removeListener(_clearTestResultOnInput);
    disposeTransientFeedback();
    _hostFocusNode.dispose();
    _pageController.dispose();
    _hostController.dispose();
    _tokenController.dispose();
    _sshPasswordController.dispose();
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

  void _clearHostErrorOnInput() {
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

  void _handleConfigNext() {
    if (_hostController.text.trim().isEmpty) {
      setState(() => _hostRequiredError = true);
      _hostFocusNode.requestFocus();
      return;
    }
    _nextStep();
  }

  Future<void> _testConnection() async {
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
    try {
      final token = _tokenController.text.trim();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final response = await http
          .get(Uri.parse('http://$host/version'), headers: headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _setTestResult(
          '连接正常 · Clash ${data['version'] ?? '未知版本'}',
          success: true,
        );
      } else if (response.statusCode == 401) {
        _setTestResult('密钥验证失败，请检查后重试', success: false);
      } else {
        _setTestResult(
          '连接失败 · HTTP ${response.statusCode}',
          success: false,
        );
      }
    } catch (_) {
      _setTestResult(ConnectionFeedback.unavailable, success: false);
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
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('connections_tab_mode', _connectionsTabMode);
      await prefs.setString('theme_mode', _themeModeString(_themeMode));
      await ConnectionSettingsStore.instance.saveController(
        host: host,
        token: _tokenController.text.trim(),
        sshPassword: _sshPasswordController.text.trim(),
      );
      await ClashService.instance.loadConfig();
      if (!mounted) return;
      // 配置保存完成，替换路由栈，进入主界面
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
              showHostRequiredError: _hostRequiredError,
              obscureToken: _obscureToken,
              onToggleObscure: () =>
                  setState(() => _obscureToken = !_obscureToken),
              obscureSshPassword: _obscureSshPassword,
              onToggleSshObscure: () =>
                  setState(() => _obscureSshPassword = !_obscureSshPassword),
              testing: _testing,
              testResult: _testResult,
              testSuccess: _testSuccess,
              onTest: _testConnection,
              onBack: _previousStep,
              onNext: _handleConfigNext,
            ),
            _PreferencesPage(
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
      // 步骤指示器
      bottomNavigationBar: Container(
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
    );
  }
}

// ─── 第一步：欢迎页 ────────────────────────────────────────────────────────────

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
                            'Proxly 帮你在手机上管理 OpenClash / Mihomo，查看运行状态、流量、连接和 YAML 配置。',
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
      desc: '读取、编辑并上传 OpenClash YAML',
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

// ─── 第二步：连接配置页 ────────────────────────────────────────────────────────

class _ConfigPage extends StatelessWidget {
  final TextEditingController hostController;
  final FocusNode hostFocusNode;
  final TextEditingController tokenController;
  final TextEditingController sshPasswordController;
  final bool showHostRequiredError;
  final bool obscureToken;
  final VoidCallback onToggleObscure;
  final bool obscureSshPassword;
  final VoidCallback onToggleSshObscure;
  final bool testing;
  final String? testResult;
  final bool testSuccess;
  final VoidCallback onTest;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _ConfigPage({
    required this.hostController,
    required this.hostFocusNode,
    required this.tokenController,
    required this.sshPasswordController,
    required this.showHostRequiredError,
    required this.obscureToken,
    required this.onToggleObscure,
    required this.obscureSshPassword,
    required this.onToggleSshObscure,
    required this.testing,
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
                child: SingleChildScrollView(
                  key: const ValueKey('setup_config_scroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
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
                        // ── 地址 + 密钥输入卡片 ──────────────────────────────────────────────
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
                                  '填写 OpenClash 外部控制地址，格式为 IP:端口',
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
                                    contentPadding: const EdgeInsets.symmetric(
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
                                    contentPadding: const EdgeInsets.symmetric(
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
                                title: tr('SSH 密码（可选）'),
                                description: tr(
                                  '用于管理 YAML 配置和重启 OpenClash，未使用 SSH 可留空',
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
                                    contentPadding: const EdgeInsets.symmetric(
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
                        // ── 测试连接 ─────────────────────────────────────────────────────────
                        GestureDetector(
                          onTap: testing ? null : onTest,
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cardBorder, width: 0.5),
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
                        // ── 测试结果提示 ─────────────────────────────────────────────────────
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
              const SizedBox(height: 12),
              _WizardNavButtons(onBack: onBack, onNext: onNext),
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

// ─── 第三步：功能偏好 ────────────────────────────────────────────────────────

class _PreferencesPage extends StatelessWidget {
  final bool saving;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final String connectionsTabMode;
  final ValueChanged<String> onSetConnectionsMode;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  const _PreferencesPage({
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

// ─── 出站链路模式选择按钮 ──────────────────────────────────────────────────────

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
