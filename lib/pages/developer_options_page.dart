import '../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
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
  bool _showBall = false;
  bool _showConsoleButton = false;
  int _trustedSshHosts = 0;
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
    if (_trustedSshHosts == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('清除 SSH 信任？')),
        content: Text(tr('清除后，下次执行 YAML、快捷设置或重启操作时，需要重新确认设备指纹。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
  }

  Future<bool> _confirmWebPanelUpdate() async {
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
          : SingleChildScrollView(
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
                    SwitchListTile(
                      title: Text(
                        tr('显示主题悬浮球'),
                        style: TextStyle(fontSize: 13, color: textColor),
                      ),
                      subtitle: Text(
                        tr('屏幕上显示可拖动的深浅色切换按钮，长按拖动，点击切换'),
                        style: TextStyle(fontSize: 11, color: hintColor),
                      ),
                      value: _showBall,
                      onChanged: _toggleShowBall,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                    ),
                    Divider(height: 0, color: cardBorder),
                    SwitchListTile(
                      title: Text(tr('显示控制台按钮'),
                          style: TextStyle(fontSize: 13, color: textColor)),
                      subtitle: Text(tr('在首页左上角显示 Zashboard 控制台入口'),
                          style: TextStyle(fontSize: 11, color: hintColor)),
                      value: _showConsoleButton,
                      onChanged: _toggleShowConsoleButton,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
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
                        onPressed:
                            _trustedSshHosts == 0 ? null : _clearSshTrust,
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
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final details = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('应用语言'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tr('语言切换会立即应用，并同步内置 Zashboard 面板。'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: hintColor,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          );
                          if (constraints.maxWidth < 340) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                details,
                                const SizedBox(height: 12),
                                const Align(
                                  alignment: Alignment.centerRight,
                                  child: AppLanguagePicker(compact: true),
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: details),
                              const SizedBox(width: 12),
                              const AppLanguagePicker(compact: true),
                            ],
                          );
                        },
                      ),
                    ),
                    Divider(height: 0, color: cardBorder),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('连接 Tab 内容'),
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tr('选择底部「连接」Tab 的显示内容'),
                            style: TextStyle(fontSize: 11, color: hintColor),
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
                                onTap: () => _setConnectionsTabMode('webview'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 0, color: cardBorder),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                tr('Zashboard 面板更新'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textColor,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _webPanelVersion,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: hintColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tr('更新内置 Web 控制面板。新版可能需要重新适配代理页和连接页。'),
                            style: TextStyle(fontSize: 11, color: hintColor),
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
                                    const Icon(
                                      Icons.system_update_alt_rounded,
                                      size: 17,
                                      color: Colors.white,
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
