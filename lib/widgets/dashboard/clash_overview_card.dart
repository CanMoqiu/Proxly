import 'dashboard_card_titles.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import '../../theme/app_theme.dart';
import '../adaptive_ui.dart';
import '../../utils/traffic_formatter.dart';

class ClashOverviewCard extends StatelessWidget {
  final int activeConnections, totalDownload, totalUpload;
  final List<double> downloadSpeeds, uploadSpeeds;
  final double currentDownSpeed, currentUpSpeed;
  const ClashOverviewCard(
      {super.key,
      required this.activeConnections,
      required this.totalDownload,
      required this.totalUpload,
      required this.downloadSpeeds,
      required this.uploadSpeeds,
      required this.currentDownSpeed,
      required this.currentUpSpeed});
  String _formatBytes(int bytes) => TrafficFormatter.formatBytes(bytes);
  String _formatSpeed(double bytes) => TrafficFormatter.formatSpeed(bytes);
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final cardBg = palette.surface, cardBorder = palette.border;
    final textPrimary = palette.textPrimary,
        textSecondary = palette.textSecondary;
    final primary = Theme.of(context).colorScheme.primary;
    double maxChartSpeed = [...downloadSpeeds, ...uploadSpeeds]
        .fold(1024.0, (a, b) => a > b ? a : b);
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
            dashboardCardTitle(DashboardCardId.overview),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: tr('活跃连接'),
                  value: '$activeConnections',
                  cardBg: palette.inputBackground,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: tr('累计下载'),
                  value: _formatBytes(totalDownload),
                  valueColor: primary,
                  cardBg: palette.inputBackground,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: tr('累计上传'),
                  value: _formatBytes(totalUpload),
                  valueColor: palette.success,
                  cardBg: palette.inputBackground,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final label in [
                        _formatSpeed(maxChartSpeed),
                        _formatSpeed(maxChartSpeed * 0.75),
                        _formatSpeed(maxChartSpeed * 0.5),
                        _formatSpeed(maxChartSpeed * 0.25),
                        '0B/s',
                      ])
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 9,
                                  height: 1,
                                  color: textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: CustomPaint(
                    size: const Size(double.infinity, 100),
                    painter: _SpeedChartPainter(
                      downloadSpeeds: downloadSpeeds,
                      uploadSpeeds: uploadSpeeds,
                      gridColor: palette.border,
                      maxSpeed: maxChartSpeed,
                      primary: primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 56),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '60s',
                  style: TextStyle(fontSize: 9, color: textSecondary),
                ),
                Text(
                  '30s',
                  style: TextStyle(fontSize: 9, color: textSecondary),
                ),
                Text(
                  '0s',
                  style: TextStyle(fontSize: 9, color: textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SpeedLegend(
                color: primary,
                label: '↓ ${_formatSpeed(currentDownSpeed)}',
              ),
              const SizedBox(width: 24),
              _SpeedLegend(
                color: const Color(0xFF1D9E75),
                label: '↑ ${_formatSpeed(currentUpSpeed)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Color cardBg;
  final Color textPrimary;
  final Color textSecondary;

  const _StatCard({
    required this.label,
    required this.value,
    this.valueColor,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          AdaptiveSingleLineText(
            tr(label),
            style: TextStyle(fontSize: 10, color: textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SpeedLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _SpeedLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 2,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 4),
        Text(tr(label), style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  final List<double> downloadSpeeds;
  final List<double> uploadSpeeds;
  final Color gridColor;
  final double maxSpeed;
  final Color primary;

  _SpeedChartPainter({
    required this.downloadSpeeds,
    required this.uploadSpeeds,
    required this.gridColor,
    required this.maxSpeed,
    required this.primary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final scale = maxSpeed > 0 ? (size.height - 4) / maxSpeed : 1.0;
    final step = size.width / (downloadSpeeds.length - 1);

    void drawLine(List<double> speeds, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < speeds.length; i++) {
        final x = i * step;
        final y = size.height - (speeds[i] * scale).clamp(0, size.height - 2);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawLine(downloadSpeeds, primary);
    drawLine(uploadSpeeds, const Color(0xFF1D9E75));
  }

  @override
  bool shouldRepaint(_SpeedChartPainter old) =>
      old.gridColor != gridColor ||
      old.maxSpeed != maxSpeed ||
      old.primary != primary ||
      old.downloadSpeeds.last != downloadSpeeds.last ||
      old.uploadSpeeds.last != uploadSpeeds.last;
}
