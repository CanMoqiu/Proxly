import '../l10n/app_locale.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_platform.dart';
import '../services/app_version.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import 'adaptive_ui.dart';
import 'app_feedback.dart';

enum _Stage { available, downloading, done }

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  /// Whether the dialog was opened by an automatic update check.
  final bool autoTriggered;
  const UpdateDialog({
    super.key,
    required this.info,
    this.autoTriggered = false,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _Stage _stage = _Stage.available;
  double _progress = 0; // 0.0 to 1.0; -1 means indeterminate.
  final _cancelled = ValueNotifier(false);

  @override
  void dispose() {
    _cancelled.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (AppPlatform.isIOS) {
      try {
        final opened = await launchUrl(widget.info.releasePage,
            mode: LaunchMode.externalApplication);
        if (!opened) throw StateError('Browser unavailable');
        if (mounted) Navigator.of(context).pop();
      } catch (_) {
        if (!mounted) return;
        AppFeedback.showSnackBar(context, tr('无法打开链接，请检查浏览器设置'),
            tone: AppFeedbackTone.error);
      }
      return;
    }
    // Android 8+ requires the "install unknown apps" permission before opening
    // the package installer.
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        if (!mounted) return;
        _showPermissionBanner(context);
        return;
      }
    }
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
    });
    try {
      final file = await UpdateService.instance.downloadApk(
        widget.info.apkUrl,
        widget.info.tag,
        widget.info.sha256,
        (p) {
          if (mounted) setState(() => _progress = p);
        },
        _cancelled,
      );
      if (_cancelled.value || !mounted) return;
      setState(() => _stage = _Stage.done);
      Navigator.of(context).pop();
      await UpdateService.instance.installApk(file);
    } catch (e) {
      if (!mounted) return;
      if (_cancelled.value) return; // Cancellation is user-driven; do not show an error.
      AppFeedback.showSnackBar(
        context,
        tr('下载失败：$e'),
        tone: AppFeedbackTone.error,
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _skipVersion() async {
    await UpdateService.instance.skipVersion(widget.info.tag);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disableAutomaticChecks() async {
    await UpdateService.instance.setAutomaticCheckEnabled(false);
    if (!mounted) return;
    AppFeedback.showSnackBar(
      context,
      tr('更新检测已关闭，可在关于页重新开启'),
      tone: AppFeedbackTone.success,
    );
    Navigator.of(context).pop();
  }

  void _showPermissionBanner(BuildContext ctx) {
    final orange = AppPalette.of(ctx).warning;
    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogCtx, _, __) => Align(
        alignment: Alignment.topCenter,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: orange,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55F59E0B),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('请允许"安装未知应用"\n开启后重新点击更新'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      Navigator.of(dialogCtx).pop();
                      // Open this app's dedicated "install unknown apps" settings page.
                      await Permission.requestInstallPackages.request();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: AdaptiveSingleLineText(
                      tr('去开启'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }

  void _cancel() {
    if (_stage == _Stage.downloading) {
      _cancelled.value = true;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final bgColor = palette.surface;
    final textColor = palette.textPrimary;
    final hintColor = palette.textSecondary;
    final primary = Theme.of(context).colorScheme.primary;

    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        tr(
          _stage == _Stage.available
              ? '发现新版本 ${displayAppVersion(widget.info.tag)}'
              : '正在下载 ${displayAppVersion(widget.info.tag)}',
        ),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      // Leave enough space around the dialog for the release notes to remain readable.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      // Keep the content area tall enough for the release notes and actions.
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: _stage == _Stage.available
          ? _AvailableContent(
              body: widget.info.body,
              hintColor: hintColor,
              textColor: textColor,
            )
          : _DownloadingContent(progress: _progress, hintColor: hintColor),
      actions: _stage == _Stage.available
          ? [
              if (widget.autoTriggered) ...[
                TextButton(
                  onPressed: _disableAutomaticChecks,
                  child: AdaptiveSingleLineText(
                    tr('关闭更新检测'),
                    style: TextStyle(fontSize: 13, color: hintColor),
                  ),
                ),
                TextButton(
                  onPressed: _skipVersion,
                  child: AdaptiveSingleLineText(
                    tr('跳过此版本'),
                    style: TextStyle(fontSize: 13, color: hintColor),
                  ),
                ),
              ] else
                TextButton(
                  onPressed: _cancel,
                  child: AdaptiveSingleLineText(
                    tr('取消'),
                    style: TextStyle(fontSize: 13, color: hintColor),
                  ),
                ),
              TextButton(
                onPressed: _startDownload,
                child: AdaptiveSingleLineText(
                  tr('立即更新'),
                  style: TextStyle(fontSize: 13, color: primary),
                ),
              ),
            ]
          : [
              TextButton(
                onPressed: _cancel,
                child: AdaptiveSingleLineText(
                  tr('取消'),
                  style: TextStyle(fontSize: 13, color: hintColor),
                ),
              ),
            ],
    );
  }
}

class _AvailableContent extends StatelessWidget {
  final String? body;
  final Color hintColor;
  final Color textColor;
  const _AvailableContent({
    this.body,
    required this.hintColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    if (body == null || body!.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          tr(AppPlatform.isIOS ? '前往 GitHub 发布页下载 IPA，自签后手动安装。' : '是否立即下载并安装？'),
          style: TextStyle(fontSize: 13, color: hintColor),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);

    // Match Markdown rendering to the app theme.
    final mdStyle = MarkdownStyleSheet(
      p: TextStyle(fontSize: 13, color: hintColor, height: 1.5),
      h1: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
      h2: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
      h3: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      strong: TextStyle(fontWeight: FontWeight.w600, color: textColor),
      em: TextStyle(fontStyle: FontStyle.italic, color: hintColor),
      code: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        color: isDark ? const Color(0xFFCE9178) : const Color(0xFFAF4B4B),
        backgroundColor:
            isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF3F3F3),
      ),
      codeblockDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(6),
      ),
      listBullet: TextStyle(fontSize: 13, color: hintColor),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: palette.textDisabled,
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      blockquote: TextStyle(
        fontSize: 13,
        color: hintColor,
        fontStyle: FontStyle.italic,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: hintColor.withValues(alpha: 0.3), width: 1),
        ),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        // Limit the notes to half the screen so the action buttons remain visible.
        maxHeight: MediaQuery.of(context).size.height * 0.50,
      ),
      child: Markdown(
        data: body!.trim(),
        styleSheet: mdStyle,
        // Let Markdown use its own scroll view instead of measuring the full document.
        shrinkWrap: false,
        padding: const EdgeInsets.only(bottom: 12),
        // Keep links inert here so accidental taps cannot leave the update dialog.
        onTapLink: (_, __, ___) {},
      ),
    );
  }
}

class _DownloadingContent extends StatelessWidget {
  final double progress;
  final Color hintColor;
  const _DownloadingContent({required this.progress, required this.hintColor});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final known = progress >= 0;
    final pct = known ? '${(progress * 100).toInt()}%' : '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: known ? progress : null,
          backgroundColor: hintColor.withValues(alpha: 0.2),
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
        if (known) ...[
          const SizedBox(height: 8),
          Text(pct, style: TextStyle(fontSize: 12, color: hintColor)),
        ],
      ],
    );
  }
}
