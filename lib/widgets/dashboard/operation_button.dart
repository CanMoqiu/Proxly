import 'package:flutter/material.dart';
import '../adaptive_ui.dart';

class DashboardOperationButton extends StatelessWidget {
  static const _warningFill = Color(0xFFD97706);

  final String label;
  final IconData icon;
  final bool warning;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const DashboardOperationButton({
    super.key,
    required this.label,
    required this.icon,
    this.warning = false,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = warning
        ? ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled)
                    ? _warningFill.withValues(alpha: 0.42)
                    : _warningFill),
            foregroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled)
                    ? Colors.white.withValues(alpha: 0.68)
                    : Colors.white),
          )
        : null;

    return FilledButton.icon(
      onPressed: enabled ? onTap : null,
      style: style,
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 18),
      label: AdaptiveSingleLineText(label),
    );
  }
}
