import 'dashboard_card_titles.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import '../../theme/app_theme.dart';
import '../adaptive_ui.dart';
import '../../services/clash_config_file_service.dart';
import 'operation_button.dart';

class CurrentYamlCard extends StatelessWidget {
  final ClashActiveConfig? activeConfig;
  final bool loading;
  final bool switching;
  final bool operationBusy;
  final String? message;
  final bool messageIsError;
  final Color cardBg;
  final Color cardBorder;
  final Color textColor;
  final Color hintColor;
  final VoidCallback onRefresh;
  final VoidCallback onSwitch;
  final VoidCallback onEdit;

  const CurrentYamlCard({
    super.key,
    required this.activeConfig,
    required this.loading,
    required this.switching,
    required this.operationBusy,
    required this.message,
    required this.messageIsError,
    required this.cardBg,
    required this.cardBorder,
    required this.textColor,
    required this.hintColor,
    required this.onRefresh,
    required this.onSwitch,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Expanded(
                child: AdaptiveSingleLineText(
                  dashboardCardTitle(DashboardCardId.currentYaml),
                  alignment: Alignment.centerLeft,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('刷新当前配置'),
                visualDensity: VisualDensity.compact,
                onPressed: loading || operationBusy ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.refresh_rounded, size: 20, color: hintColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                activeConfig?.usesYaml == true
                    ? Icons.description_outlined
                    : Icons.link_off_rounded,
                size: 20,
                color: hintColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        loading
                            ? '正在读取...'
                            : (activeConfig?.displayText ?? '尚未读取'),
                      ),
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(activeConfig?.detailText ?? '读取 OpenClash 当前使用的配置来源'),
                      style: TextStyle(fontSize: 11, color: hintColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              tr(message!),
              style: TextStyle(
                fontSize: 12,
                color: messageIsError
                    ? AppPalette.of(context).error
                    : AppPalette.of(context).success,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: DashboardOperationButton(
              key: const ValueKey('current_config_switch'),
              label: tr(switching ? '处理中' : '切换配置'),
              icon: Icons.swap_horiz_rounded,
              loading: switching,
              enabled: !operationBusy && !loading,
              onTap: onSwitch,
            )),
            const SizedBox(width: 10),
            Expanded(
                child: OutlinedButton.icon(
              key: const ValueKey('current_config_edit'),
              onPressed: operationBusy || loading ? null : onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: AdaptiveSingleLineText(tr('编辑配置')),
            ))
          ]),
        ],
      ),
    );
  }
}
