import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_locale.dart';
import '../services/app_platform.dart';
import '../services/app_version.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import 'app_popup.dart';
import 'app_feedback.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final bool autoTriggered;
  const UpdateDialog(
      {super.key, required this.info, this.autoTriggered = false});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _busy = false;
  bool _downloading = false;
  bool _permissionRequired = false;
  double _progress = 0;
  String? _error;
  final _cancelled = ValueNotifier(false);

  @override
  void dispose() {
    // Barrier taps and system back must cancel the download too.
    _cancelled.value = true;
    _cancelled.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = tr('操作失败，请重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startDownload() => _perform(() async {
        if (AppPlatform.isIOS) {
          try {
            final opened = await launchUrl(widget.info.releasePage,
                mode: LaunchMode.externalApplication);
            if (!opened) throw StateError('Browser unavailable');
            if (mounted && !_cancelled.value) AppPopup.close(context);
          } catch (_) {
            if (mounted) setState(() => _error = tr('无法打开链接，请检查浏览器设置'));
          }
          return;
        }
        if (Platform.isAndroid) {
          final status = await Permission.requestInstallPackages.status;
          if (!mounted || _cancelled.value) return;
          if (!status.isGranted) {
            setState(() => _permissionRequired = true);
            return;
          }
        }
        if (!mounted || _cancelled.value) return;
        setState(() {
          _downloading = true;
          _permissionRequired = false;
          _progress = 0;
        });
        try {
          final file = await UpdateService.instance.downloadApk(
              widget.info.apkUrl, widget.info.tag, widget.info.sha256,
              (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          }, _cancelled);
          if (_cancelled.value || !mounted) return;
          await UpdateService.instance.installApk(file);
          if (mounted && !_cancelled.value) AppPopup.close(context);
        } catch (error) {
          if (mounted && !_cancelled.value) {
            setState(() {
              _downloading = false;
              _error = tr('下载失败：$error');
            });
          }
        }
      });

  Future<void> _skipVersion() => _perform(() async {
        await UpdateService.instance.skipVersion(widget.info.tag);
        if (mounted && !_cancelled.value) AppPopup.close(context);
      });

  Future<void> _disableAutomaticChecks() => _perform(() async {
        await UpdateService.instance.setAutomaticCheckEnabled(false);
        if (!mounted || _cancelled.value) return;
        AppFeedback.showSnackBar(context, tr('更新检测已关闭，可在关于页重新开启'),
            tone: AppFeedbackTone.success);
        AppPopup.close(context);
      });

  void _cancel() {
    _cancelled.value = true;
    AppPopup.close(context);
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    return PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) _cancelled.value = true;
        },
        child: AppDialog(
          title: Text(tr(_downloading
              ? '正在下载 ${displayAppVersion(widget.info.tag)}'
              : '发现新版本 ${displayAppVersion(widget.info.tag)}')),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_downloading)
                  _DownloadingContent(
                      progress: _progress, hintColor: palette.textSecondary)
                else
                  _AvailableContent(
                      body: widget.info.body,
                      hintColor: palette.textSecondary,
                      textColor: palette.textPrimary),
                if (_permissionRequired) ...[
                  Text(tr('请允许"安装未知应用"\n开启后重新点击更新')),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => _perform(() async {
                                await Permission.requestInstallPackages
                                    .request();
                              }),
                      child: Text(tr('去开启'))),
                ],
                if (_error != null)
                  Text(_error!, style: TextStyle(color: palette.error)),
                if (_busy && !_downloading) const LinearProgressIndicator(),
              ]),
          actions: _downloading
              ? [
                  TextButton(onPressed: _cancel, child: Text(tr('取消下载'))),
                ]
              : [
                  if (widget.autoTriggered) ...[
                    TextButton(
                        onPressed: _busy ? null : _disableAutomaticChecks,
                        child: Text(tr('关闭更新检测'))),
                    TextButton(
                        onPressed: _busy ? null : _skipVersion,
                        child: Text(tr('跳过此版本'))),
                  ] else
                    TextButton(onPressed: _cancel, child: Text(tr('取消'))),
                  FilledButton(
                      onPressed: _busy ? null : _startDownload,
                      child: Text(tr(AppPlatform.isIOS ? '前往发布页' : '立即更新'))),
                ],
        ));
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

    return MarkdownBody(
      data: body!.trim(),
      styleSheet: mdStyle,
      onTapLink: (_, __, ___) {},
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
