import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import '../../services/connection_settings_store.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../adaptive_ui.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showConsoleButton;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color dividerColor;
  final VoidCallback onConsolePressed;
  final String? activityLabel;

  const HomeAppBar({
    super.key,
    required this.showConsoleButton,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.dividerColor,
    required this.onConsolePressed,
    this.activityLabel,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 0.5);

  @override
  Widget build(BuildContext context) {
    final store = ConnectionSettingsStore.instance;
    final titleStyle = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: foregroundColor,
    );
    return AppBar(
      backgroundColor: backgroundColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: ValueListenableBuilder(
                  valueListenable: store.profilesChanged,
                  builder: (context, _, __) {
                    final device = store.activeDevice;
                    if (device == null) return const SizedBox.shrink();
                    final deviceStyle = titleStyle.copyWith(fontSize: 14);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 152),
                        child: Row(
                          children: [
                            SvgPicture.asset(
                              'assets/icons/router.svg',
                              key: const ValueKey('home_device_icon'),
                              width: 18,
                              height: 18,
                              excludeFromSemantics: true,
                              colorFilter: ColorFilter.mode(
                                Theme.of(context).colorScheme.primary,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Semantics(
                                label: device.name,
                                excludeSemantics: true,
                                child: MediaQuery.disableAnimationsOf(context)
                                    ? Text(device.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: deviceStyle)
                                    : AdaptiveMarqueeText(
                                        device.name,
                                        key: const ValueKey('home_device_name'),
                                        style: deviceStyle,
                                        startDelay:
                                            const Duration(milliseconds: 750),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .34),
              child: Text(
                tr('首页'),
                style: titleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (activityLabel != null)
                      SizedBox(
                        width: 36,
                        child: Center(
                          child: Semantics(
                            label: activityLabel,
                            liveRegion: true,
                            child: const SizedBox(
                              key: ValueKey('dashboard_activity_indicator'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                    if (showConsoleButton)
                      SizedBox(
                        width: 52,
                        height: kToolbarHeight,
                        child: Tooltip(
                          message: tr('控制台'),
                          child: _DashboardButton(
                            key: const ValueKey('home_console_button'),
                            color: foregroundColor,
                            onTap: onConsolePressed,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: dividerColor),
      ),
    );
  }
}

class _DashboardButton extends StatefulWidget {
  final VoidCallback onTap;
  final Color color;

  const _DashboardButton({super.key, required this.onTap, required this.color});

  @override
  State<_DashboardButton> createState() => _DashboardButtonState();
}

class _DashboardButtonState extends State<_DashboardButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: 0.78,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: ScaleTransition(
          scale: _scale,
          child: SvgPicture.asset(
            'assets/icons/console.svg',
            colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
            width: 22,
            height: 22,
            semanticsLabel: 'Zashboard',
          ),
        ),
      ),
    );
  }
}
