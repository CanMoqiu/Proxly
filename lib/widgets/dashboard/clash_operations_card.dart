import 'dashboard_card_titles.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import '../../theme/app_theme.dart';
import 'operation_button.dart';

class ClashOperationsCard extends StatelessWidget {
  final String restartLabel;
  final bool busy, flushingDns, closingConnections;
  final VoidCallback onRestart, onFlushDns, onCloseConnections;
  const ClashOperationsCard(
      {super.key,
      required this.restartLabel,
      required this.busy,
      required this.flushingDns,
      required this.closingConnections,
      required this.onRestart,
      required this.onFlushDns,
      required this.onCloseConnections});
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final cardBg = palette.surface, cardBorder = palette.border;
    final textColor = palette.textPrimary, hintColor = palette.textSecondary;
    return Container(
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
            dashboardCardTitle(DashboardCardId.operations),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('重启 OpenClash，或维护 Clash 内核的 DNS 缓存与代理连接。'),
            style: TextStyle(fontSize: 11, color: hintColor),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: DashboardOperationButton(
              key: const ValueKey('maintenance_restart'),
              label: tr(restartLabel),
              icon: Icons.restart_alt_rounded,
              warning: true,
              loading: false,
              enabled: !busy,
              onTap: onRestart,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DashboardOperationButton(
                  key: const ValueKey('maintenance_flush_dns'),
                  label: tr(flushingDns ? '清理中' : '清理 DNS 缓存'),
                  icon: Icons.dns_rounded,
                  loading: flushingDns,
                  enabled: !busy,
                  onTap: onFlushDns,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DashboardOperationButton(
                  key: const ValueKey(
                    'maintenance_close_connections',
                  ),
                  label: tr(closingConnections ? '关闭中' : '关闭连接'),
                  icon: Icons.link_off_rounded,
                  loading: closingConnections,
                  enabled: !busy,
                  onTap: onCloseConnections,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
