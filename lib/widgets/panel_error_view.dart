import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import '../services/app_platform.dart';

class PanelErrorView extends StatelessWidget {
  const PanelErrorView(
      {super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr(message), textAlign: TextAlign.center),
                if (AppPlatform.isIOS) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr('请检查控制器地址、网络连接，以及系统设置中的 Proxly 局域网权限。'),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: Text(tr('重试'))),
              ],
            ),
          ),
        ),
      );
}
