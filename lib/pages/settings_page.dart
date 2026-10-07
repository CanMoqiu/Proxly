import '../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/clash_data_hub.dart';
import '../services/connection_settings_store.dart';
import '../services/clash_host_validator.dart';
import '../services/clash_service.dart';
import '../services/connection_feedback.dart';
import '../services/web_panel_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/app_feedback.dart';
import 'about_page.dart';
import 'developer_options_page.dart';
import '../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TransientFeedbackStateMixin<SettingsPage> {
  final _hostController = TextEditingController();
  final _tokenController = TextEditingController();
  final _sshPasswordController = TextEditingController();
  bool _obscureToken = true;
  bool _obscureSshPassword = true;
  bool _testing = false;
  bool _saving = false;
  bool _updatingControllerValues = false;
  bool _settingsLoadFailed = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    ConnectionSettingsStore.instance.addListener(_loadSettings);
    _hostController.addListener(_clearTestResultOnInput);
    _tokenController.addListener(_clearTestResultOnInput);
    _loadSettings();
  }

  void _clearTestResultOnInput() {
    if (_updatingControllerValues) return;
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

  Future<void> _loadSettings() async {
    try {
      final settings = await ConnectionSettingsStore.instance.load();
      if (mounted) {
        cancelFeedbackClear('connection_test');
        setState(() {
          _settingsLoadFailed = false;
          _updatingControllerValues = true;
          _hostController.text = settings.host;
          _tokenController.text = settings.token;
          _sshPasswordController.text = settings.sshPassword;
          _updatingControllerValues = false;
          _testResult = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _settingsLoadFailed = true);
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    ProxlyApp.setThemeModeOf(context, mode); // Update shared state and rebuild the app.
    if (mounted) setState(() {}); // Refresh the switch and theme button immediately.
    final prefs = await SharedPreferences.getInstance();
    final str = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';
    await prefs.setString('theme_mode', str);
  }

  Future<void> _saveSettings() async {
    if (_settingsLoadFailed) {
      await _loadSettings();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final host = ClashHostValidator.normalizeAddress(_hostController.text);
    if (host.isEmpty) {
      AppFeedback.showSnackBar(
        context,
        tr('请先填写 OpenClash 地址'),
        tone: AppFeedbackTone.error,
      );
      return;
    }
    final hostError = ClashHostValidator.validationError(host);
    if (hostError != null) {
      AppFeedback.showSnackBar(
        context,
        hostError,
        tone: AppFeedbackTone.error,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ConnectionSettingsStore.instance.saveController(
        host: host,
        token: _tokenController.text.trim(),
        sshPassword: _sshPasswordController.text,
      );
      await ClashService.instance.loadConfig();
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
    final host = ClashHostValidator.normalizeAddress(_hostController.text);
    if (host.isEmpty) {
      _setTestResult('请先填写 Clash 控制器地址', success: false);
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
          '连接成功 · Clash ${data['version'] ?? '未知版本'}',
          success: true,
        );
      } else if (response.statusCode == 401) {
        _setTestResult('密钥错误，请检查后重试', success: false);
      } else {
        _setTestResult(
          '连接失败 · 状态码 ${response.statusCode}',
          success: false,
        );
      }
    } catch (e) {
      _setTestResult(ConnectionFeedback.unavailable, success: false);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    ConnectionSettingsStore.instance.removeListener(_loadSettings);
    _hostController.removeListener(_clearTestResultOnInput);
    _tokenController.removeListener(_clearTestResultOnInput);
    disposeTransientFeedback();
    _hostController.dispose();
    _tokenController.dispose();
    _sshPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        child: SingleChildScrollView(
          padding: AdaptiveScrollPadding.page(context, top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Appearance and theme settings.
              // Connection settings.
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
                    if (_settingsLoadFailed) ...[
                      Text(tr('凭据暂时不可用，请解锁设备后重试。已保存的配置未被删除。')),
                      TextButton(
                          onPressed: _loadSettings, child: Text(tr('重试'))),
                    ],
                    LabeledInputField(
                      title: tr('OpenClash 地址'),
                      description: tr('填写 OpenClash 外部控制地址，格式为 IP:端口'),
                      titleColor: textColor,
                      descriptionColor: labelColor,
                      child: TextField(
                        controller: _hostController,
                        style: TextStyle(fontSize: 14, color: textColor),
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
                          enabledBorder: inputBorder,
                          focusedBorder: focusedBorder,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LabeledInputField(
                      title: tr('外部控制密钥（可选）'),
                      description: tr('用于访问已设置密钥的控制器，未设置可留空'),
                      titleColor: textColor,
                      descriptionColor: labelColor,
                      child: TextField(
                        controller: _tokenController,
                        obscureText: _obscureToken,
                        style: TextStyle(fontSize: 14, color: textColor),
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
                              _obscureToken
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: hintColor,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscureToken = !_obscureToken),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LabeledInputField(
                      title: tr('SSH 密码（可选）'),
                      description: tr('用于管理 YAML 配置和重启 OpenClash，未使用 SSH 可留空'),
                      titleColor: textColor,
                      descriptionColor: labelColor,
                      child: TextField(
                        controller: _sshPasswordController,
                        obscureText: _obscureSshPassword,
                        style: TextStyle(fontSize: 14, color: textColor),
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
                              _obscureSshPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: hintColor,
                              size: 20,
                            ),
                            onPressed: () => setState(
                              () => _obscureSshPassword = !_obscureSshPassword,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Keep the test result inside the connection card.
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _testSuccess
                                  ? palette.success
                                  : palette.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tr(_testResult!),
                              style: TextStyle(
                                fontSize: 12,
                                color: _testSuccess
                                    ? palette.success
                                    : palette.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Connection actions.
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _testing ? null : _testConnection,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: primary, width: 0.8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: _testing
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: primary,
                                        ),
                                      )
                                    : AdaptiveSingleLineText(
                                        tr('测试连接'),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: primary,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: _saving ? null : _saveSettings,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : AdaptiveSingleLineText(
                                        tr('保存'),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                subtitle: tr('调试与实验性功能'),
                cardBg: cardBg,
                cardBorder: cardBorder,
                textColor: textColor,
                hintColor: hintColor,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DeveloperOptionsPage(),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // About
              _NavRow(
                icon: Icons.info_outline_rounded,
                title: tr('关于 Proxly'),
                subtitle: tr('功能介绍、版本日志、开源协议'),
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
    );
  }
}

// Shared navigation row

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color cardBg;
  final Color cardBorder;
  final Color textColor;
  final Color hintColor;
  final VoidCallback onTap;

  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
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
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(title),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr(subtitle),
                    style: TextStyle(fontSize: 11, color: hintColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: hintColor),
          ],
        ),
      ),
    );
  }
}
