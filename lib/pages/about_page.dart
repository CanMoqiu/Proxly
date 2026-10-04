import '../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../services/app_platform.dart';
import '../services/app_licenses.dart';
import '../services/app_version.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/app_feedback.dart';
import '../widgets/update_dialog.dart';

enum _UpdateState { idle, checking, upToDate, available, failed }

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _appName = 'Proxly';
  static const _description = 'Proxly 是一款专为 OpenClash / Mihomo 设计的监控面板，'
      '让你在手机上实时掌握代理状态、流量用量与连接详情，无需打开浏览器。';
  static const _githubRepo = 'CanMoqiu/proxly';
  static const _mitLicenseEnglish = '''Copyright (c) 2026 CanMoqiu

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.''';
  static const _mitLicenseChinese = '''版权所有 (c) 2026 CanMoqiu

任何获得本软件及相关文档文件（以下简称“软件”）副本的人，均可免费且不受限制地使用本软件，包括但不限于使用、复制、修改、合并、发布、分发、再许可和/或销售本软件副本，并可允许获授本软件的人行使上述权利，但须符合以下条件：

上述版权声明和本许可声明应包含在本软件的所有副本或重要部分中。

本软件按“原样”提供，不提供任何明示或默示的保证，包括但不限于适销性、特定用途适用性及非侵权性的保证。无论责任源于合同、侵权行为或其他原因，作者或版权持有人均不对因本软件、本软件的使用或其他交易而产生、引起或与之相关的任何索赔、损害或其他责任承担责任。''';

  String _version = '';
  bool _metadataFailed = false;
  String get _platform => AppPlatform.isIOS
      ? 'iOS'
      : AppPlatform.supportsApkUpdates
          ? 'Android'
          : defaultTargetPlatform.name;
  String get _displayVersion => displayAppVersion(_version);
  _UpdateState _updateState = _UpdateState.idle;
  UpdateInfo? _latestInfo;
  bool? _automaticCheckEnabled;
  bool _changingAutomaticCheck = false;

  @override
  void initState() {
    super.initState();
    UpdateService.instance.availableUpdate.addListener(_handleAvailableUpdate);
    _handleAvailableUpdate();
    _loadVersion();
    if (AppPlatform.supportsUpdateChecks) _loadAutomaticCheckPreference();
  }

  void _handleAvailableUpdate() {
    if (!mounted) return;
    if (!AppPlatform.supportsUpdateChecks) return;
    final info = UpdateService.instance.availableUpdate.value;
    setState(() {
      _latestInfo = info;
      if (info != null) _updateState = _UpdateState.available;
    });
  }

  @override
  void dispose() {
    UpdateService.instance.availableUpdate
        .removeListener(_handleAvailableUpdate);
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _metadataFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _metadataFailed = true);
    }
  }

  void _showLicenses() {
    AppLicenses.register();
    showLicensePage(
      context: context,
      applicationName: _appName,
      applicationVersion: _displayVersion,
      applicationLegalese: '© 2026 CanMoqiu',
    );
  }

  Future<void> _loadAutomaticCheckPreference() async {
    try {
      final enabled = await UpdateService.instance.isAutomaticCheckEnabled();
      if (mounted) setState(() => _automaticCheckEnabled = enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _automaticCheckEnabled = true);
      AppFeedback.showSnackBar(
        context,
        tr('读取更新检测设置失败'),
        tone: AppFeedbackTone.error,
      );
    }
  }

  Future<void> _setAutomaticCheckEnabled(bool enabled) async {
    if (_changingAutomaticCheck || _automaticCheckEnabled == null) return;
    final previous = _automaticCheckEnabled;
    setState(() {
      _automaticCheckEnabled = enabled;
      _changingAutomaticCheck = true;
    });
    try {
      await UpdateService.instance.setAutomaticCheckEnabled(enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _automaticCheckEnabled = previous);
      AppFeedback.showSnackBar(
        context,
        tr('保存更新检测设置失败'),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) setState(() => _changingAutomaticCheck = false);
    }
  }

  Future<void> _checkUpdate() async {
    if (_updateState == _UpdateState.checking) return;
    setState(() => _updateState = _UpdateState.checking);
    try {
      final info = await UpdateService.instance.checkForUpdate(silent: false);
      if (!mounted) return;
      if (info == null) {
        setState(() => _updateState = _UpdateState.upToDate);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _updateState = _UpdateState.idle);
        });
      } else {
        setState(() {
          _latestInfo = info;
          _updateState = _UpdateState.available;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _updateState = _UpdateState.failed);
      AppFeedback.showSnackBar(
        context,
        tr(error.toString()),
        tone: AppFeedbackTone.error,
      );
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      if (await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // A missing browser should produce actionable feedback, not a silent tap.
    }
    if (!mounted) return;
    AppFeedback.showSnackBar(context, tr('无法打开链接，请检查浏览器设置'),
        tone: AppFeedbackTone.error);
  }

  Widget _buildUpdateButton(Color hintColor) {
    final blue = Theme.of(context).colorScheme.primary;
    final red = AppPalette.of(context).error;

    Widget pill({
      required Color borderColor,
      Color? fillColor,
      required Widget child,
      VoidCallback? onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: child,
        ),
      );
    }

    Widget row(List<Widget> children) =>
        Row(mainAxisSize: MainAxisSize.min, children: children);

    switch (_updateState) {
      case _UpdateState.idle:
        return pill(
          borderColor: blue,
          onTap: _checkUpdate,
          child: AdaptiveSingleLineText(tr('检测版本'),
              style: TextStyle(fontSize: 13, color: blue)),
        );
      case _UpdateState.checking:
        return pill(
          borderColor: hintColor,
          child: row([
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: hintColor,
              ),
            ),
            const SizedBox(width: 6),
            AdaptiveSingleLineText(
              tr('检查中…'),
              style: TextStyle(fontSize: 13, color: hintColor),
            ),
          ]),
        );
      case _UpdateState.upToDate:
        return pill(
          borderColor: hintColor,
          child: row([
            Icon(Icons.check_rounded, size: 14, color: hintColor),
            const SizedBox(width: 4),
            AdaptiveSingleLineText(
              tr('无更新'),
              style: TextStyle(fontSize: 13, color: hintColor),
            ),
          ]),
        );
      case _UpdateState.available:
        return pill(
          borderColor: blue,
          fillColor: blue,
          onTap: () {
            if (_latestInfo == null) return;
            showDialog(
              context: context,
              builder: (_) => UpdateDialog(info: _latestInfo!),
            );
          },
          child: row([
            const Icon(
              Icons.system_update_rounded,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            AdaptiveSingleLineText(tr('更新'),
                style: const TextStyle(fontSize: 13, color: Colors.white)),
          ]),
        );
      case _UpdateState.failed:
        return pill(
          borderColor: red,
          onTap: _checkUpdate,
          child: AdaptiveSingleLineText(
            tr('检查失败，重试'),
            style: TextStyle(fontSize: 13, color: red),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLanguage = AppLocaleScope.watch(context).language;
    final showChineseLicense = appLanguage == AppLanguage.simplifiedChinese;
    final palette = AppPalette.of(context);
    final bgColor = palette.pageBackground;
    final cardBg = palette.surface;
    final cardBorder = palette.border;
    final textColor = palette.textPrimary;
    final hintColor = palette.textSecondary;
    final dividerColor = palette.border;

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
          tr('关于'),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
        children: [
          // ── App 标识 ──
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/app_icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _appName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                if (_metadataFailed)
                  TextButton.icon(
                    onPressed: _loadVersion,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(tr('版本信息读取失败，重试')),
                  )
                else
                  Text(
                    _version.isEmpty
                        ? tr('读取中…')
                        : '${tr('版本')} $_displayVersion',
                    key: const ValueKey('about_version'),
                    style: TextStyle(fontSize: 13, color: hintColor),
                  ),
                const SizedBox(height: 8),
                Text(
                  '$_platform · ${isTestAppVersion(_version) ? tr('测试版') : tr('正式版')}',
                  style: TextStyle(fontSize: 11, color: hintColor),
                ),
                const SizedBox(height: 12),
                if (AppPlatform.supportsUpdateChecks) ...[
                  _buildUpdateButton(hintColor),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tr('更新检测'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 52,
                        height: 34,
                        child: _automaticCheckEnabled == null
                            ? Center(
                                child: SizedBox(
                                  key: const ValueKey(
                                    'about_automatic_update_loading',
                                  ),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: hintColor,
                                  ),
                                ),
                              )
                            : Switch.adaptive(
                                key: const ValueKey(
                                  'about_automatic_update_switch',
                                ),
                                activeTrackColor:
                                    Theme.of(context).colorScheme.primary,
                                value: _automaticCheckEnabled!,
                                onChanged: _changingAutomaticCheck
                                    ? null
                                    : _setAutomaticCheckEnabled,
                              ),
                      ),
                    ],
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      tr('关闭后不再自动检测新版本，仍可在关于页手动检查更新。'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: hintColor),
                    ),
                  ),
                ],
                if (AppPlatform.isIOS)
                  Text(
                    tr('前往 GitHub 发布页下载 IPA，自签后手动安装。'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: hintColor),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    tr(_description),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: hintColor,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── 链接 ──
          _SectionTitle('使用与支持', textColor),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder, width: 0.5),
              ),
              child: Column(
                children: [
                  _LinkRow(
                    icon: Icons.menu_book_outlined,
                    title: tr('功能介绍'),
                    subtitle: tr('在 GitHub 查看完整功能说明'),
                    textColor: textColor,
                    hintColor: hintColor,
                    dividerColor: dividerColor,
                    onTap: () => _openUrl(
                      'https://github.com/$_githubRepo#readme',
                    ),
                    isLast: false,
                  ),
                  _LinkRow(
                    icon: Icons.history_rounded,
                    title: tr('更新日志'),
                    subtitle: tr('在 GitHub Releases 查看所有版本'),
                    textColor: textColor,
                    hintColor: hintColor,
                    dividerColor: dividerColor,
                    onTap: () => _openUrl(
                      'https://github.com/$_githubRepo/releases',
                    ),
                    isLast: false,
                  ),
                  if (AppPlatform.isIOS)
                    _LinkRow(
                      icon: Icons.install_mobile_rounded,
                      title: tr('iOS 安装与更新'),
                      subtitle: tr('下载 IPA、自签安装和覆盖更新说明'),
                      textColor: textColor,
                      hintColor: hintColor,
                      dividerColor: dividerColor,
                      onTap: () => _openUrl(
                        'https://github.com/$_githubRepo/blob/main/docs/ios-selfsign.zh-CN.md',
                      ),
                      isLast: false,
                    ),
                  _LinkRow(
                    icon: Icons.bug_report_outlined,
                    title: tr('问题反馈'),
                    subtitle: tr('请附版本信息、复现步骤和已脱敏的截图'),
                    textColor: textColor,
                    hintColor: hintColor,
                    dividerColor: dividerColor,
                    onTap: () => _openUrl(
                      'https://github.com/$_githubRepo/issues',
                    ),
                    isLast: false,
                  ),
                  _LinkRow(
                    icon: Icons.code_rounded,
                    title: tr('项目源码'),
                    subtitle: _githubRepo,
                    textColor: textColor,
                    hintColor: hintColor,
                    dividerColor: dividerColor,
                    onTap: () => _openUrl('https://github.com/$_githubRepo'),
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── 开源协议 ──
          _SectionTitle('开源协议', textColor),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 0.5),
            ),
            child: ExpansionTile(
              key: const ValueKey('about_mit_license'),
              title: Text('MIT License',
                  style: TextStyle(fontSize: 13, color: textColor)),
              subtitle: Text(tr('Proxly 的使用与分发许可'),
                  style: TextStyle(fontSize: 11, color: hintColor)),
              shape: const Border(),
              collapsedShape: const Border(),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectionArea(
                      child: Text(
                        _mitLicenseEnglish,
                        key: const ValueKey('about_mit_license_english'),
                        style: TextStyle(
                          fontSize: 12,
                          color: hintColor,
                          height: 1.65,
                        ),
                      ),
                    ),
                    if (showChineseLicense) ...[
                      const SizedBox(height: 16),
                      Divider(color: cardBorder, height: 1),
                      const SizedBox(height: 16),
                      Text(
                        '中文译文',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SelectionArea(
                        child: Text(
                          _mitLicenseChinese,
                          key: const ValueKey('about_mit_license_chinese'),
                          style: TextStyle(
                            fontSize: 12,
                            color: hintColor,
                            height: 1.65,
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 第三方依赖 ──
          _SectionTitle('开源致谢', textColor),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 0.5),
            ),
            child: Column(
              children: [
                _LinkRow(
                  icon: Icons.dashboard_outlined,
                  title: 'Zashboard',
                  subtitle: 'Zephyruso · MIT',
                  textColor: textColor,
                  hintColor: hintColor,
                  dividerColor: dividerColor,
                  onTap: () =>
                      _openUrl('https://github.com/Zephyruso/zashboard'),
                  isLast: false,
                ),
                _LinkRow(
                  icon: Icons.article_outlined,
                  title: tr('第三方许可证'),
                  subtitle: tr('Flutter、依赖库、JetBrains Mono 与旗帜字体'),
                  textColor: textColor,
                  hintColor: hintColor,
                  dividerColor: dividerColor,
                  onTap: _showLicenses,
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── 底部声明 ──
          Center(
            child: Text(
              tr('Proxly 与 Clash / OpenClash / Mihomo 项目无官方关联'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: hintColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 小组件 ────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionTitle(this.text, this.color);

  @override
  Widget build(BuildContext context) => Text(
        tr(text),
        style:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
      );
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color hintColor;
  final Color dividerColor;
  final VoidCallback onTap;
  final bool isLast;

  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.textColor,
    required this.hintColor,
    required this.dividerColor,
    required this.onTap,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
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
                    size: 17,
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
                      const SizedBox(height: 1),
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
        ),
        if (!isLast)
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 16,
            endIndent: 16,
            color: dividerColor,
          ),
      ],
    );
  }
}
