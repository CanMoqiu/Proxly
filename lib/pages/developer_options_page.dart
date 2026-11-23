import '../widgets/app_popup.dart';
import '../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/optional_settings_visibility.dart';
import '../services/ssh_host_trust_service.dart';
import '../services/web_panel_service.dart';
import '../services/web_panel_update_session.dart';
import '../services/app_platform.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/app_feedback.dart';

class DeveloperOptionsPage extends StatefulWidget {
  const DeveloperOptionsPage({super.key});

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  bool _showOptionalSettings = false;
  bool _showBall = false;
  bool _showConsoleButton = false;
  int _trustedSshHosts = 0;
  bool _clearingSshTrust = false;
  String _connectionsTabMode = 'webview';
  String _webPanelVersion = WebPanelService.builtinVersion;
  final _panelUpdate = WebPanelUpdateSession.instance;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _panelUpdate.addListener(_handlePanelUpdate);
    _loadSettings();
  }

  void _handlePanelUpdate() {
    if (mounted) {
      setState(() {
        if (_panelUpdate.installedVersion != null) {
          _webPanelVersion = _panelUpdate.installedVersion!;
        }
      });
    }
  }

  @override
  void dispose() {
    _panelUpdate.removeListener(_handlePanelUpdate);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final webPanelVersion = await WebPanelService.getActiveVersion();
    if (mounted) {
      setState(() {
        _showOptionalSettings = OptionalSettingsVisibility.read(prefs);
        _showBall = prefs.getBool('show_floating_ball') ?? false;
        _showConsoleButton = prefs.getBool('show_console_button') ?? false;
        _connectionsTabMode =
            prefs.getString('connections_tab_mode') ?? 'webview';
        _webPanelVersion = webPanelVersion;
        _loaded = true;
      });
    }
    _loadTrustedSshHosts();
  }

  Future<void> _loadTrustedSshHosts() async {
    try {
      final count = await SshHostTrustService.instance.trustedHostCount();
      if (mounted) setState(() => _trustedSshHosts = count);
    } catch (_) {
      // Trust metadata is optional UI state and must not block this page.
    }
  }

  Future<void> _toggleShowBall(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_floating_ball', value);
    setState(() => _showBall = value);
    if (mounted) ProxlyApp.setBallVisibilityOf(context, value);
  }

  Future<void> _toggleShowConsoleButton(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_console_button', value);
    if (mounted) setState(() => _showConsoleButton = value);
  }

  Future<void> _setConnectionsTabMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('connections_tab_mode', mode);
    setState(() => _connectionsTabMode = mode);
  }

  Future<void> _clearSshTrust() async {
    if (_trustedSshHosts == 0 || _clearingSshTrust) return;
    setState(() => _clearingSshTrust = true);
    try {
      final confirmed = await AppPopup.dialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: Text(tr('清除 SSH 信任？')),
          content: Text(tr('清除后，下次执行 YAML、快捷设置或重启操作时，需要重新确认设备指纹。')),
          actions: [
            TextButton(
              onPressed: () => AppPopup.close(dialogContext, false),
              child: Text(tr('取消')),
            ),
            FilledButton(
              onPressed: () => AppPopup.close(dialogContext, true),
              child: Text(tr('清除信任')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await SshHostTrustService.instance.clearAll();
      if (!mounted) return;
      setState(() => _trustedSshHosts = 0);
      AppFeedback.showSnackBar(
        context,
        tr('SSH 信任已清除'),
        tone: AppFeedbackTone.success,
      );
    } catch (_) {
      if (mounted) {
        AppFeedback.showSnackBar(context, tr('清除 SSH 信任失败，请重试'),
            tone: AppFeedbackTone.error);
      }
    } finally {
      if (mounted) setState(() => _clearingSshTrust = false);
    }
  }

  Future<bool> _confirmWebPanelUpdate() async {
    final confirmed = await AppPopup.dialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
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
            onPressed: () => AppPopup.close(dialogContext, false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => AppPopup.close(dialogContext, true),
            child: Text(tr('继续更新')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _updateWebPanel() async {
    if (_panelUpdate.busy) return;
    if (!_panelUpdate.hasUpdate) {
      try {
        await _panelUpdate.check();
      } catch (_) {}
      return;
    }
    final confirmed =
        _panelUpdate.activationPending || await _confirmWebPanelUpdate();
    if (!confirmed || !mounted) return;
    try {
      await _panelUpdate.install();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final bgColor = palette.pageBackground;
    final cardBg = palette.surface;
    final cardBorder = palette.border;
    final dividerColor = palette.border;
    final textColor = palette.textPrimary;
    final hintColor = palette.textSecondary;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          tr('高级选项'),
          style: TextStyle(
            fontSize: 16,
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
      body: !_loaded
          ? const SizedBox.shrink()
          : AdaptiveContent(
              child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              child: Material(
                color: cardBg,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: cardBorder, width: 0.5),
                ),
                child: Column(
                  children: [
                    if (_showOptionalSettings) ...[
                      _PreferenceSwitch(
                        title: tr('显示主题悬浮球'),
                        subtitle: tr('点按切换主题，长按拖动'),
                        value: _showBall,
                        onChanged: _toggleShowBall,
                      ),
                      Divider(height: 0, color: cardBorder),
                    ],
                    _PreferenceSwitch(
                      title: tr('显示控制台按钮'),
                      value: _showConsoleButton,
                      onChanged: _toggleShowConsoleButton,
                    ),
                    Divider(height: 0, color: cardBorder),
                    ListTile(
                      title: Text(
                        tr('SSH 设备信任'),
                        style: TextStyle(fontSize: 13, color: textColor),
                      ),
                      subtitle: Text(
                        tr(_trustedSshHosts == 0
                            ? '尚未信任 SSH 设备'
                            : '已信任 $_trustedSshHosts 台 SSH 设备'),
                        style: TextStyle(fontSize: 11, color: hintColor),
                      ),
                      trailing: TextButton(
                        onPressed: _trustedSshHosts == 0 || _clearingSshTrust
                            ? null
                            : _clearSshTrust,
                        child: AdaptiveSingleLineText(tr('清除信任')),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                    ),
                    Divider(height: 0, color: cardBorder),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: AppSettingPickerRow(
                        title: tr('应用语言'),
                        picker: const AppLanguagePicker(compact: true),
                      ),
                    ),
                    Divider(height: 0, color: cardBorder),
                    if (_showOptionalSettings) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('连接 Tab 内容'),
                              style: TextStyle(fontSize: 13, color: textColor),
                            ),
                            const SizedBox(height: 12),
                            AdaptiveOptionGroup(
                              labels: [tr('原生列表'), tr('Zashboard 面板')],
                              spacing: 10,
                              children: [
                                _OptionButton(
                                  label: tr('原生列表'),
                                  icon: Icons.list_alt_rounded,
                                  selected: _connectionsTabMode == 'native',
                                  onTap: () => _setConnectionsTabMode('native'),
                                ),
                                _OptionButton(
                                  label: tr('Zashboard 面板'),
                                  icon: Icons.language_rounded,
                                  selected: _connectionsTabMode == 'webview',
                                  onTap: () =>
                                      _setConnectionsTabMode('webview'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 0, color: cardBorder),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tr('Zashboard 面板更新'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _webPanelVersion,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: hintColor,
                                ),
                              ),
                            ],
                          ),
                          if (_panelUpdate.phase ==
                                  WebPanelUpdatePhase.downloading ||
                              _panelUpdate.phase ==
                                  WebPanelUpdatePhase.installing) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _panelUpdate.progress,
                                backgroundColor: palette.inputBackground,
                                valueColor: AlwaysStoppedAnimation(primary),
                                minHeight: 6,
                              ),
                            ),
                          ],
                          if (_panelUpdate.message != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              tr(_panelUpdate.message!),
                              style: TextStyle(
                                fontSize: 12,
                                color: _panelUpdate.phase ==
                                        WebPanelUpdatePhase.failed
                                    ? palette.error
                                    : palette.success,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: _panelUpdate.busy ? null : _updateWebPanel,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: primary.withValues(
                                  alpha: _panelUpdate.busy ? 0.55 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_panelUpdate.busy)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  else
                                    SvgPicture.asset(
                                      'assets/icons/panel-update.svg',
                                      width: 18,
                                      height: 18,
                                      colorFilter: const ColorFilter.mode(
                                        Colors.white,
                                        BlendMode.srcIn,
                                      ),
                                      excludeFromSemantics: true,
                                    ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: AdaptiveSingleLineText(
                                      tr(_panelUpdate.busy
                                          ? (_panelUpdate.phase ==
                                                  WebPanelUpdatePhase.checking
                                              ? '检测中…'
                                              : '更新中')
                                          : (_panelUpdate.hasUpdate
                                              ? '更新'
                                              : '检测版本')),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )),
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final details = subtitle;
    return MergeSemantics(
      child: ListTile(
        title: Text(
          title,
          style: TextStyle(fontSize: 13, color: palette.textPrimary),
        ),
        subtitle: details == null
            ? null
            : Text(
                details,
                style: TextStyle(fontSize: 11, color: palette.textSecondary),
              ),
        trailing: Switch(value: value, onChanged: onChanged),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _OptionButton({
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
