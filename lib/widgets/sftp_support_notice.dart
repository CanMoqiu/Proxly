import 'app_popup.dart';
import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../services/sftp_support_service.dart';

/// Persistent recovery controls, separate from transient file-operation errors.
class SftpSupportNotice extends StatelessWidget {
  final SftpSupportIssue issue;
  final bool busy;
  final VoidCallback onInstall;
  final VoidCallback onRetry;

  const SftpSupportNotice(
      {super.key,
      required this.issue,
      required this.busy,
      required this.onInstall,
      required this.onRetry});

  static Future<bool> confirm(
          BuildContext context, SftpSupportIssue issue) async =>
      await AppPopup.dialog<bool>(
          context: context,
          builder: (context) => AppDialog(
                title: Text(tr('安装 SFTP 组件？')),
                content: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(issue.target.label),
                    const SizedBox(height: 12),
                    Text(tr(
                        '将在路由器上更新软件包索引并安装 openssh-sftp-server，需要路由器联网及可用存储空间。不执行全量升级或重启 Clash。')),
                    const SizedBox(height: 12),
                    SelectableText(issue.installCommand ?? ''),
                  ],
                )),
                actions: [
                  TextButton(
                      onPressed: () => AppPopup.close(context, false),
                      child: Text(tr('取消'))),
                  FilledButton(
                      onPressed: () => AppPopup.close(context, true),
                      child: Text(tr('确认安装'))),
                ],
              )) ??
      false;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(issue.message)),
                if (!issue.canInstall && !issue.installed && issue.openWrt)
                  Text(tr(
                      '自动安装需要 root 权限及 opkg 或 apk，请在路由器上手动安装 openssh-sftp-server。')),
                if (busy) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                  Text(tr('正在检查或安装 SFTP，请稍候…')),
                ],
                Wrap(spacing: 8, children: [
                  if (issue.canInstall)
                    TextButton(
                        onPressed: busy ? null : onInstall,
                        child: Text(tr('安装 SFTP 组件'))),
                  TextButton(
                      onPressed: busy ? null : onRetry,
                      child: Text(tr('重新检测'))),
                ]),
              ],
            )),
      );
}
