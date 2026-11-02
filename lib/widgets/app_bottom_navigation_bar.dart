import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../services/app_platform.dart';
import '../theme/app_theme.dart';

class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Theme(
      // Match Android's Material 3 ripple without changing the iOS page theme.
      data: AppPlatform.isIOS
          ? theme.copyWith(splashFactory: InkSparkle.splashFactory)
          : theme,
      child: BottomNavigationBar(
        // Shifting moves the item while ink remains at the original tap position.
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: false,
        backgroundColor: palette.surface,
        unselectedItemColor: palette.textSecondary,
        selectedItemColor: theme.colorScheme.primary,
        currentIndex: currentIndex,
        onTap: onTap,
        items: [
          BottomNavigationBarItem(
              icon: const Icon(Icons.home_rounded), label: tr('首页')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.hub_outlined),
              activeIcon: const Icon(Icons.hub_rounded),
              label: tr('代理')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.lan_outlined),
              activeIcon: const Icon(Icons.lan_rounded),
              label: tr('连接')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.settings_rounded), label: tr('设置')),
        ],
      ),
    );
  }
}
