import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import '../../theme/app_theme.dart';
import 'dashboard_button_style.dart';

class SshTrustCard extends StatelessWidget {
  const SshTrustCard({super.key, required this.busy, required this.onReview});
  final bool busy;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const ValueKey('dashboard_ssh_trust_notice'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('SSH 设备尚未信任'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(tr('已暂停 SSH 连接。确认设备指纹后可恢复配置与快捷操作。'),
            style: TextStyle(color: palette.textSecondary, fontSize: 13)),
        const SizedBox(height: 12),
        OutlinedButton(
          style: DashboardButtonStyle.action,
          onPressed: busy ? null : onReview,
          child: Text(tr(busy ? '正在连接…' : '查看并确认 SSH 身份')),
        ),
      ]),
    );
  }
}
