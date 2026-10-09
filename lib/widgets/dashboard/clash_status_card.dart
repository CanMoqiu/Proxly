import 'dashboard_card_titles.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import '../../theme/app_theme.dart';

class ClashStatusCard extends StatelessWidget {
  final bool loading, online, restartBusy, restartFailed;
  final String? error;
  final String coreVersion;
  final VoidCallback onRetry;
  const ClashStatusCard(
      {super.key,
      required this.loading,
      required this.online,
      required this.restartBusy,
      required this.restartFailed,
      required this.error,
      required this.coreVersion,
      required this.onRetry});
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final cardBg = palette.surface, cardBorder = palette.border;
    final textPrimary = palette.textPrimary,
        textSecondary = palette.textSecondary;
    final statusColor = restartBusy
        ? palette.warning
        : restartFailed
            ? palette.error
            : online
                ? palette.success
                : textSecondary;
    final statusLabel = restartBusy
        ? '重启中'
        : restartFailed
            ? '重启失败'
            : online
                ? '运行中'
                : '未连接';
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(
                dashboardCardTitle(DashboardCardId.status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              )),
              const SizedBox(width: 8),
              Flexible(
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Flexible(
                    child: Text(
                  tr(statusLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: restartBusy || restartFailed || online
                        ? statusColor
                        : textSecondary,
                  ),
                )),
              ])),
            ],
          ),
          if (loading && !restartBusy) const LinearProgressIndicator(),
          if (error != null && !restartBusy && !restartFailed) ...[
            const SizedBox(height: 8),
            Text(tr(error!),
                style: TextStyle(fontSize: 12, color: textSecondary)),
            TextButton(onPressed: onRetry, child: Text(tr('重试'))),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                tr('内核版本'),
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.inputBackground,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    coreVersion,
                    style: TextStyle(
                      fontSize: 11,
                      color: textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
