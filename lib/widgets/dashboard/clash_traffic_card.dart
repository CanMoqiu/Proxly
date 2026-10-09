import 'dashboard_card_titles.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import '../../theme/app_theme.dart';
import '../adaptive_ui.dart';
import '../../services/clash_service.dart';
import '../../utils/traffic_formatter.dart';

class ClashTrafficCard extends StatelessWidget {
  final List<ProviderTraffic> providers;
  const ClashTrafficCard({super.key, required this.providers});
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final cardBg = palette.surface, cardBorder = palette.border;
    final textPrimary = palette.textPrimary,
        textSecondary = palette.textSecondary;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dashboardCardTitle(DashboardCardId.traffic),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (providers.isEmpty)
            Text(tr('暂无订阅流量'),
                style: TextStyle(color: textSecondary, fontSize: 12)),
          ...providers.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final trafficLabel = formatHomeProviderTrafficLabel(p);

            final Color barColor;
            barColor = switch (p.remainingLevel) {
              ProviderTrafficLevel.healthy => palette.success,
              ProviderTrafficLevel.warning => palette.warning,
              ProviderTrafficLevel.critical => palette.error,
            };

            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HomeSubscriptionTrafficRow(
                        name: p.name,
                        trafficLabel: trafficLabel,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: p.remainingPercentage,
                          backgroundColor: palette.inputBackground,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            barColor,
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < providers.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                    ),
                    child: Divider(
                      color: palette.border,
                      height: 1,
                      thickness: 0.5,
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

String formatHomeProviderTrafficLabel(ProviderTraffic provider) {
  if (provider.isUnlimited) {
    return '${TrafficFormatter.formatBytes(provider.used)} / ${tr('无限制')}';
  }
  return '${TrafficFormatter.formatBytes(provider.remaining)} / '
      '${TrafficFormatter.formatBytes(provider.total)}';
}

class HomeSubscriptionTrafficRow extends StatelessWidget {
  final String name;
  final String trafficLabel;
  final Color textPrimary;
  final Color textSecondary;

  const HomeSubscriptionTrafficRow({
    super.key,
    required this.name,
    required this.trafficLabel,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AdaptiveMarqueeText(
            name,
            style: TextStyle(fontSize: 12, color: textPrimary),
            gap: 32,
            startDelay: const Duration(seconds: 3),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          trafficLabel,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 11, color: textSecondary),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ],
    );
  }
}
