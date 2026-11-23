import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/app_locale.dart';
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
      data: theme.copyWith(
        highlightColor: Colors.transparent,
        splashFactory:
            kIsWeb ? InkRipple.splashFactory : InkSparkle.splashFactory,
      ),
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
              icon: _navigationIcon('assets/icons/proxy.svg'), label: tr('代理')),
          BottomNavigationBarItem(
              icon: _navigationIcon('assets/icons/link.svg'), label: tr('连接')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.settings_rounded), label: tr('设置')),
        ],
      ),
    );
  }

  Widget _navigationIcon(String asset) => Builder(builder: (context) {
        final style = IconTheme.of(context);
        return SvgPicture.asset(
          asset,
          width: style.size,
          height: style.size,
          colorFilter: ColorFilter.mode(style.color!, BlendMode.srcIn),
          excludeFromSemantics: true,
        );
      });
}
