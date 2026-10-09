import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showConsoleButton;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color dividerColor;
  final VoidCallback onConsolePressed;
  final VoidCallback onCustomizePressed;
  final bool editing;
  final String? activityLabel;

  const HomeAppBar({
    super.key,
    required this.showConsoleButton,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.dividerColor,
    required this.onConsolePressed,
    required this.onCustomizePressed,
    this.editing = false,
    this.activityLabel,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 0.5);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: backgroundColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: showConsoleButton
          ? Tooltip(
              message: tr('控制台'),
              child: _DashboardButton(
                key: const ValueKey('home_console_button'),
                color: foregroundColor,
                onTap: onConsolePressed,
              ),
            )
          : null,
      title: Text(
        tr('首页'),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: foregroundColor,
        ),
      ),
      centerTitle: true,
      actions: [
        if (activityLabel != null)
          Center(
              child: Semantics(
                  label: activityLabel,
                  liveRegion: true,
                  child: const SizedBox(
                      key: ValueKey('dashboard_activity_indicator'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)))),
        IconButton(
          key: const ValueKey('home_customize_button'),
          tooltip: tr(editing ? '完成' : '自定义首页'),
          onPressed: onCustomizePressed,
          style: IconButton.styleFrom(overlayColor: Colors.transparent),
          icon: Icon(
              editing
                  ? Icons.check_rounded
                  : Icons.dashboard_customize_outlined,
              color: foregroundColor),
        ),
      ],
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
